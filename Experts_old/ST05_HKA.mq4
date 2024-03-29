/*

# ST05_HKA
作成日：2017/2/26
更新日：2017/

・マルチタイム平均足を使った順張りトレード
・日足、４H足の反転を確認し、

*/

#include <MyLib.mqh>

#define MAGIC 20170226
#define COMMENT "ST05_HKA"

extern int Slippage = 3;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   string IndicatorName ="Heiken Ashi";
   double haopen1 = iCustom(NULL,0,IndicatorName,2,1);//１つ前の足の平均足始値
   double haClose1 = iCustom(NULL,0,IndicatorName,3,1);//１つ前の足の平均足終値
   double haopen2 = iCustom(NULL,0,IndicatorName,2,2);//２つ前の足の平均足始値
   double haClose2 = iCustom(NULL,0,IndicatorName,3,2);//２つ前の足の平均足終値
   double HaDifference1 = haClose1 - haopen1;//この値がマイナスなら赤色、プラスなら白色
   double HaDifference2 = haClose2 - haopen2;//この値がマイナスなら赤色、プラスなら白色
   

   //平均足が陰線から陽線に変わったら買い注文
   if(pos == 0 && HaDifference2<0 && HaDifference1>0) ret = 1;

   //平均足が陽線から陰線に変わったら売り注文
   if(pos == 0 && HaDifference2>0 && HaDifference1<0) ret = -1;
   
   return(ret);
   
}

/*
エキジット関数
*/
void ExitPosition(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   string IndicatorName ="Heiken Ashi";
   double haopen1 = iCustom(NULL,0,IndicatorName,2,1);//１つ前の足の平均足始値
   double haClose1 = iCustom(NULL,0,IndicatorName,3,1);//１つ前の足の平均足終値
   double haopen2 = iCustom(NULL,0,IndicatorName,2,2);//２つ前の足の平均足始値
   double haClose2 = iCustom(NULL,0,IndicatorName,3,2);//２つ前の足の平均足終値
   double HaDifference1 = haClose1 - haopen1;//この値がマイナスなら赤色、プラスなら白色
   double HaDifference2 = haClose2 - haopen2;//この値がマイナスなら赤色、プラスなら白色
   
   if(pos > 0 && HaDifference1<0 && HaDifference2>0) ret = 1;
   if(pos < 0 && HaDifference1>0 && HaDifference2<0) ret = -1;
   
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
   double open_4H1 = iCustom(NULL,240,IndicatorName,2,1);
   double Close_4H1 = iCustom(NULL,240,IndicatorName,3,1);
   double Difference_4H1 = Close_4H1 - open_4H1;
   double open_4H2 = iCustom(NULL,240,IndicatorName,2,2);
   double Close_4H2 = iCustom(NULL,240,IndicatorName,3,2);
   double Difference_4H2 = Close_4H2 - open_4H2;
   
   if(signal>0 && Difference_Day2>0 && Difference_Day1>0/* && Difference_4H2>0 && Difference_4H1>0*/) ret = signal;
   if(signal<0 && Difference_Day2<0 && Difference_Day1<0/* && Difference_4H2<0 && Difference_4H1<0*/) ret = signal;
   
   return(ret);

}

extern int ATRPeriod = 14;
extern double ATRMult = 2.0;
extern int TSPoint = 10;
int start()
{
   ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);

   double order_lots = 0.01;
   double atr;

   //Buy Order
   if(sig_entry > 0)
   {
      //MyOrderClose(Slippage,MAGIC);
      atr = iATR(NULL,0,ATRPeriod,1)*ATRMult;
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,Ask - atr,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      //MyOrderClose(Slippage,MAGIC);
      atr = iATR(NULL,0,ATRPeriod,1)*ATRMult;
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,Bid + atr,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   MyTrailingStopATR(ATRPeriod,ATRMult,MAGIC);
   //TimeStop_Exit(Slippage,3,MAGIC);
   
   return(0);
}



