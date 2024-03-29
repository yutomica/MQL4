/*

# ST15_MACDEnt
作成日：2018/9/29
更新日：2018//

・日足ベースSMAでトレンド判定
・MACDでエントリーを判断

*/


#include <stderror.mqh>
#include <stdlib.mqh>
#include <WinUser32.mqh>
#include <Original/Mylib.mqh>
#include <Original/Basic.mqh>
#include <Original/DateAndTime.mqh>
#include <Original/LotSizing.mqh>
#include <Original/TrailingStop.mqh>
#include <Original/TimeStop.mqh>
#include <Original/Tracker.mqh>
//#include <Original/OrderHandle.mqh>
//#include <Original/OrderReliable.mqh>
//#include <Original/Mail.mqh>

#define MAGIC 20180929
#define COMMENT "ST15_MACDENT"

#define OBS_PERIOD PERIOD_D1
#define EXE_PERIOD PERIOD_H1

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int Fast_MAPeriod = 21;
extern int Middle_MAPeriod = 75;
extern int Slow_MAPeriod = 200;
extern int Fast_MACDPeriod = 8;
extern int Slow_MACDPeriod = 17;
extern int Sig_MACDPeriod = 9;

extern int TimeStopBars = 10;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
 
   double macd[2];
   for(int j=1;j<3;j++){
      macd[j-1] = iMACD(NULL,EXE_PERIOD,Fast_MACDPeriod,Slow_MACDPeriod,Sig_MACDPeriod,PRICE_CLOSE,0,j);
   }

   double macdsig[2];
   for(j=1;j<3;j++){
      macdsig[j-1] = iMACD(NULL,EXE_PERIOD,Fast_MACDPeriod,Slow_MACDPeriod,Sig_MACDPeriod,PRICE_CLOSE,1,j);
   }   

   //Buy
   if(pos == 0       
      && macd[0] > macdsig[0] && macd[1] < macdsig[1]
      && macd[0] < 0
   ) ret = 1;
   //Sell
   if(pos == 0 
      && macd[0] < macdsig[0] && macd[1] > macdsig[1]
      && macd[0] > 0
   ) ret = -1;
   
   return(ret);
   
}


/*
エキジット関数
*/
void ExitPosition(int magic)
{

   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   double macd[2];
   for(int j=1;j<3;j++){
      macd[j-1] = iMACD(NULL,EXE_PERIOD,Fast_MACDPeriod,Slow_MACDPeriod,Sig_MACDPeriod,PRICE_CLOSE,0,j);
   }

   double macdsig[2];
   for(j=1;j<3;j++){
      macdsig[j-1] = iMACD(NULL,EXE_PERIOD,Fast_MACDPeriod,Slow_MACDPeriod,Sig_MACDPeriod,PRICE_CLOSE,1,j);
   }  
   
   //Buy Close
   if(pos > 0 
      && macd[0] < macdsig[0] && macd[1] > macdsig[1]
   )ret = 1;

   //Sell Close
   if(pos < 0 
      && macd[0] > macdsig[0] && macd[1] > macdsig[1] 
   ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}

/*
フィルタ関数
*/
int FilterSignal(int signal)
{
   int ret = 0;
   double fastma[2];
   for(int j=1;j<3;j++){
      fastma[j-1] = iMA(NULL,OBS_PERIOD,Fast_MAPeriod,0,MODE_SMA,PRICE_CLOSE,j);
   }
   double middlema[2];
   for(j=1;j<3;j++){
      middlema[j-1] = iMA(NULL,OBS_PERIOD,Middle_MAPeriod,0,MODE_SMA,PRICE_CLOSE,j);
   }   
   double slowma[2];
   for(j=1;j<3;j++){
      slowma[j-1] = iMA(NULL,OBS_PERIOD,Slow_MAPeriod,0,MODE_SMA,PRICE_CLOSE,j);
   }
      
   if(signal>0 
      && fastma[1] < fastma[0] && middlema[1] < middlema[0] //&& slowma[1] < slowma[0]
      && fastma[0] > middlema[0] //&& middlema[0] > slowma[0]
      && iClose(NULL,OBS_PERIOD,1) > fastma[0]
   ) ret = signal;
   if(signal<0
      && fastma[1] > fastma[0] && middlema[1] > middlema[0] //&& slowma[1] > slowma[0]
      && fastma[0] < middlema[0] //&& middlema[0] < slowma[0]
      && iClose(NULL,OBS_PERIOD,1) < fastma[0]
   ) ret = signal;
   
   return(ret);

}


int start()
{
   //ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.01;
   
   //Buy Order
   if(sig_entry > 0)
   {

      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,0,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,0,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   //TrailingStop
   //MyTrailingStop(TSPoint,MAGIC);
   
   //TrailingStop_ATR
   //MyTrailingStopATR(ATRPeriod,ATRMult,MAGIC);
   
   //TimeStop_Exit
   //TimeStop_Exit(Slippage,EXE_PERIOD,TimeStopBars,MAGIC);
   
   TimeStop_Exit_Force(Slippage,NULL,100,MAGIC);

   return(0);
}
