
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

// 初期化関数
int init()
{
   
   IndicatorBuffers(1);
   
   // 指標バッファの割り当て
   SetIndexBuffer(0, Buf0);
   
   // 指標ラベルの設定
   SetIndexLabel(0, "Kairi");

   return(0);
}

// スタート関数
int start()
{
   int limit = Bars-IndicatorCounted();
   double a;
   
   for(int i=limit-1; i>=0; i--)
   {
      a = iBands(NULL,0,BBPeriod,1,0,PRICE_CLOSE,MODE_MAIN,i);
      Buf0[i] = MathAbs(1.0 - Close[i]/a)*100.0;
   }

   return(0);
}

