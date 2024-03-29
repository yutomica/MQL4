/*

# ST02_3sigRebound
作成日：2016/8/18
更新日：2019/7/27

<概要>
ボリンジャーバンド±3σ（BB3）にタッチしたタイミングでの逆張りトレード

<要件>
・EN:BB3を超えた時点で、Entry_margin先に指値注文をセット
・EX：なし
・TP：パラメータ（TP_pips）
・SL:パラメータ（SL_pips）

*/

#include <MyLib.mqh>

#define MAGIC 20160818
#define COMMENT "ST02_3sigRebound"

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int BBPeriod = 20;
extern int TP_pips = 10;
extern int SL_pips = 50;


void init()
{
   if(Digits == 3 || Digits == 5){
      TP_pips *= 10;
      SL_pips *= 10;
   }
}


/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double U3sig_0 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_UPPER,0);
   double L3sig_0 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_LOWER,0);
   double U4sig_0 = iBands(NULL, 0, BBPeriod, 4, 0, PRICE_CLOSE,MODE_UPPER,0);
   double L4sig_0 = iBands(NULL, 0, BBPeriod, 4, 0, PRICE_CLOSE,MODE_LOWER,0);
   int ret = 0;
   
   /*Buy*/
   if(pos == 0 && Ask <= L3sig_0 && Ask > L4sig_0) ret = 1;
   
   /*SellLimit*/
   if(pos == 0 && Bid >= U3sig_0 && Bid < U4sig_0) ret = -1;
   
   return(ret);
   
}


/*
待機注文のストップ関数
*/
void KillOrder(int magic)
{
   double U3sig_1 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_UPPER,1);
   double L3sig_1 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_LOWER,1);
   double U3sig_0 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_UPPER,0);
   double L3sig_0 = iBands(NULL, 0, BBPeriod, 3, 0, PRICE_CLOSE,MODE_LOWER,0);

   /*Kill BuyLimit*/
   if(
      MyCurrentOrders(OP_BUYLIMIT,magic)>0 
      && Ask > L3sig_0
   ) MyOrderDelete(magic);

   /*Kill SellLimit*/
   if(MyCurrentOrders(
      OP_SELLLIMIT,magic)<0 
      && Bid < U3sig_0
   ) MyOrderDelete(magic);
}

int start()
{
   double order_price;
   int sig_entry = EntrySignal(MAGIC);
   
   //ロット判定
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {
      order_price = Ask;
      MyOrderSend(OP_BUY,order_lots,order_price,Slippage,order_price-SL_pips*Point,order_price+TP_pips*Point,COMMENT,MAGIC);
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      order_price = Bid;
      MyOrderSend(OP_SELL,order_lots,order_price,Slippage,order_price+SL_pips*Point,order_price-TP_pips*Point,COMMENT,MAGIC);
   }   
   
   //TimeStop_Exit(Slippage,0,3,MAGIC);
   
   return(0);
}



