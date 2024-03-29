/*

# STXX_MAPlusCandlestick
作成日：2018/3/10
更新日：2018/3/

・移動平均線とローソク足に着目したトレード

*/


#include <MyLib.mqh>

#define MAGIC 20180310
#define COMMENT "STXX_MAPlusCandlestick"

#define OBS_PERIOD PERIOD_H4
#define EXE_PERIOD PERIOD_M15

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int FastMAPeriod = 7;
extern int MiddleMAPeriod = 25;
extern int SlowMAPeriod = 50;
extern int TSPoint = 10;


/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
 
   double FMA_2 = iMA(NULL,0,FastMAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
   double FMA_1 = iMA(NULL,0,FastMAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
   double MMA_2 = iMA(NULL,0,MiddleMAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
   double MMA_1 = iMA(NULL,0,MiddleMAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
   double SMA_2 = iMA(NULL,0,SlowMAPeriod,0,MODE_SMA,PRICE_CLOSE,2);
   double SMA_1 = iMA(NULL,0,SlowMAPeriod,0,MODE_SMA,PRICE_CLOSE,1);
   
   //Buy
   if(pos == 0       
      && SMA_2 < MMA_2 && MMA_2 < FMA_2
      && SMA_1 < MMA_1 && MMA_1 < FMA_1
      && SMA_2 < SMA_1
      && MMA_2 < MMA_1
      && FMA_2 < FMA_1
      && High[2] > FMA_2 && Low[2] < FMA_2
      && Close[1] > FMA_1
   ) ret = 1;
   //Sell
   if(pos == 0 
      && SMA_2 > MMA_2 && MMA_2 > FMA_2
      && SMA_1 > MMA_1 && MMA_1 > FMA_1
      && SMA_2 > SMA_1
      && MMA_2 > MMA_1
      && FMA_2 > FMA_1
      && High[2] > FMA_2 && Low[2] < FMA_2
      && Close[1] < FMA_1
   ) ret = -1;
   
   return(ret);
   
}


int start()
{

   double SL;
   double spread = Ask - Bid;
   int sig_entry = EntrySignal(MAGIC);
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {
      SL = Low[1] - spread;
      if(Ask - SL < MarketInfo(Symbol(), MODE_STOPLEVEL)*Point){SL = Ask - spread - MarketInfo(Symbol(), MODE_STOPLEVEL)*Point;}
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      SL = High[1] + spread;
      if(SL - Bid - spread < MarketInfo(Symbol(), MODE_STOPLEVEL)*Point){SL = Bid + spread + MarketInfo(Symbol(), MODE_STOPLEVEL)*Point;}
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   //TrailingStop
   MyTrailingStop(TSPoint,MAGIC);   

   return(0);
}
