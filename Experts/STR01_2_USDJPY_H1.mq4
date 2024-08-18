//+------------------------------------------------------------------+
//|                                            STR01_2_USDJPY_H1.mq4 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
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

#define MAGIC 20240811
#define COMMENT "STR01_2_USDJPY_H1"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern double RiskPercent = 0.01;
extern int Slippage = 3;
extern int TPPips = 50;
extern int CloseHalfPips = 10;
extern int En_bars = 20;
extern int SL_bars = 5;
extern int TimeStop_bars = 14;
extern int jaw_period = 13;
extern int jaw_shift = 8;
extern int teeth_period = 8;
extern int teeth_shift = 5;
extern int lips_period = 5;
extern int lips_shift = 3;


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
double TP,SL,SLPips;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  if(Digits == 3 || Digits == 5){
   TPPips = TPPips*10;
   Slippage = Slippage*10;
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
エントリー関数：
HLバンドブレイクアウト、かつAlligatorが逆方向トレンドを指していない
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

int FilterSignal(int signal)
{   
   double jaw[5];
   for(int i=1;i<=5;i++){jaw[i] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,1,i);}
   double teeth[5];
   for(int j=1;j<=5;j++){teeth[j] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,2,j);}
   double lips[5];
   for(int k=1;k<=5;k++){lips[k] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,3,k);}  
   int ret = 0;
   int trend = 0;
   
   //トレンド判定
   if(
      jaw[1] < teeth[1] && teeth[1] < lips[1]
      //&& jaw[2] < teeth[2] && teeth[2] < lips[2]
      //&& jaw[3] < teeth[3] && teeth[3] < lips[3]
      && jaw[1] > jaw[2] //&& jaw[2] > jaw[3]
      && teeth[1] > teeth[2] //&& teeth[2] > teeth[3]
      && lips[1] > lips[2] //&& lips[2] > lips[3]
   ) trend = 1; //bull
   if(
      jaw[1] > teeth[1] && teeth[1] > lips[1]
      //&& jaw[2] > teeth[2] && teeth[2] > lips[2]
      //&& jaw[3] > teeth[3] && teeth[3] > lips[3]
      && jaw[1] < jaw[2] //&& jaw[2] < jaw[3]
      && teeth[1] < teeth[2] //&& teeth[2] < teeth[3]
      && lips[1] < lips[2] //&& lips[2] < lips[3]   
   ) trend = 2; //bear
   
   //Buy Filter
   if(signal > 0 && trend != 2) ret = signal;
   //Sell Filter
   if(signal < 0 && trend != 1) ret = signal;
   
   return(ret);
}



/*
エキジット関数
*/
void ExitPosition(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double jaw[5];
   for(int i=1;i<=5;i++){jaw[i] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,1,i);}
   double teeth[5];
   for(int j=1;j<=5;j++){teeth[j] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,2,j);}
   double lips[5];
   for(int k=1;k<=5;k++){lips[k] = iAlligator(NULL,NULL,jaw_period,jaw_shift,teeth_period,teeth_shift,lips_period,lips_shift,MODE_EMA,PRICE_MEDIAN,3,k);}  
   int ret = 0;
   int trend = 0;
   
   //トレンド判定
   if(
      jaw[1] < teeth[1] && teeth[1] < lips[1]
      //&& jaw[2] < teeth[2] && teeth[2] < lips[2]
      //&& jaw[3] < teeth[3] && teeth[3] < lips[3]
      && jaw[1] > jaw[2] //&& jaw[2] > jaw[3]
      && teeth[1] > teeth[2] //&& teeth[2] > teeth[3]
      && lips[1] > lips[2] //&& lips[2] > lips[3]
   ) trend = 1; //bull
   if(
      jaw[1] > teeth[1] && teeth[1] > lips[1]
      //&& jaw[2] > teeth[2] && teeth[2] > lips[2]
      //&& jaw[3] > teeth[3] && teeth[3] > lips[3]
      && jaw[1] < jaw[2] //&& jaw[2] < jaw[3]
      && teeth[1] < teeth[2] //&& teeth[2] < teeth[3]
      && lips[1] < lips[2] //&& lips[2] < lips[3]   
   ) trend = 2; //bear
      
   //Buy Close
   if(pos > 0 && trend == 2) ret = 1;
   //Sell Close
   if(pos < 0 && trend == 1) ret = -1;

   if(ret!=0) MyOrderClose(Slippage,magic);

}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   int oTicket;
   //if(newBar==True){Tracker(fileHandle,MAGIC);}
   //Tracker(fileHandle,MAGIC);
   
   ExitPosition(MAGIC);
   sig_entry = EntrySignal(MAGIC);
   sig_entry = FilterSignal(sig_entry);
   
   if(newBar==True && sig_entry>0){
      SL = Low[iLowest(NULL, 0, MODE_LOW, SL_bars, 0)];
      SLPips = Ask - SL;
      TP = 0;
      order_lots = calcLotSizeRiskPercent(AccountBalance(),NULL,SLPips,RiskPercent);
      order_lots = int(order_lots/(MarketInfo(NULL,MODE_MINLOT)*2))*MarketInfo(NULL,MODE_MINLOT)*2;
      if(order_lots > MarketInfo(NULL,MODE_MINLOT)){oTicket = MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);}
   }
   
   if(newBar==True && sig_entry<0){
      SL = High[iHighest(NULL, 0, MODE_HIGH, SL_bars, 0)];
      SLPips = SL - Bid;
      TP = 0;
      order_lots = calcLotSizeRiskPercent(AccountBalance(),NULL,SLPips,RiskPercent);
      order_lots = int(order_lots/(MarketInfo(NULL,MODE_MINLOT)*2))*MarketInfo(NULL,MODE_MINLOT)*2;
      if(order_lots > MarketInfo(NULL,MODE_MINLOT)){oTicket = MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);}
   }
   
   CloseHalf(CloseHalfPips,Slippage,MAGIC);
   //TPPips = TPRatio*iATR(Symbol(),NULL,14,1);
   MyTrailingStop(TPPips,MAGIC);
   //TimeStop_Exit(Slippage,0,TimeStop_bars,MAGIC);
   //TimeStop_Exit_Force(Slippage,NULL,100,MAGIC);
  
}