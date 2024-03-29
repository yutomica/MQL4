/*

# チャネルブレイクアウト-プルバックシステム
作成日：2019/8/19
更新日：20XX/X/X

・参考：パンローリング「売買システム入門」
・20日間最高値を更新し、その後７日以内に５日最安値を更新したら、翌日寄付きでEn
・Exは以下の組み合わせを検討
　－En後N日（N=5,10,15,20）で仕切り
　－目安となった20日間最高値で仕切り
　－TS

*/

//+------------------------------------------------------------------+
//| ライブラリ                                                       |
//+------------------------------------------------------------------+
#include <stderror.mqh>
#include <stdlib.mqh>
#include <WinUser32.mqh>
#include <Original/Mylib.mqh>
#include <Original/Basic.mqh>
#include <Original/DateAndTime.mqh>
#include <Original/LotSizing.mqh>
#include <Original/TrailingStop.mqh>
#include <Original/TimeStop.mqh>
#include <Original/Tracker.mqh>
//#include <Original/Mail.mqh>

//+------------------------------------------------------------------+
//| 定数                                                             |
//+------------------------------------------------------------------+
#define MAGIC 20190819
#define COMMENT "ST22_CBPB"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern string Note01       = "=== General ==================================================";
extern int    SlippagePips = 5;
extern double FixLotSize   = 0.01;
extern int fileHandle;

extern string Note02       = "=== Entry ====================================================";
extern int lookbackperiod  = 20;
extern int lookforwardperid = 5;
extern int pendingterm = 7;

extern string Note03       = "=== Exit ====================================================";
extern int TSPips          = 50;
extern int TimeStopBars    = 5;

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  gPipsPoint = currencyUnitPerPips(Symbol());
  gSlippage = getSlippage(Symbol(), SlippagePips);
  
  //string ymdhms = replace(TimeToStr(TimeLocal(), TIME_DATE|TIME_SECONDS),":",".");
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

   if(pos == 0 
      && iHighest(NULL,0,MODE_HIGH,lookbackperiod,1) < pendingterm
      && iLow(NULL,0,iLowest(NULL,0,MODE_LOW,lookforwardperid,2)) > Close[1]
   ) ret = 1;
   //Print(iHighest(NULL,0,MODE_HIGH,lookbackperiod,1));
   
   return(ret);
}


/*
エキジット関数
*/
void ExitPosition(int magic)
{
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   bool newBar = IsNewBar();
   Tracker(fileHandle,MAGIC);
   
   //ExitPosition(MAGIC);
   int sig_entry = EntrySignal(MAGIC);
   
   
   if(newBar==True && sig_entry > 0){
      MyOrderSend(OP_BUY,FixLotSize,Ask,SlippagePips,0,0,COMMENT,MAGIC);
   }
   if(newBar==True && sig_entry < 0){
      MyOrderSend(OP_SELL,FixLotSize,Bid,SlippagePips,0,0,COMMENT,MAGIC);
   }
   
   TimeStop_Exit(SlippagePips,0,TimeStopBars,MAGIC);
   MyTrailingStop(TSPips,MAGIC);
   
}