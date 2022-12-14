#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_color1 Blue
#property indicator_color2 Red
#property indicator_color3 Green
#property indicator_width1 3
#property indicator_width2 3
#property indicator_width3 3
#property indicator_minimum 0
#property indicator_maximum 1

//指標バッファ
double BufBull[];
double BufBear[];
double BufNeutral[];

//パラメータ
extern int ADX_period = 14;
extern double ADX_thresh = 25.0;
extern int OBS_PERIOD = PERIOD_D1;

int init(){
	SetIndexBuffer(0, BufBull);
	SetIndexBuffer(1, BufBear);
	SetIndexBuffer(2, BufNeutral);

	SetIndexLabel(0,"Bull");
	SetIndexLabel(1,"Bear");
	SetIndexLabel(2,"Neutral");

	SetIndexStyle(0, DRAW_HISTOGRAM);
	SetIndexStyle(1, DRAW_HISTOGRAM);
	SetIndexStyle(2, DRAW_HISTOGRAM);

	return(0);

}

int start(){
	int limit = Bars - IndicatorCounted();

	for(int i=limit-1;i>=0;i--){

		BufBull[i] = 0;
		BufBear[i] = 0;
		BufNeutral[i] = 1;

      double ADX[3],pDI[3],mDI[3];
      //double ADX_ma[3];
      ADX[0] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MAIN,i+1);
      ADX[1] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MAIN,i+2);
      ADX[2] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MAIN,i+3);
      pDI[0] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_PLUSDI,i+1);
      pDI[1] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_PLUSDI,i+2);
      pDI[2] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_PLUSDI,i+3);
      mDI[0] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MINUSDI,i+1);
      mDI[1] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MINUSDI,i+2);
      mDI[2] = iADX(NULL,OBS_PERIOD,ADX_period,PRICE_CLOSE,MODE_MINUSDI,i+3);
      
		if(ADX[1] < ADX[0] 
		   //&& ADX[2] < ADX[1]
		   && ADX[0] >= ADX_thresh
		   && ADX[1] >= ADX_thresh
		   && ADX[2] >= ADX_thresh
		   //&& pDI[2] > mDI[2] 
		   && pDI[1] > mDI[1] 
		   && pDI[0] > mDI[0]
		){BufNeutral[i] = 0;BufBull[i] = 1;}
		if(ADX[1] < ADX[0] 
		   //&& ADX[2] < ADX[1]
		   && ADX[0] >= ADX_thresh
		   && ADX[1] >= ADX_thresh
		   && ADX[2] >= ADX_thresh
		   //&& pDI[2] < mDI[2] 
		   && pDI[1] < mDI[1] 
		   && pDI[0] < mDI[0]
		){BufNeutral[i] = 0;BufBear[i] = 1;}

	}

	return(0);

}
