/*

# FXKouryaku_201808_HeikinAshi
作成日：2018/8/15
更新日：2018//

・平均足のダマシを利用するデイトレード
・トレンドフォロー

*/


#include <MyLib.mqh>

#define MAGIC 20180808
#define COMMENT "FXKouryaku_201808_HeikinAshi"


extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int SMAPeriod = 40;
extern int SLPips = 5;
extern string IndicatorName ="Heiken Ashi";
extern int i;


void init(){
   if(Digits == 3 || Digits == 5){SLPips*=10;}
}

/*
エントリー関数
*/

int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;

   double haOpen1 = iCustom(NULL,0,IndicatorName,2,1);//1つ前の足の平均足始値
   double haClose1 = iCustom(NULL,0,IndicatorName,3,1);//1つ前の足の平均足終値
   double haOpen2 = iCustom(NULL,0,IndicatorName,2,2);//2つ前の足の平均足始値
   double haClose2 = iCustom(NULL,0,IndicatorName,3,2);//2つ前の足の平均足終値
   double haOpen3 = iCustom(NULL,0,IndicatorName,2,3);//3つ前の足の平均足始値
   double haClose3 = iCustom(NULL,0,IndicatorName,3,3);//3つ前の足の平均足終値
   double haOpen4 = iCustom(NULL,0,IndicatorName,2,4);//4つ前の足の平均足始値
   double haClose4 = iCustom(NULL,0,IndicatorName,3,4);//4つ前の足の平均足終値
   double haOpen5 = iCustom(NULL,0,IndicatorName,2,5);//5つ前の足の平均足始値
   double haClose5 = iCustom(NULL,0,IndicatorName,3,5);//5つ前の足の平均足終値

   
   double SMA[3];
   for(int j=1;j<=3;j++){
      SMA[j-1] = iMA(NULL,0,SMAPeriod,0,MODE_SMA,PRICE_CLOSE,j);
   }

   //Buy
   if(pos == 0
      && SMA[1] > SMA[2] > SMA[3]
      && SMA[1] < haClose1
      && haOpen5 > haClose5
      && haOpen4 > haClose4
      && haOpen3 > haClose3
      && haOpen2 > haClose2
      && haOpen1 < haClose1
   ) ret = 1;
   //Sell
   if(pos == 0
      && SMA[1] < SMA[2] < SMA[3]
      && SMA[1] > haClose1
      && haOpen5 < haClose5
      && haOpen4 < haClose4
      && haOpen3 < haClose3
      && haOpen2 < haClose2
      && haOpen2 > haClose1
   ) ret = -1;

   return(ret);
   
}


int start()
{
   int sig_entry = EntrySignal(MAGIC);
   double sl;
   double tp;
   double haHL[4];
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {
      for(i=2;i<=5;i++){
         haHL[i-2] = iCustom(NULL,0,IndicatorName,1,i);//iつ前の足の平均足高値(陽線)／安値(陰線)
      }
      sl = haHL[ArrayMinimum(haHL)] - (Ask-Bid);
      tp = Ask + 1.5*(Ask-sl);
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,sl,tp,COMMENT,MAGIC))
      {
         
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   //Sell Order
   if(sig_entry < 0)
   {
      for(i=2;i<=5;i++){
         haHL[i-2] = iCustom(NULL,0,IndicatorName,1,i);//iつ前の足の平均足高値(陽線)／安値(陰線)
      }
      sl = haHL[ArrayMaximum(haHL)] + (Ask-Bid);
      tp = Bid - 1.5*(sl-Bid);
      Print(sl-Bid);
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,sl,tp,COMMENT,MAGIC))
      {
         
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   return(0);
}