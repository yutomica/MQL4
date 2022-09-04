//+------------------------------------------------------------------+
//|                                                  PRICE_STDEV.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#property indicator_separate_window
#property indicator_buffers 2
#property indicator_color1 Red
#property indicator_color2 Blue

double Buf_low[];
double Buf_up[];

extern int STDPeriod = 20;

int init()
{
   SetIndexBuffer(0,Buf_low);
   SetIndexBuffer(1,Buf_up);
   SetIndexLabel(0,"PRICE_STDEV_LOWER");
   SetIndexLabel(1,"PRICE_STDEV_UPPER");
   
   return(0);
}

int start()
{
   int limit = Bars - IndicatorCounted();
   double MEAN=0;
   double STDEV=0;
   
   for(int i=limit-1;i>=0;i--)
   {
      for(int j=STDPeriod;j>=0;j--){MEAN += Close[j];}
      MEAN = MEAN / STDPeriod;
      for(j=STDPeriod;j>=0;j--){STDEV += (MEAN - Close[j])*(MEAN - Close[j]);}
      Buf_low[i] = Close[i] - sqrt(STDEV/STDPeriod);
      Buf_up[i] = Close[i] + sqrt(STDEV/STDPeriod);
   }
   
   return(0);
}