/*

XXXX

# STR03
作成日：2022/05/15
更新日：2022//


【チャート】：

【テクニカル】：

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

#define MAGIC 20220513
#define COMMENT "STR03"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int lbperiod = 5;
extern int M_EMAPeriod = 144;
extern int S_EMAPeriod = 169;
extern int F_EMAPeriod = 12;


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
  }
    
  /*Edge Validation*/
  string outfile = "_tmp.csv";
  fileHandle = FileOpen(outfile,FILE_CSV|FILE_WRITE,",");
  
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
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double F_EMA_1 = iMA(NULL,0,F_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
   double F_EMA_2 = iMA(NULL,0,F_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
   double M_EMA_1 = iMA(NULL,0,M_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
   double M_EMA_2 = iMA(NULL,0,M_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
   double S_EMA_1 = iMA(NULL,0,S_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
   double S_EMA_2 = iMA(NULL,0,S_EMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);

   //BUY：
   if(/*pos == 0
      && */Close[1] > M_EMA_1 && Close[1] > S_EMA_1 
      && F_EMA_2 < M_EMA_2 && F_EMA_2 < S_EMA_2
      && F_EMA_1 > M_EMA_1 && F_EMA_1 > S_EMA_1
   ) ret = 1;
   //Sell：
   if(/*pos == 0
      && */Close[1] < M_EMA_1 && Close[1] < S_EMA_1 
      && F_EMA_2 > M_EMA_2 && F_EMA_2 > S_EMA_2
      && F_EMA_1 < M_EMA_1 && F_EMA_1 < S_EMA_1
   ) ret = -1;
   
   return(ret);
   
}



/*
エキジット関数
*/
/*
void ExitPosition(int magic)
{
   int ret = 0;
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   
   //Buy Close
   if(pos > 0 && ) ret = 1;

   //Sell Close
   if(pos < 0 && ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}
*/


/*
フィルタ関数
*/

int FilterSignal(int signal)
{
   int ret = 0;
   int TrendJudge_ADX_Neut_1 = iCustom(NULL,0,"TrendJudge_ADX",14,25,PERIOD_D1,2,1);
   int TrendJudge_ADX_Neut_2 = iCustom(NULL,0,"TrendJudge_ADX",14,25,PERIOD_D1,2,2);
   
   if(signal>0 && TrendJudge_ADX_Neut_1 == 1 && TrendJudge_ADX_Neut_2 == 1) ret = signal;
   if(signal<0 && TrendJudge_ADX_Neut_1 == 1 && TrendJudge_ADX_Neut_2 == 1) ret = signal;
   
   return(ret);

}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   if(newBar==True){Tracker(fileHandle,MAGIC);}
   //Tracker(fileHandle,MAGIC);
   
   //ExitPosition(MAGIC);
   sig_entry = EntrySignal(MAGIC);
   //sig_entry = FilterSignal(sig_entry);
   
   order_lots = 0.01;
   
   if(newBar==True && sig_entry>0){
      SL = 0;//Ask - 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   if(newBar==True && sig_entry<0){
      SL = 0;//Bid + 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   TimeStop_Exit_Force(Slippage,NULL,100,MAGIC);
  
}