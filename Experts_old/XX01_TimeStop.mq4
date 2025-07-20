//+------------------------------------------------------------------+
//|                                                XX01_TimeStop.mq4 |
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
   datetime Ent_Time;
   int shift;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      Ent_Time = OrderOpenTime();
      shift = iBarShift(NULL,0,Ent_Time);
      
      if(shift > TimeShift && OrderProfit()<0)
      {
         Print("ExitPotision : Profit is ",OrderProfit());
         MyOrderClose(Slippage,magic);
         break;
      }
   }
}




int start()
{
   datetime t = TimeLocal();
   datetime test_date1, test_date2, test_date3, test_date4;
   
   datetime some_time=D'2016.12.14 00:00';
   int shift=iBarShift(NULL,0,some_time);
   Print("index of the bar for the time ",TimeToStr(some_time)," is ",shift);

   test_date1 = TimeLocal();
   test_date2 = StrToTime("2000.01.01 00:00");
   test_date3 = StrToTime("2000.01.02 00:00");

   test_date4 = test_date1 - test_date2 + test_date3;
   string s = TimeYear(t) + "/" + TimeMonth(t) + "/" + TimeDay(t)
       + " " + TimeHour(t) + "/" + TimeMinute(t) + ":" + TimeSeconds(t); 
   //Print("Now = ",TimeToStr(test_date1)," 5 minute ago = ",TimeToStr(test_date4));
   //FileWrite(handle,Month(),Day(),Hour(),Minute(),Seconds());
   return(0);

}

void deinit()
{
   //FileClose(handle);
}