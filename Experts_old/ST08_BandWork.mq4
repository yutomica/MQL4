/*

# ST08_BandWork
作成日：2017/9/3
更新日：2018/5/27

・バンドウォークを利用した順張りトレード

*/


#include <MyLib.mqh>

#define MAGIC 20160903
#define COMMENT "ST08_BandWork"

#define OBS_PERIOD PERIOD_D1
#define EXE_PERIOD PERIOD_H1

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int BBPeriod = 20;
extern double Kairi_lev = 0.008;
extern int jaw_period = 13;
extern int jaw_shift = 8;
extern int teeth_period = 8;
extern int teeth_shift = 5;
extern int lips_period = 5;
extern int lips_shift = 3;
extern int TSPoint = 10;
extern int TimeStopBars = 2;


/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
 
   double jaw_1 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,1,1);
   double jaw_2 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,1,2);
   double teeth_1 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,2,1);
   double teeth_2 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,2,2);
   double lips_1 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,3,1);
   double lips_2 = iAlligator(NULL,OBS_PERIOD,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,3,2);
      
   double BBMiddle_0_h = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,0); 
   double U3sig_1_h = iBands(NULL,EXE_PERIOD,BBPeriod,3,0,PRICE_CLOSE,MODE_UPPER,0);   
   double L3sig_1_h = iBands(NULL,EXE_PERIOD,BBPeriod,3,0,PRICE_CLOSE,MODE_LOWER,0); 
   double U1sig_1_h = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);   
   double L1sig_1_h = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   double U1sig_2_h = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,2);   
   double L1sig_2_h = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,2);

   //移動平均乖離率
   double kairi = MathAbs(1 - iClose(NULL,EXE_PERIOD,0)/BBMiddle_0_h);
   
   //Buy
   if(pos == 0       
      && jaw_1 < teeth_1 && teeth_1 < lips_1
      //&& jaw_2 < teeth_2 && teeth_2 < lips_2
      //&& jaw_1 > jaw_2 && teeth_1 > teeth_2 && lips_1 > lips_2
      && iClose(NULL,OBS_PERIOD,1) > teeth_1
      
      && iClose(NULL,EXE_PERIOD,1) > U1sig_1_h
      && iClose(NULL,EXE_PERIOD,2) > U1sig_2_h
      && kairi < Kairi_lev
      
      && Close[0] > Open[0]
      && Close[0] < U3sig_1_h
   ) ret = 1;
   //Sell
   if(pos == 0 
      && jaw_1 > teeth_1 && teeth_1 > lips_1
      //&& jaw_2 > teeth_2 && teeth_2 > lips_2
      //&& jaw_1 < jaw_2 && teeth_1 < teeth_2 && lips_1 < lips_2
      && iClose(NULL,OBS_PERIOD,1) < teeth_1
      
      && iClose(NULL,EXE_PERIOD,1) < L1sig_1_h
      && iClose(NULL,EXE_PERIOD,2) < L1sig_2_h
      && kairi < Kairi_lev
      
      && Close[0] < Open[0]
      && Close[0] > L3sig_1_h
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
   double BB_Middle = iBands(NULL,EXE_PERIOD,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,1);

   //Buy Close
   if(pos > 0 
      && BB_Middle > iClose(NULL,EXE_PERIOD,1)
   )ret = 1;

   //Sell Close
   if(pos < 0 
      && BB_Middle < iClose(NULL,EXE_PERIOD,1)
   ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}


int start()
{
   ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {

      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,iLow(NULL,OBS_PERIOD,1),0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,iHigh(NULL,OBS_PERIOD,1),0,COMMENT,MAGIC))
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

   return(0);
}
