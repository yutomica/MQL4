/*

# STXX_FastTrade
作成日：2018/2/10
更新日：2017/

◆フィルタ
・40SMAより上に2SMA（高値）、2SMA（安値）が位置している
◆エントリー
・2SMA（安値）に直近値がタッチしたらエントリー
◆TP
・2SMA（高値）にタッチしたら利確
◆SL
・40SMAにタッチしたら損切

*/

#include <MyLib.mqh>

#define MAGIC 20180210
#define COMMENT "STXX_FastTrade"

extern int Slippage = 3;
extern int Fast_MAPeriod = 2;
extern int Slow_MAPeriod = 40;
extern int RSIPeriod = 14;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   double SMA_LOW = iMA(NULL,0,Fast_MAPeriod,0,MODE_SMA,PRICE_LOW,0);
   double SMA_HIGH = iMA(NULL,0,Fast_MAPeriod,0,MODE_SMA,PRICE_HIGH,0);
   double SMA_BASE = iMA(NULL,0,Slow_MAPeriod,0,MODE_SMA,PRICE_CLOSE,0);
   double RSI_0 = iRSI(NULL,0,RSIPeriod,PRICE_CLOSE,0);
   double RSI_1 = iRSI(NULL,0,RSIPeriod,PRICE_CLOSE,1);
   double RSI_2 = iRSI(NULL,0,RSIPeriod,PRICE_CLOSE,2);

   //40SMAよりも2SMAが上、かつ直近終値が安値2SMAにタッチしたら買い注文
   if(pos == 0 
      && SMA_BASE < SMA_HIGH && SMA_BASE < SMA_LOW 
      /*&& Close[1] > SMA_LOW*/ && Close[0] <= SMA_LOW
      && Low[0] > SMA_BASE 
      && RSI_0 < 70 && RSI_1 < 70 && RSI_2 < 70
   ) ret = 1;

   //40SMAよりも2SMAが下、かつ直近終値が高値2SMAにタッチしたら売り注文
   if(pos == 0 
      && SMA_BASE > SMA_HIGH && SMA_BASE > SMA_LOW 
      /*&& Close[1] < SMA_HIGH*/ && Close[0] >= SMA_HIGH
      && High[0] < SMA_BASE 
      && RSI_0 > 30 && RSI_1 > 30 && RSI_2 > 30
   ) ret = -1;
   
   return(ret);
   
}


/*
エキジット関数
*/
int ExitSignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;

   double SMA_LOW = iMA(NULL,0,Fast_MAPeriod,0,MODE_SMA,PRICE_LOW,0);
   double SMA_HIGH = iMA(NULL,0,Fast_MAPeriod,0,MODE_SMA,PRICE_HIGH,0);
   double SMA_BASE = iMA(NULL,0,Slow_MAPeriod,0,MODE_SMA,PRICE_CLOSE,0);
   
   //高値2SMAにタッチしたら利確
   if(pos > 0 /*&& Close[1] < SMA_HIGH*/ && Close[0] > SMA_HIGH) return ret = -1;
   //40SMAにタッチしたら損切
   if(pos > 0 && Close[0] <= SMA_BASE) return ret = -1;
   //安値2SMAにタッチしたら利確
   if(pos < 0 /*&& Close[1] > SMA_LOW*/ && Close[0] < SMA_LOW) return ret = 1;
   //40SMAにタッチしたら損切
   if(pos < 0 && Close[0] >= SMA_BASE) return ret = 1;
   
   return(ret);
}


int start()
{
   if(ExitSignal(MAGIC)!=0)
   {
      MyOrderClose(Slippage,MAGIC);
   }
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
   
   
   return(0);
}



