/*
# STR02
作成日：2022/05/06
更新日：2022//



◆トレンド反転でクローズ

*/

#include <stderror.mqh>
#include <stdlib.mqh>
#include <WinUser32.mqh>
//#include <Original/Application.mqh>
#include <Original/Mylib.mqh>
#include <Original/Basic.mqh>
#include <Original/DateAndTime.mqh>
#include <Original/LotSizing.mqh>
#include <Original/TrailingStop.mqh>
#include <Original/TimeStop.mqh>
#include <Original/Mail.mqh>
#include <Original/Tracker.mqh>
//#include <Original/OrderHandle.mqh>
//#include <Original/OrderReliable.mqh>

#define MAGIC 20220506
#define COMMENT "STR02"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int TPPips = 5;
extern int TimeStop_bars = 10;
extern int HLPeriod = 20;
extern int BBPeriod = 25;


//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    fileHandle;
int    sig_entry;
double order_lots;
double TP,SL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  if(Digits == 3 || Digits == 5){
   TPPips = TPPips*10;
  }
    
  /*Edge Validation*/
  /*string outfile = "_tmp.csv";
  fileHandle = FileOpen(outfile,FILE_CSV|FILE_WRITE,",");
  */
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  FileClose(fileHandle);
}



/*
エントリー関数

◆日足、20期間HLバンド、ミドルラインの上下でトレンド判定
・終値がミドルラインを上/下回り、かつ陽/陰線であればトレンド開始
・終値がミドルラインを上/下回ったらトレンド修了
◆トレンド内の押し目でエントリー
・15分足、25期間BBの上/下2σを終値が上/下回ったらSell/Buy
・SLは日足20期間HLバンドのミドルライン

*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double BB2sigU_1 = iBands(NULL,PERIOD_M15,BBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,1);
   double BB2sigL_1 = iBands(NULL,PERIOD_M15,BBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,1);
   //BUY：
   if(pos == 0 && Close[1] < BB2sigL_1) ret = 1;
   //Sell：
   if(pos == 0 && Close[1] > BB2sigU_1) ret = -1;
   
   return(ret);
   
}



/*
エキジット関数
*/
void ExitPosition(int magic)
{
   int ret = 0;
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double HLmid_1 = iCustom(NULL,PERIOD_D1,"HLBand",HLPeriod,0,0,1);
    
   //Buy Close
   if(pos > 0 && Close[1] < HLmid_1) ret = 1;

   //Sell Close
   if(pos < 0 && Close[1] > HLmid_1) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}



/*
フィルタ関数
*/
int FilterSignal(int signal)
{
   int ret = 0;
   double HLmid_1 = iCustom(NULL,PERIOD_D1,"HLBand",HLPeriod,0,0,1);
   
   if(signal>0 && Close[1] > HLmid_1 && Close[1] > Open[1]) ret = signal;
   if(signal<0 && Close[1] < HLmid_1 && Close[1] < Open[1]) ret = signal;
   
   return(ret);

}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   //if(newBar==True){Tracker(fileHandle,MAGIC);}
   //Tracker(fileHandle,MAGIC);
   
   ExitPosition(MAGIC);
   sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   order_lots = 0.1;
   
   if(newBar==True && sig_entry>0){
      SL = 0;
      TP = 0;
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
      //TP = Ask + TPPips*Point;
      //MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   if(newBar==True && sig_entry<0){
      SL = 0;
      TP = 0;
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
      //TP = Bid - TPPips*Point;
      //MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   //MyTrailingStop(TPPips,MAGIC);
   //TimeStop_Exit(Slippage,0,TimeStop_bars,MAGIC);   
   //TimeStop_Exit_Force(Slippage,NULL,10,MAGIC);
  
}