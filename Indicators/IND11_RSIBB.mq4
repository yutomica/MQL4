
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1 ForestGreen

// 指標バッファ
double Buf0[];

// 外部パラメータ
extern int BBPeriod = 20;
extern int RSIPeriod = 8;

// 初期化関数
int init()
{
   // 指標バッファの割り当て
   SetIndexBuffer(0, Buf0);
   
   // 指標ラベルの設定
   SetIndexLabel(0, "RSIBB");

   return(0);
}

// スタート関数
int start()
{
   int limit = Bars-IndicatorCounted();
   double tmp[];

   for(int i=limit-1; i>=0; i--)
   {
      for
      Buf0[i] = (iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,i)-iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,i));
   }

   return(0);
}

