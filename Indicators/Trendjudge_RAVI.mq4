//+------------------------------------------------------------------+
//|                                              Trendjudge_RAVI.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1 Blue
#property indicator_width1 3
#property indicator_minimum 0
//#property indicator_maximum 30

//指標バッファ
double Buf[];

//パラメータ
extern int FastMA_period = 7;
extern int SlowMA_period = 65;

int init(){
	SetIndexBuffer(0, Buf);
	SetIndexLabel(0,"RAVI");
	SetIndexStyle(0,DRAW_HISTOGRAM);
	return(0);
}

int start(){
	int limit = Bars - IndicatorCounted();

	for(int i=limit-1;i>=0;i--){

      double fastma;
      double slowma; 
      fastma = iMA(NULL,0,FastMA_period,0,MODE_SMA,PRICE_CLOSE,i);
      slowma = iMA(NULL,0,SlowMA_period,0,MODE_SMA,PRICE_CLOSE,i);
		//Buf[i] = 100.*MathAbs(fastma - slowma)/slowma;
      Buf[i] = 100.*MathAbs(fastma - slowma)*MathPow(slowma,-1);
	}

	return(0);

}
