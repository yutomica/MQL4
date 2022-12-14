/*

# TimeStop.mqh
作成日：2017/1/27
更新日：2019/10/22

*/

#include <Original/MyLib.mqh>


/*
   TimeStopExit
   ・エントリーからTimeShift後に利益が出ていない場合にエキジットする。

*/
void TimeStop_Exit(double slippage,int timeframe,int TimeShift,int magic)
{
   datetime Ent_Time;
   int shift;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      Ent_Time = OrderOpenTime();
      shift = iBarShift(NULL,timeframe,Ent_Time);      
      //Print("Bars from entry : ",shift," | Profit : ",OrderProfit());
           
      if(shift >= TimeShift && OrderProfit()<0 && OrderType()==OP_BUY)
      {
         if(OrderClose(OrderTicket(),OrderLots(),Bid,slippage,ArrowColor[OrderType()])==true){;}
      }
      if(shift >= TimeShift && OrderProfit()<0 && OrderType()==OP_SELL)
      {
         if(OrderClose(OrderTicket(),OrderLots(),Ask,slippage,ArrowColor[OrderType()])==true){;}
      }
   }
}

/*
   TimeStopExit_Force
   ・エントリーからTimeShift後に強制的にエキジットする。
*/
void TimeStop_Exit_Force(double slippage,int timeframe,int TimeShift,int magic)
{
   datetime Ent_Time;
   int shift;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      Ent_Time = OrderOpenTime();
      shift = iBarShift(NULL,timeframe,Ent_Time);      
      //Print("Bars from entry : ",shift," | Profit : ",OrderProfit());
           
      if(shift >= TimeShift)
      {
         Print("ExitPotision : Profit is ",OrderProfit());
         MyOrderClose(slippage,magic);
         break;
      }
   }
}
