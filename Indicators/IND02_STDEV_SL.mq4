//+------------------------------------------------------------------+
//|                                               IND02_STDEV_SL.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 ForestGreen
#property indicator_color2 ForestGreen

// 指標バッファ
double Buf0[];
double Buf1[];

// 外部パラメータ
extern int MAPeriod = 20;
extern double sigma = 2;

// 初期化関数
int init()
{
   // 指標バッファの割り当て
   SetIndexBuffer(0, Buf0);
   SetIndexBuffer(1, Buf1);
   
   // 指標ラベルの設定
   SetIndexLabel(0, "Lower Level");
   SetIndexLabel(1, "Upper Level");

   return(0);
}

// スタート関数
int start()
{
   int limit = Bars-IndicatorCounted();

   for(int i=limit-1; i>=0; i--)
   {
      Buf0[i] = Close[i] - iStdDev(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,i)*sigma;
      Buf1[i] = Close[i] + iStdDev(NULL,0,MAPeriod,0,MODE_SMA,PRICE_CLOSE,i)*sigma;
   }

   return(0);
}

