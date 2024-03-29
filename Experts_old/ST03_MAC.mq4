/*

# ST03_MAC
作成日：2016/12/25
更新日：2017/2/25

・移動平均線のクロスをシグナルとしたエントリー
・フィルタに日足ベースの平均足を利用

*/

#include <MyLib.mqh>

#define MAGIC 20161225
#define COMMENT "ST03_MAC"

extern int Slippage = 3;

/*
エントリー関数
*/
extern int FMA_Period = 15;
extern int SMA_Period = 35;
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double FMA_2 = iMA(NULL,0,FMA_Period,0,MODE_SMA,PRICE_CLOSE,2);
   double FMA_1 = iMA(NULL,0,FMA_Period,0,MODE_SMA,PRICE_CLOSE,1);
   double SMA_2 = iMA(NULL,0,SMA_Period,0,MODE_SMA,PRICE_CLOSE,2);
   double SMA_1 = iMA(NULL,0,SMA_Period,0,MODE_SMA,PRICE_CLOSE,1);
   
   //Buy
   if(pos == 0 && FMA_2 < SMA_2 && FMA_1 >= SMA_1) ret = 1;
   //Sell
   if(pos == 0 && FMA_2 > SMA_2 && FMA_1 <= SMA_1) ret = -1;
   
   return(ret);
   
}


/*
エキジット関数
*/
void ExitPosition(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double FMA_2 = iMA(NULL,0,FMA_Period,0,MODE_SMA,PRICE_CLOSE,2);
   double FMA_1 = iMA(NULL,0,FMA_Period,0,MODE_SMA,PRICE_CLOSE,1);
   double SMA_2 = iMA(NULL,0,SMA_Period,0,MODE_SMA,PRICE_CLOSE,2);
   double SMA_1 = iMA(NULL,0,SMA_Period,0,MODE_SMA,PRICE_CLOSE,1);
   
   if(pos > 0 && FMA_2 > SMA_2 && FMA_1 <= SMA_1) ret = 1;
   if(pos < 0 && FMA_2 < SMA_2 && FMA_1 >= SMA_1) ret = -1;
   
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

/*
extern int ATRPeriod = 20;
extern double ATRMult = 2.0;
extern int TimeStop_bars = 10;
*/
int start()
{
   
   ExitPosition(MAGIC);
   
   int sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   double order_lots = 0.01;

   //Buy Order
   if(sig_entry > 0)
   {
      //MyOrderClose(Slippage,MAGIC);
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,0,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      //MyOrderClose(Slippage,MAGIC);
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,0,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   //TrailingStop
   //MyTrailingStopATR(ATRPeriod,ATRMult,MAGIC);
   
   //TimeStop_Exit
   //TimeStop_Exit(Slippage,TimeStop_bars,MAGIC);

   return(0);
}



