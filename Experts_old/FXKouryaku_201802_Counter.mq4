/*

# FXKouryaku_201802_RangeCounter
作成日：2018/4/22
更新日：2018/4/

・

*/


#include <MyLib.mqh>

#define MAGIC 20180422
#define COMMENT "FXKouryaku_201802_RangeCounter"


extern double Safety_ratio = 3.0;
extern int Slippage = 3;

extern int SLPips = 10;
extern double TPRange = 1.5;


void init(){
   if(Digits == 3 || Digits == 5){
      SLPips *= 10;
   }  
}

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   double KLine[10];
   for(int j=1;j<=10;j++){
      KLine[j] = iStochastic(NULL,0,5,3,3,MODE_SMA,1,0,j);
   }
   double DLine[10];
   for(int k=1;k<=10;k++){
      DLine[k] = iStochastic(NULL,0,5,3,3,MODE_SMA,1,1,k);
   }
   
   double Range_Upper = High[iHighest(NULL,PERIOD_D1,MODE_HIGH,3,1)];
   double Range_Lower = Low[iLowest(NULL,PERIOD_D1,MODE_LOW,3,1)];

   
   /*Buy*/
   if(pos == 0 
      //&& Low[iLowest(NULL,0,MODE_LOW,4,2)] < Range_Lower
      && Low[2] < Range_Lower
      && Low[1] > Range_Lower
      && Close[1] > Open[1]
      && DLine[2] < 20
      && DLine[1] > 20
   ) ret = 1;
   
   /*Sell*/
   if(pos == 0 
      //&& High[iHighest(NULL,0,MODE_HIGH,4,2)] > Range_Upper
      && High[2] > Range_Upper
      && High[1] < Range_Upper
      && Close[1] < Open[1]
      && DLine[2] > 80
      && DLine[1] < 80
   ) ret = -1;
   
   return(ret);
   
}

int start()
{
   int sig_entry = EntrySignal(MAGIC);

   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   double SL = 0;
   double TP = 0;

   //Buy Order
   if(sig_entry > 0)
   {
      SL = Low[iLowest(NULL,PERIOD_D1,MODE_LOW,3,1)]-SLPips*Point;
      TP = (Ask - SL)*TPRange;
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,Ask+TP,COMMENT,MAGIC);
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      SL = High[iHighest(NULL,PERIOD_D1,MODE_HIGH,3,1)]+SLPips*Point;
      TP = (SL - Bid)*TPRange;
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,Bid-TP,COMMENT,MAGIC);
   }
   
   return(0);
}
