/*

Donchian Breakoutによるトレード

# STR01
作成日：2022/03/02
更新日：2022/05/04

【チャート】：
・USDJPY H1

【テクニカル】：
・日足Trendjudge_ADX

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

#define MAGIC 20220302
#define COMMENT "STR01"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int TPRatio = 14;
extern int En_bars = 25;
extern int TimeStop_bars = 14;


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
double TPPips;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  if(Digits == 3 || Digits == 5){
   TPRatio = TPRatio*10;
  }
    
  /*Edge Validation*/
  //string outfile = "_tmp.csv";
  //fileHandle = FileOpen(outfile,FILE_CSV|FILE_WRITE,",");
  
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

   //BUY：
   if(/*pos == 0
      && */High[iHighest(NULL, 0, MODE_HIGH, En_bars, 2)] < Close[1]
   ) ret = 1;
   //Sell：
   if(/*pos == 0
      && */Low[iLowest(NULL, 0, MODE_LOW, En_bars, 2)] > Close[1]
   ) ret = -1;
   
   return(ret);
   
}



/*
エキジット関数
*/
void ExitPosition(int magic)
{
   int ret = 0;
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int TrendJudge_ADX_Bull = iCustom(NULL,PERIOD_D1,"TrendJudge_ADX",14,25,PERIOD_D1,0,1);
   int TrendJudge_ADX_Bear = iCustom(NULL,PERIOD_D1,"TrendJudge_ADX",14,25,PERIOD_D1,1,1);
   int TrendJudge_ADX_Neut = iCustom(NULL,PERIOD_D1,"TrendJudge_ADX",14,25,PERIOD_D1,2,1);
   
   //Buy Close
   if(pos > 0 
      && (TrendJudge_ADX_Bear == 1 || TrendJudge_ADX_Neut == 1)
   ) ret = 1;

   //Sell Close
   if(pos < 0 
      && (TrendJudge_ADX_Bull == 1 || TrendJudge_ADX_Neut == 1)
   ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}



/*
ロット算出関数
*/
double getLots(void)
{
   double ret = 1.0;
   int TrendJudge_ADX_Bull = iCustom(NULL,PERIOD_D1,"TrendJudge_ADX",14,25,PERIOD_D1,0,1);
   int TrendJudge_ADX_Bear = iCustom(NULL,PERIOD_D1,"TrendJudge_ADX",14,25,PERIOD_D1,1,1);
   
   if(TrendJudge_ADX_Bull == 1 || TrendJudge_ADX_Bull == 1){ret = ret * 2;}
  
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
   
   //ExitPosition(MAGIC);
   sig_entry = EntrySignal(MAGIC);
   //sig_entry = FilterSignal(sig_entry);
   
   if(newBar==True && sig_entry>0){
      //SL = iLow(NULL,PERIOD_D1,1);//
      SL = Ask - 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      order_lots = getLots();
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   if(newBar==True && sig_entry<0){
      //SL = iHigh(NULL,PERIOD_D1,1);//
      SL = Bid + 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      order_lots = getLots();
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
   }
   TPPips = TPRatio*iATR(Symbol(),NULL,14,1);
   MyTrailingStop(TPPips,MAGIC);
   TimeStop_Exit(Slippage,0,TimeStop_bars,MAGIC);
   //TimeStop_Exit_Force(Slippage,NULL,100,MAGIC);
  
}