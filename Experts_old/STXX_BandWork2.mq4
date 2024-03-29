/*

# STXX_BandWork2
作成日：2018/2/27
更新日：2018/3/1

・バンドウォークを利用した順張りトレード

*/


#include <MyLib.mqh>

#define MAGIC 20180227
#define COMMENT "STXX_BandWork2"

extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int BBPeriod = 20;
extern double order_lots = 0.01;
extern int max_orders = 20;

extern double Kairi_lev = 0.008;

double lastorder_price;

datetime Bar_Time = 0;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   //double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   
   double U1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   double L1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   double BBMiddle_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,1);
   double U1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,2);
   double L1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,2);
   double BBMiddle_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,2);

   //Buy
   if(/*pos == 0 
      &&*/ Close[2] > U1sig_2 && Close[1] > U1sig_1 
      && BBMiddle_2 < BBMiddle_1
   ) ret = 1;
   //Sell
   if(/*pos == 0 
      &&*/ Close[2] < L1sig_2 && Close[1] < L1sig_1 
      && BBMiddle_2 > BBMiddle_1
   ) ret = -1;
   
   return(ret);
   
}


/*
エキジット関数
*/
int ExitPosition(int magic)
{

   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double U1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   double L1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   double U1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,2);
   double L1sig_2 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,2);

   //Buy Close
   if(pos > 0
      && U1sig_2 > Close[2] && U1sig_1 > Close[1]
   )ret = 1;

   //Sell Close
   if(pos < 0
      && L1sig_2 < Close[2] && L1sig_1 < Close[1]
   ) ret = -1;

   if(ret!=0){
      MyOrderClose(Slippage,magic);
      return 0;
   }
   else{
      return 1;
   }
}



int start()
{

   int TPGrid = 50;
   if(ExitPosition(MAGIC)==0){
      lastorder_price = 0;
   }
   int sig_entry = EntrySignal(MAGIC);
   if(Digits == 3 || Digits == 5) TPGrid *= 10;
   double U1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_UPPER,1);
   double L1sig_1 = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_LOWER,1);
   
   //Buy Order
   if(sig_entry > 0 && OrdersTotal() <= max_orders && (Ask > lastorder_price + TPGrid*Point || lastorder_price == 0))
   {  
      Print(TPGrid);
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,0,0,COMMENT,MAGIC))
      {
         lastorder_price = Ask;
         MyOrderModify(U1sig_1,0,MAGIC);
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0 && OrdersTotal() <= max_orders && (Bid < lastorder_price - TPGrid*Point || lastorder_price == 0))
   {
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,0,0,COMMENT,MAGIC))
      {
         lastorder_price = Bid;
         MyOrderModify(L1sig_1,0,MAGIC);
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   //TimeStop_Exit
   //TimeStop_Exit(Slippage,0,4,MAGIC);
   Print(Bar_Time);

   return(0);
}
