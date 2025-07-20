//+------------------------------------------------------------------+
//|                                                   TrendJudge.mq4 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
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
extern int slow_ma_period = 50;
extern int middle_ma_period = 25;
extern int fast_ma_period = 5;

int init(){
	SetIndexBuffer(0, Buf);
	SetIndexLabel(0,"TRENDJUDGE");
	SetIndexStyle(0, DRAW_HISTOGRAM);
	return(0);

}

int start(){
	int limit = Bars - IndicatorCounted();

	for(int i=limit-1;i>=0;i--){

		Buf[i] = 0;
		
		double slow_ma[3];
		slow_ma[0] = iMA(NULL,0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		slow_ma[1] = iMA(NULL,0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		slow_ma[2] = iMA(NULL,0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		double middle_ma[3];
		middle_ma[0] = iMA(NULL,0,middle_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		middle_ma[1] = iMA(NULL,0,middle_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		middle_ma[2] = iMA(NULL,0,middle_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
      double fast_ma[3];
		fast_ma[0] = iMA(NULL,0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		fast_ma[1] = iMA(NULL,0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		fast_ma[2] = iMA(NULL,0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		
		if(slow_ma[2] < slow_ma[1] && slow_ma[1] < slow_ma[0]
			&& middle_ma[2] < middle_ma[1] && middle_ma[1] < middle_ma[0]
			&& fast_ma[2] < fast_ma[1] && fast_ma[1] < fast_ma[0]
			&& middle_ma[0] > slow_ma[0] && fast_ma[0] > middle_ma[0]
			&& Close[1] > fast_ma[0]
		){ Buf[i] = 1;}
		else if(slow_ma[2] > slow_ma[1] && slow_ma[1] > slow_ma[0]
			&& middle_ma[2] > middle_ma[1] && middle_ma[1] > middle_ma[0]
			&& fast_ma[2] > fast_ma[1] && fast_ma[1] > fast_ma[0]
			&& middle_ma[0] < slow_ma[0] && fast_ma[0] < middle_ma[0]
			&& Close[1] < fast_ma[0]
		){ Buf[i] = -1;}

	}

	return(0);

}
