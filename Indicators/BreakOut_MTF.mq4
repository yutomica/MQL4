//+------------------------------------------------------------------+
//|                                                 BreakOut_MTF.mq4 |
//|                        Copyright 2019, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

/*
参考：https://fxtrading.greeds.net/マルチタイムフレーム製のインジケーターを簡単/
*/

#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1 Blue
#property indicator_width1 3
#property indicator_minimum -1.2
#property indicator_maximum 1.2


//指標バッファ
double Buf[];

//パラメータ
extern int TimeFrame = PERIOD_H4;
extern int BOPeriod = 20;

int OnInit(){
	SetIndexBuffer(0, Buf);
	SetIndexLabel(0,"BO");
	SetIndexStyle(0, DRAW_HISTOGRAM);
   string TimeFrameStr;
   switch(TimeFrame)
   {
       case 1 : TimeFrameStr ="Period_M1"; break;
       case 5 : TimeFrameStr="Period_M5"; break;
       case 15 : TimeFrameStr="Period_M15"; break;
       case 30 : TimeFrameStr="Period_M30"; break;
       case 60 : TimeFrameStr="Period_H1"; break;
       case 240 : TimeFrameStr="Period_H4"; break;
       case 1440 : TimeFrameStr="Period_D1"; break;
       case 10080 : TimeFrameStr="Period_W1"; break;
       case 43200 : TimeFrameStr="Period_MN1"; break;
       default : TimeFrameStr="Current Timeframe";
   } 
   IndicatorShortName("BO_MTF:"+TimeFrameStr); 
	return(INIT_SUCCEEDED);

}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int i,y,limit,counted_bars=IndicatorCounted();
   
   limit=Bars-counted_bars;
   for(i=0;i<limit;i++)
   {
      y=iBarShift(NULL,TimeFrame,Time[i],false);
      if(
         iHigh(NULL,TimeFrame,iHighest(NULL,TimeFrame, MODE_HIGH, BOPeriod, y+2)) 
         < iClose(NULL,TimeFrame,y+1)
      ) Buf[i] = 1;
      else if(
         iLow(NULL,TimeFrame,iLowest(NULL, TimeFrame, MODE_LOW, BOPeriod, y+2)) 
         > iClose(NULL,TimeFrame,y+1)
      ) Buf[i] = -1;
      else Buf[i] = 0;    
   }
   return(rates_total);
}
