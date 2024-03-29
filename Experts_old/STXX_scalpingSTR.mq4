/*

# STXX_scaplingSTR
作成日：2018/3/10
更新日：2018/3/

・RSIのみで売買する異色のトレード手法

*/


#include <MyLib.mqh>

#define MAGIC 20180310
#define COMMENT "STXX_ScalpingSTR"

#define OBS_PERIOD PERIOD_H4
#define EXE_PERIOD PERIOD_M15

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int RSIPeriod = 3;

/*RSI判定*/


/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
 
   double RSI_2 = iRSI(NULL,EXE_PERIOD,RSIPeriod,PRICE_CLOSE,2);
   double RSI_1 = iRSI(NULL,EXE_PERIOD,RSIPeriod,PRICE_CLOSE,1);
   double RSI_0 = iRSI(NULL,EXE_PERIOD,RSIPeriod,PRICE_CLOSE,0);
   
   //Buy
   if(pos == 0       
      && RSI_2 < 20
      && RSI_1 >= 20
      //&& RSI_0 < 80
   ) ret = 1;
   //Sell
   if(pos == 0 
      && RSI_2 > 80
      && RSI_1 <= 80
      //&& RSI_0 > 20
   ) ret = -1;
   
   return(ret);
   
}


/*
フィルタ関数
*/
int FilterSignal(int signal)
{
   double RSI_2 = iRSI(NULL,OBS_PERIOD,RSIPeriod,PRICE_CLOSE,2);
   double RSI_1 = iRSI(NULL,OBS_PERIOD,RSIPeriod,PRICE_CLOSE,1);
   double RSI_0 = iRSI(NULL,OBS_PERIOD,RSIPeriod,PRICE_CLOSE,0);
   
   int ret = 0;
   if(signal > 0 
      && RSI_2 < 20
      && RSI_1 >= 20
      && RSI_0 < 80
   ) ret = signal;
   if(signal < 0
      && RSI_2 > 80
      && RSI_1 <= 80
      && RSI_0 > 20   
   ) ret = signal;
   
   return(ret);
}



int start()
{

   double SL;double TP;
   int sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {
      SL = Low[1];
      TP = Ask + (Ask - SL)*1.5;
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      SL = High[1];
      TP = Bid - (SL - Bid)*1.5;
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }

   return(0);
}
