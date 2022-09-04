//+------------------------------------------------------------------+
//|                                          Period_ConverterALL.mq4 |
//|             Original Copyright © 2005, MetaQuotes Software Corp. |
//|                                        http://www.metaquotes.net |
//|                      Only OffLine convert history from 1M Period | 
//|                          to M5, M15, M30, 1H, 4H, 1D in one time |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2005, MetaQuotes Software Corp."
#property link      "http://www.metaquotes.net"
//#property show_inputs
#include <WinUser32.mqh>
//extern int ExtPeriodMultiplier=5; // new period multiplier factor
int        ExtHandle = -1;
static int  ArrPeriod[];
//+------------------------------------------------------------------+
//| script program start function                                    |
//+------------------------------------------------------------------+
int start()
  {
   if(Period() != PERIOD_M1)
     {
       Print("Start Period Must be M1."); 
       return(0);
     }
   ArrayResize(ArrPeriod, 8);
   ArrPeriod[0] = 5;
   ArrPeriod[1] = 15;  
   ArrPeriod[2] = 30;  
   ArrPeriod[3] = 60;  
   ArrPeriod[4] = 240;  
   ArrPeriod[5] = 1440;  
   ArrPeriod[6] = 10080;    
   ArrPeriod[7] = 43200;      
   int    i, start_pos, i_time, time0, last_fpos, periodseconds;
   double d_open, d_low, d_high, d_close, d_volume, last_volume;
   int    hwnd = 0, cnt = 0;
 //---- History header
   int    version = 400;
   string c_copyright = "(C)opyright 2003, MetaQuotes Software Corp.";
   string c_symbol = Symbol();
   int    i_period = 1;
   int    i_digits = Digits;
   int    i_unused[13];
   string Comm = ""; 
   for(int qq = 0; qq < ArraySize(ArrPeriod); qq++)
     {
       i_period = Period()*ArrPeriod[qq];
       Comm = "Converting to Period (" + i_period + "), bars to end: ";
       //----  
       ExtHandle = FileOpenHistory(c_symbol + i_period + ".hst", FILE_BIN|FILE_WRITE);
       if(ExtHandle < 0) 
           return(-1);
       //---- write history file header
       FileWriteInteger(ExtHandle, version, LONG_VALUE);
       FileWriteString(ExtHandle, c_copyright, 64);
       FileWriteString(ExtHandle, c_symbol, 12);
       FileWriteInteger(ExtHandle, i_period, LONG_VALUE);
       FileWriteInteger(ExtHandle, i_digits, LONG_VALUE);
       FileWriteInteger(ExtHandle, 0, LONG_VALUE);       //timesign
       FileWriteInteger(ExtHandle, 0, LONG_VALUE);       //last_sync
       FileWriteArray(ExtHandle, i_unused, 0, 13);
       //---- write history file
       periodseconds = i_period*60;
       start_pos = Bars - 1;
       d_open = Open[start_pos];
       d_low = Low[start_pos];
       d_high = High[start_pos];
       d_volume = Volume[start_pos];
        //---- normalize open time
       i_time = Time[start_pos] / periodseconds;
       i_time *= periodseconds;
       for(i = start_pos - 1; i >= 0; i--)
         {
           if(MathMod(i, 1000) == 0)
               Comment(Comm + " " + i);
           time0 = Time[i];
           if(time0 >= i_time + periodseconds || i == 0)
             {
               if(i == 0 && time0 < i_time + periodseconds)
                 {
                   d_volume += Volume[0];
                   if(Low[0] < d_low)   
                       d_low = Low[0];
                   if(High[0] > d_high) 
                       d_high = High[0];
                   d_close = Close[0];
                 }
               last_fpos = FileTell(ExtHandle);
               last_volume = Volume[i];
               FileWriteInteger(ExtHandle, i_time, LONG_VALUE);
               FileWriteDouble(ExtHandle, d_open, DOUBLE_VALUE);
               FileWriteDouble(ExtHandle, d_low, DOUBLE_VALUE);
               FileWriteDouble(ExtHandle, d_high, DOUBLE_VALUE);
               FileWriteDouble(ExtHandle, d_close, DOUBLE_VALUE);
               FileWriteDouble(ExtHandle, d_volume, DOUBLE_VALUE);
               FileFlush(ExtHandle);
               cnt++;
               if(time0 >= i_time + periodseconds)
                 {
                   i_time = time0 / periodseconds;
                   i_time *= periodseconds;
                   d_open = Open[i];
                   d_low = Low[i];
                   d_high = High[i];
                   d_close = Close[i];
                   d_volume = last_volume;
                 }
             }    
           else
             {
               d_volume += Volume[i];
               if(Low[i] < d_low)
                   d_low = Low[i];
               if(High[i] > d_high) 
                   d_high = High[i];
               d_close=Close[i];
            }
          } 
        FileFlush(ExtHandle);
        if(ExtHandle >= 0) 
          { 
            FileClose(ExtHandle); 
            ExtHandle = -1; 
          }           
     }
//----
   return(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void deinit()
  {
   if(ExtHandle >= 0) 
     { 
       FileClose(ExtHandle); ExtHandle = -1; 
     }
   Comment("");
  }
//+------------------------------------------------------------------+