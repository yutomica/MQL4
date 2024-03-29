/*

# STXX_HKA
作成日：2017/2/26
更新日：2017/

・マルチタイム平均足を使った順張りトレード
・日足、４H足の反転を確認し、

*/

#include <MyLib.mqh>

#define MAGIC 20170226
#define COMMENT "STXX_HKA"

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
   double open_Day = iCustom(NULL,1440,IndicatorName,2,0);
   double Close_Day = iCustom(NULL,1440,IndicatorName,3,0);
   double Difference_Day = Close_Day - open_Day;
   double open_4H = iCustom(NULL,240,IndicatorName,2,0);
   double Close_4H = iCustom(NULL,240,IndicatorName,3,0);
   double Difference_4H = Close_4H - open_4H;

   //日足・４時間足の平均足が陽線で、トレードする足の平均足が陰線から陽線に変わったら買い注文
   if(pos == 0 && HaDifference2<0 && HaDifference1>0 && Difference_Day>0 && Difference_4H>0) ret = 1;

   //日足・４時間足の平均足が陰線で、トレードする足の平均足が陽線から陰線に変わったら売り注文
   if(pos == 0 && HaDifference2>0 && HaDifference1<0 && Difference_Day<0 && Difference_4H<0) ret = -1;
   
   return(ret);
   
}

extern int TSPoint = 10;
int start()
{
   int sig_entry = EntrySignal(MAGIC);

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
   
   MyTrailingStop(TSPoint,MAGIC);
   
   return(0);
}



