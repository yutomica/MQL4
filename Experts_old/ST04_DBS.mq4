/*

# ST04_DBS
作成日：2017/2/25
更新日：2017/

・ダイナミックブレイクアウトシステム（DBS）
・移動平均線のクロスをシグナルとしたエントリー
・移動平均期間をボラティリティに合わせて調整

*/

#include <MyLib.mqh>

#define MAGIC 20170225
#define COMMENT "ST04_DBS"

extern int Slippage = 3;

/*
エントリー関数
*/
int EntrySignal(int magic,int FMA_Period,int SMA_Period)
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
void ExitPosition(int magic,int FMA_Period,int SMA_Period)
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

int start()
{
   
   int Floor1 = 12;int Floor2 = 24;
   int Ceiling1 = 23;int Ceiling2 = 50;
   double x = iStdDev(NULL,0,20,0,MODE_SMA,PRICE_CLOSE,1);
   double y = iStdDev(NULL,0,20,0,MODE_SMA,PRICE_CLOSE,2);
   double xx = iStdDev(NULL,0,30,0,MODE_SMA,PRICE_CLOSE,1);
   double yy = iStdDev(NULL,0,30,0,MODE_SMA,PRICE_CLOSE,2);
   double delta_vol1 = (x-y)/x;
   double delta_vol2 = (xx-yy)/xx;
   
   static int var_a = 12;//FMA
   static int var_b = 24;//SMA
   
   var_a *= MathCeil(1+delta_vol1);
   var_a = MathMax(var_a,Floor1);
   //var_a = MathMin(var_a,Ceiling1);
   var_b *= MathCeil(1+delta_vol2);
   var_b = MathMax(var_b,Floor2);
   //var_b = MathMin(var_b,Ceiling2);
   Print(delta_vol1," ",delta_vol2,"A: ",var_a,", B: ",var_b);
   
   ExitPosition(MAGIC,var_a,var_b);
   int sig_entry = EntrySignal(MAGIC,var_a,var_b);

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



