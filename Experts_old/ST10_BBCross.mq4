/*

# ST10_BBCross
作成日：2017/9/3
更新日：2017//

・ボリンジャーバンド(短期＋長期)のクロスによるトレード

*/


#include <MyLib.mqh>

#define MAGIC 20160903
#define COMMENT "ST07_BandMACross"

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int FastBBPeriod = 5;
extern int SlowBBPeriod = 20;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double Slow_U1sig_2;double Slow_U1sig_1;
   double Slow_L1sig_2;double Slow_L1sig_1;
   double Slow_MD_1;
   double Fast_U2sig_2;double Fast_U2sig_1;
   double Fast_L2sig_2;double Fast_L2sig_1;
   int ret = 0;
   
   Slow_U1sig_2 = iBands(NULL,0,SlowBBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,2);
   Slow_U1sig_1 = iBands(NULL,0,SlowBBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   Slow_L1sig_2 = iBands(NULL,0,SlowBBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,2);
   Slow_L1sig_1 = iBands(NULL,0,SlowBBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   Slow_MD_1 = iBands(NULL,0,SlowBBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,1);
   Fast_U2sig_2 = iBands(NULL,0,FastBBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,2);
   Fast_U2sig_1 = iBands(NULL,0,FastBBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,1);
   Fast_L2sig_2 = iBands(NULL,0,FastBBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,2);
   Fast_L2sig_1 = iBands(NULL,0,FastBBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,1);
   
   //Buy Entry
   //短期の＋2σが長期の＋１σを上抜け
   if(pos == 0 
      && Fast_U2sig_2 < Slow_U1sig_2
      && Fast_U2sig_1 > Slow_U1sig_1
      && Close[1] > Slow_MD_1
   ) ret = 1;
   
   //Sell Entry
   //短期の―2σが長期の－１σをした抜け
   if(pos == 0 
      && Fast_L2sig_2 > Slow_L1sig_2
      && Fast_L2sig_1 < Slow_L1sig_1
      && Close[1] < Slow_MD_1
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

   //Buy Close
   //直近3本の安値を下抜け
   if(pos > 0 
      && Close[1] < Low[4]
      && Close[1] < Low[3]
      && Close[1] < Low[2]
   )ret = 1;

   //Sell Close
   //直近3本の高値を上抜け
   if(pos < 0 
      && Close[1] > High[4]
      && Close[1] > High[3]
      && Close[1] > High[2]
   ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}


/*
フィルタ関数
*/
int FilterSignal(int signal)
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


extern int ATRPeriod = 14;
extern double ATRMult = 2.0;
extern int TSPoint = 10;
int start()
{
   double atr;
   
   ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
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



