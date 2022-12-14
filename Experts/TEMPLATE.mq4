/*

# [ストラテジ名]
作成日：20XX/X/X
更新日：20XX/X/X


【チャート】：
・日足
・トレンドが明確な通貨ペアならどれでもOK

【テクニカル】：
・移動平均線（55SMA、90SMA）
・MACD２(短期12、長期26、シグナル9)

【ロジック】：
・2本の移動平均線とローソク足でトレンドを確認（MAの傾き、ローソク足のMAに対する位置）
・トレンドが確認出来たらその方向へのエントリーに備える
・MACDラインとシグナルラインのゴールデンクロス/デッドクロスで買/売エントリー
・TP:デッドクロスで利確
・SL：5％ルールを適用


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

#define MAGIC 201YMMDD
#define COMMENT "ST0X_XXX"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 3;


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
 
   //BUY：
   if(pos == 0
      && 
   ) ret = 1;
   
   //Sell：
   if(pos == 0
      && 
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
   
   //Buy Close
   if(pos > 0 && ) ret = 1;

   //Sell Close
   if(pos < 0 && ) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}



/*
フィルタ関数
*/
int FilterSignal(int signal)
{
   int ret = 0;
   
   if(signal>0 && ) ret = signal;
   if(signal<0 && ) ret = signal;
   
   return(ret);

}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   
   ExitPosition(MAGIC);
   sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   order_lots = 0.01;
   
   if(newBar==True && sig_entry>0){
      SL = Ask - 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   if(newBar==True && sig_entry<0){
      SL = Bid + 2*iATR(Symbol(),NULL,14,1);
      TP = 0;
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
   }
  
}