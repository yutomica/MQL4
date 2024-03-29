/*

# ST17_DonchianBreakout_Nofilter_EURJPY_H4
作成日：2020/6/1
開始日：2020/6/1
更新日：20XX/X/X


[概要]
・20日ブレイクアウトを仕掛けにエントリー、20時台のエントリーは避ける
・80Pips下にSLを設定
・半裁量運用を前提としたストラテジ、TP設定、SL変更は手動で行う

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

#define MAGIC 202006011
#define COMMENT "ST17_DonchianBreakout_Nofilter_EURJPY_H4"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 0.02;
extern int Slippage = 3;
extern int En_bars = 20;
extern int Ex_bars = 10;
extern int SLPips = 80;


//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    sig_entry;
double order_lots;
double SL;
int    fileHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  if(Digits == 3 || Digits == 5){
   SLPips *= 10;
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
  //FileClose(fileHandle);
}



/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int curHour = Hour();
   int ret = 0;

   //BUY：
   if(pos == 0
      && High[iHighest(NULL, 0, MODE_HIGH, En_bars, 2)] < Close[1]
      && curHour!=20
   ) ret = 1;
   //Sell：
   if(pos == 0
      && Low[iLowest(NULL, 0, MODE_LOW, En_bars, 2)] > Close[1]
      && curHour!=20
   ) ret = -1;
   
   return(ret);
   
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  bool newBar = IsNewBar();
  //Tracker(fileHandle,MAGIC);
  
   sig_entry = EntrySignal(MAGIC);
  
   //order_lots = AccountBalance()*Safety_ratio/(MarketInfo(Symbol(),MODE_LOTSIZE)*SLPips*Point);
   //order_lots = int(order_lots*100)/100.;
   //Print(order_lots);
   //if(order_lots > MarketInfo(Symbol(), MODE_MAXLOT)){order_lots = MarketInfo(Symbol(), MODE_MAXLOT);}
   order_lots = 0.25;
  
   if(newBar==True && sig_entry>0){
      SL = Ask - SLPips*Point;
      if(MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,0,COMMENT,MAGIC)){
         MySendMail("ST17_DonchianBreakout_Nofilter_EURJPY_H4",1);
      }
   }
   
   if(newBar==True && sig_entry<0){
      SL = Bid + SLPips*Point;   
      if(MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,0,COMMENT,MAGIC)){
         MySendMail("ST17_DonchianBreakout_Nofilter_EURJPY_H4",2);
      }
   }
  
   //TimeStop_Exit_Force(Slippage,NULL,100,MAGIC);
   TimeStop_Exit(Slippage,NULL,14,MAGIC);
  
}