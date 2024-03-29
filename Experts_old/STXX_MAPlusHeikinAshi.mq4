/*

# STXX_MAPlusHeikinAshi
作成日：2018/3/11
更新日：2018/3/

・移動平均線と平均足に着目したトレード

*/


#include <MyLib.mqh>

#define MAGIC 20180311
#define COMMENT "STXX_MAPlusHeikinAshi"


extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int MAPeriod = 30;
extern int FilterRange = 3;
extern int TimeStopBars = 2;

/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
 
   double MADirec[10];
   for(int j=1;j<=10;j++){
      MADirec[j] = iMA(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,j) - iMA(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,j+1);
   }
   double HeikinAshiDirec[10];
   for(int i=1;i<=10;i++){
      HeikinAshiDirec[i] = iCustom(NULL,0,"Heiken Ashi",3,i) - iCustom(NULL,0,"Heiken Ashi",2,i);
   }
   
   //Buy
   if(pos == 0       
      && MADirec[1] > 0 && MADirec[2] > 0 && MADirec[3] > 0
      && HeikinAshiDirec[2] < 0
      && HeikinAshiDirec[1] > 0
   ) ret = 1;
   //Sell
   if(pos == 0 
      && MADirec[1] < 0 && MADirec[2] < 0 && MADirec[3] < 0
      && HeikinAshiDirec[2] > 0
      && HeikinAshiDirec[1] < 0
   ) ret = -1;
   
   return(ret);
   
}


/*
エキジット関数
*/
void ExitPosition(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double HeikinAshiDrec_1 = iCustom(NULL,0,"Heiken Ashi",3,1) - iCustom(NULL,0,"Heiken Ashi",2,1);
   
   int ret = 0;
   if(pos > 0 && HeikinAshiDrec_1 < 0) ret = 1;
   if(pos < 0 && HeikinAshiDrec_1 > 0) ret = -1;
   
   if(ret!=0)
   {
      MyOrderClose(Slippage,magic);
      //Sleep(PeriodSeconds(60)*1000);
   }

}

int start()
{

   double SL;
   int sig_entry = EntrySignal(MAGIC);
   ExitPosition(MAGIC);
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.1;
   
   //Buy Order
   if(sig_entry > 0)
   {
      SL = MathMin(iCustom(NULL,0,"Heiken Ashi",0,1),iCustom(NULL,0,"Heiken Ashi",1,1));
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Buy Order Executed",1);
      }
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      SL = MathMax(iCustom(NULL,0,"Heiken Ashi",0,1),iCustom(NULL,0,"Heiken Ashi",1,1));
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,0,COMMENT,MAGIC))
      {
         //MySendMail(COMMENT+":Sell Order Executed",2);
      }
   }
   
   //TrailingStop
   //MyTrailingStop(TSPoint,MAGIC);   
   
   //TimeStop_Exit
   //TimeStop_Exit(Slippage,0,TimeStopBars,MAGIC);
   
   return(0);
}
