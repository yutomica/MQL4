//+------------------------------------------------------------------+
//|                                              STR01_USDJPY_H1.mq4 |
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

#define MAGIC 20240512
#define COMMENT "STR01_USDJPY_H1"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 50;
extern int En_bars = 20;
extern int SL_bars = 5;
extern int ATRPeriod = 10;
extern double SLLimit = 2.0;



//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    fileHandle;
int    orders_cnt;
double order_lots;
double order_price,TP,SL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{  
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  FileClose(fileHandle);
}

//待機注文数をカウント
int CountPendingOrders(int magic)
{
   int pendingOrderCount = 0;
   for(int i=0;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      int type = OrderType();
      // 待機中オーダーかどうかを判定
      if (type == OP_BUYLIMIT || type == OP_SELLLIMIT ||
          type == OP_BUYSTOP  || type == OP_SELLSTOP)
      {
          pendingOrderCount++;
      }
   }
   return(pendingOrderCount);
}

// 指値注文をすべてキャンセルする関数
void CancelAllPendingOrders(int magic){
   int totalOrders = OrdersTotal();
   for (int i = totalOrders - 1; i >= 0; i--) {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      int type = OrderType();
      // 指値注文の種類をチェック（Buy Limit, Sell Limit, Buy Stop, Sell Stop）
      if(type == OP_BUYLIMIT || type == OP_SELLLIMIT || type == OP_BUYSTOP || type == OP_SELLSTOP){
         bool result = OrderDelete(OrderTicket());
         if (!result) {
            Print("注文キャンセル失敗: ", OrderTicket(), " エラーコード: ", GetLastError());
         }else{
            Print("注文キャンセル成功: ", OrderTicket());
         }
      }
   }
}


/*
N/2戦略
*/
void CloseHalf(double band,int slippage,int magic){
   bool res_cl;
   bool res_md;
   for(int i=0;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      if(OrderType() == OP_BUY)
      {
         if((Bid - OrderOpenPrice() > band*Point) && OrderStopLoss() < OrderOpenPrice()){   
            res_cl = false;
            res_md = false;
            while(!res_cl){
               while(!res_md){
                  res_md = OrderModify(OrderTicket(),0,OrderOpenPrice(),0,0,clrDodgerBlue);
               }
               res_cl = OrderClose(OrderTicket(),OrderLots()/2,Bid,slippage,clrDodgerBlue);
            }
         }
         continue;
      }
      if(OrderType() == OP_SELL)
      {
         if((OrderOpenPrice()-Ask > band*Point) && OrderStopLoss() > OrderOpenPrice()){
            res_cl = false;
            res_md = false;
            while(!res_cl){
               while(!res_md){
                  res_md = OrderModify(OrderTicket(),0,OrderOpenPrice(),0,0,clrIndianRed);
               }
               res_cl = OrderClose(OrderTicket(),OrderLots()/2,Ask,slippage,clrIndianRed);
            }
         }
         continue;
      }            
   }
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   int oTicket;
   int TPPips;
   
   orders_cnt = CountPendingOrders(MAGIC);
   
   if(newBar==True){
      //既存の待機注文をキャンセル
      CancelAllPendingOrders(MAGIC);
      order_price = High[iHighest(NULL, 0, MODE_HIGH, En_bars, 1)];
      SL = Low[iLowest(NULL, 0, MODE_LOW, SL_bars, 0)];
      TP = 0;
      order_lots = 0.1;
      if(order_price-SL<SLLimit){
         oTicket = SendOrder(OP_BUYSTOP,order_lots,order_price,Slippage,SL,TP,COMMENT,MAGIC);
      }
      order_price = Low[iLowest(NULL, 0, MODE_LOW, En_bars, 1)];
      SL = High[iHighest(NULL, 0, MODE_HIGH, SL_bars, 0)];
      TP = 0;
      order_lots = 0.1;
      if(SL-order_price<SLLimit){
         oTicket = SendOrder(OP_SELLSTOP,order_lots,order_price,Slippage,SL,TP,COMMENT,MAGIC);
      }
   }
      
   TPPips = int(iATR(NULL,0,ATRPeriod,0)*100);
   CloseHalf(TPPips,3,MAGIC);
   MyTrailingStop(TPPips,MAGIC);
  

}

