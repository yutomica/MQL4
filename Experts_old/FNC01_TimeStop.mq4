//+------------------------------------------------------------------+
//|                                               FNC01_TimeStop.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property library
#property copyright "yuu"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <MyLib.mqh>

void TimeStop_Exit(int magic,double Slippage,int TimeShift)
{
   datetime Ent_Time = 0;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL)
      {
         Ent_Time = OrderOpenTime();
         break;
      }
   }
   
   int Traded_bar = 0;
   if(Ent_Time > 0) Traded_bar = iBarShift(NULL,0,Ent_Time,false);
   if(Traded_bar >= TimeShift && OrderProfit()<0) MyOrderClose(Slippage,magic);
   
}


