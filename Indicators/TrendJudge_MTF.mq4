
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_color1 Green
#property indicator_width1 3
#property indicator_color2 YellowGreen
#property indicator_width2 3
#property indicator_color3 LightGreen
#property indicator_width3 3
#property indicator_minimum -3.2
#property indicator_maximum 3.2

#define PERIOD_0 PERIOD_D1
#define PERIOD_1 PERIOD_H1
#define PERIOD_2 PERIOD_M30

//指標バッファ
double Buf_0[];
double Buf_1[];
double Buf_2[];

//パラメータ
extern int slow_ma_period = 25;
extern int fast_ma_period = 5;

int init(){
	SetIndexBuffer(0, Buf_0);
	SetIndexBuffer(1, Buf_1);
	SetIndexBuffer(2, Buf_2);
	SetIndexLabel(0,"PERIOD_0");
	SetIndexLabel(1,"PERIOD_1");
	SetIndexLabel(2,"PERIOD_2");
	SetIndexStyle(0, DRAW_LINE);
	SetIndexStyle(1, DRAW_LINE);
	SetIndexStyle(2, DRAW_LINE);
	return(0);

}

int start(){
	int limit = Bars - IndicatorCounted();

	for(int i=limit-1;i>=0;i--){

		Buf_0[i] = 0;
		Buf_1[i] = 0;
		Buf_2[i] = 0;
				
		double slow_ma[3];
		double fast_ma[3];
		
		//PERIOD_0
		slow_ma[0] = iMA(NULL,PERIOD_0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		slow_ma[1] = iMA(NULL,PERIOD_0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		slow_ma[2] = iMA(NULL,PERIOD_0,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		fast_ma[0] = iMA(NULL,PERIOD_0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		fast_ma[1] = iMA(NULL,PERIOD_0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		fast_ma[2] = iMA(NULL,PERIOD_0,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		if(slow_ma[2] < slow_ma[1] 
			&& slow_ma[1] < slow_ma[0]
			&& fast_ma[2] < fast_ma[1]
			&& fast_ma[1] < fast_ma[0]
			&& fast_ma[0] > slow_ma[0]
			&& Close[1] > fast_ma[0]
		){ Buf_0[i] = 3;}
		else if(slow_ma[2] > slow_ma[1] 
			&& slow_ma[1] > slow_ma[0]
			&& fast_ma[2] > fast_ma[1]
			&& fast_ma[1] > fast_ma[0]
			&& fast_ma[0] < slow_ma[0]
			&& Close[1] < fast_ma[0]
		){ Buf_0[i] = -3;}

		//PERIOD_1
		slow_ma[0] = iMA(NULL,PERIOD_1,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		slow_ma[1] = iMA(NULL,PERIOD_1,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		slow_ma[2] = iMA(NULL,PERIOD_1,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		fast_ma[0] = iMA(NULL,PERIOD_1,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		fast_ma[1] = iMA(NULL,PERIOD_1,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		fast_ma[2] = iMA(NULL,PERIOD_1,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		if(slow_ma[2] < slow_ma[1] 
			&& slow_ma[1] < slow_ma[0]
			&& fast_ma[2] < fast_ma[1]
			&& fast_ma[1] < fast_ma[0]
			&& fast_ma[0] > slow_ma[0]
			&& Close[1] > fast_ma[0]
		){ Buf_1[i] = 2;}
		else if(slow_ma[2] > slow_ma[1] 
			&& slow_ma[1] > slow_ma[0]
			&& fast_ma[2] > fast_ma[1]
			&& fast_ma[1] > fast_ma[0]
			&& fast_ma[0] < slow_ma[0]
			&& Close[1] < fast_ma[0]
		){ Buf_1[i] = -2;}

		//PERIOD_2
		slow_ma[0] = iMA(NULL,PERIOD_2,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		slow_ma[1] = iMA(NULL,PERIOD_2,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		slow_ma[2] = iMA(NULL,PERIOD_2,slow_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		fast_ma[0] = iMA(NULL,PERIOD_2,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+1);
		fast_ma[1] = iMA(NULL,PERIOD_2,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+2);
		fast_ma[2] = iMA(NULL,PERIOD_2,fast_ma_period,0,MODE_SMA,PRICE_CLOSE,i+3);
		if(slow_ma[2] < slow_ma[1] 
			&& slow_ma[1] < slow_ma[0]
			&& fast_ma[2] < fast_ma[1]
			&& fast_ma[1] < fast_ma[0]
			&& fast_ma[0] > slow_ma[0]
			&& Close[1] > fast_ma[0]
		){ Buf_2[i] = 1;}
		else if(slow_ma[2] > slow_ma[1] 
			&& slow_ma[1] > slow_ma[0]
			&& fast_ma[2] > fast_ma[1]
			&& fast_ma[1] > fast_ma[0]
			&& fast_ma[0] < slow_ma[0]
			&& Close[1] < fast_ma[0]
		){ Buf_2[i] = -1;}

	}

	return(0);

}
