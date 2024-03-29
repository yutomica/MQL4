/*

# ST09_BandMACross
作成日：2017/9/3
更新日：2017//

・ボリンジャーバンド1σとMAのクロスによるトレード

*/


#include <MyLib.mqh>

#define MAGIC 20160903
#define COMMENT "ST07_BandMACross"

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int BBPeriod = 20;
extern int MAPeriod = 5;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double U1sig_2;double U1sig_1;
   double L1sig_2;double L1sig_1;
   double MD_2;double MD_1;
   double MA_2;double MA_1;
   int ret = 0;
   
   U1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,2);
   U1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   L1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,2);
   L1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   MD_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,2);
   MD_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,1);
   MA_2 = iMA(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
   MA_1 = iMA(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
   
   if(pos == 0 
      && MD_2 < MD_1
      && U1sig_2 > MA_2
      && U1sig_1 < MA_1
      && Close[1] > MD_1
   ) ret = 1;
   if(pos == 0 
      && MD_2 > MD_1
      && L1sig_2 < MA_2
      && L1sig_1 > MA_1
      && Close[1] < MD_1
   ) ret = -1;
   
   return(ret);
}

/*
エキジット関数
*/
void ExitPosition(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double U1sig_1;
   double L1sig_1;
   double MA_1;
   int ret = 0;
   
   U1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   L1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   MA_1 = iMA(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,1);

   //Buy Close
   if(pos > 0 
      && U1sig_1 > MA_1
   )ret = 1;

   //Sell Close
   if(pos < 0 
      && L1sig_1 < MA_1
   ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}


/*
フィルタ関数
*/
/*int FilterSignal(int signal)
{
   int ret = 0;
   string IndicatorName ="Heiken Ashi";
   double open_Day1 = iCustom(NULL,1440,IndicatorName,2,1);
   double Close_Day1 = iCustom(NULL,1440,IndicatorName,3,1);
   double Difference_Day1 = Close_Day1 - open_Day1;
   double open_Day2 = iCustom(NULL,1440,IndicatorName,2,2);
   double Close_Day2 = iCustom(NULL,1440,IndicatorName,3,2);
   double Difference_Day2 = Close_Day2 - open_Day2;
   
   if(signal>0 && Difference_Day2>0 && Difference_Day1>0 ) ret = signal;
   if(signal<0 && Difference_Day2<0 && Difference_Day1<0 ) ret = signal;
   
   return(ret);

}
*/

extern int ATRPeriod = 14;
extern double ATRMult = 2.0;
extern int TSPoint = 10;
int start()
{
   double atr;
   
   ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   //sig_entry = FilterSignal(sig_entry);
   
   //ロット数計算
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   //Print("lotsize=",lotsize," order_lots=",order_lots);
   order_lots = 0.01;
   
   
   //Buy Order
   if(sig_entry > 0)
   {
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,0,0,COMMENT,MAGIC);
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,0,0,COMMENT,MAGIC);
   }
   
   //TimeStop_Exit(Slippage,3,MAGIC);
   
   //MyTrailingStop(TSPoint,MAGIC);
   
   return(0);
}



