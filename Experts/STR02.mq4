//+------------------------------------------------------------------+
//|                                                         STR02.mq4|
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

#define MAGIC 20240818
#define COMMENT "STR02"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern double RiskPercent = 0.01;
extern int Slippage = 3;
extern int TPPips = 50;
extern int MaxOrders = 40;


//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    fileHandle;
int    sig_entry;
double order_lots = MarketInfo(NULL,MODE_MINLOT)*8;
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


int TrendJudge()
{  
   double haOpen1 = iCustom(NULL,PERIOD_D1,"Heiken Ashi",2,1);//1つ前の足の平均足始値
   double haClose1 = iCustom(NULL,PERIOD_D1,"Heiken Ashi",3,1);//1つ前の足の平均足終値
   int trend;
   
   //トレンド判定
   if(
      haOpen1 < haClose1
   ) trend = 1; //bull
   if(
      haOpen1 > haClose1 
   ) trend = 2; //bear
   
   return(trend);
}

int CountOrders(int magic)
{
   int N_orders = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS) == false) break;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;
      N_orders += 1;
   }
   return(N_orders);
}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   int n_orders;
   //if(newBar==True){Tracker(fileHandle,MAGIC);}
   //Tracker(fileHandle,MAGIC);
   
   sig_entry = TrendJudge();
   
   if(newBar==True && sig_entry==1){
      n_orders = CountOrders(MAGIC);
      SL = iLow(NULL,PERIOD_D1,1);
      SLPips = 0;//Ask - SL;
      TP = 0;
      if(n_orders < MaxOrders){MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);}
   }
   
   if(newBar==True && sig_entry==2){
      n_orders = CountOrders(MAGIC);
      SL = iHigh(NULL,PERIOD_D1,1);
      SLPips = 0;//SL - Bid;
      TP = 0;
      if(n_orders < MaxOrders){MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);}
   }
   
   CloseHalf(TPPips,3,MAGIC);
   MyTrailingStop(TPPips,MAGIC);
  
}