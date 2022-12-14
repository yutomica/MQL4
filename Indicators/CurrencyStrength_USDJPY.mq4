//+------------------------------------------------------------------+
//|                                             CurrencyStrength.mq4 |
//|                        Copyright 2019, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1 Green

//指標バッファ
double Buf[];

//通貨ペアごとのUP/DOWNフラグ
// 1:up,-1:down,0:else
int flg_USDJPY;
int flg_EURJPY;
int flg_GBPJPY;
int flg_AUDJPY;
int flg_EURUSD;
int flg_GBPUSD;
int flg_AUDUSD;

int init(){
	SetIndexBuffer(0, Buf);
	SetIndexLabel(0,"CurrencyStrength");
	SetIndexStyle(0, DRAW_LINE);
	return(0);
}

int start(){
	int limit = Bars - IndicatorCounted();

	for(int i=limit-1;i>=0;i--){

		Buf[i] = 0;
		
      if(
         iClose("USDJPY",0,i+1) > iOpen("USDJPY",0,i+1)
         && iClose("USDJPY",0,i+2) > iOpen("USDJPY",0,i+2)
         && iClose("USDJPY",0,i+3) > iOpen("USDJPY",0,i+3)
      ){flg_USDJPY = 1;}
      else if(
         iClose("USDJPY",0,i+1) < iOpen("USDJPY",0,i+1)
         && iClose("USDJPY",0,i+2) < iOpen("USDJPY",0,i+2)
         && iClose("USDJPY",0,i+3) < iOpen("USDJPY",0,i+3)      
      ){flg_USDJPY = -1;}
      else{flg_USDJPY = 0;}
      
      if(
         iClose("EURJPY",0,i+1) > iOpen("EURJPY",0,i+1)
         && iClose("EURJPY",0,i+2) > iOpen("EURJPY",0,i+2)
         && iClose("EURJPY",0,i+3) > iOpen("EURJPY",0,i+3)
      ){flg_EURJPY = 1;}
      else if(
         iClose("EURJPY",0,i+1) < iOpen("EURJPY",0,i+1)
         && iClose("EURJPY",0,i+2) < iOpen("EURJPY",0,i+2)
         && iClose("EURJPY",0,i+3) < iOpen("EURJPY",0,i+3)      
      ){flg_EURJPY = -1;}
      else{flg_EURJPY = 0;}

      if(
         iClose("GBPJPY",0,i+1) > iOpen("GBPJPY",0,i+1)
         && iClose("GBPJPY",0,i+2) > iOpen("GBPJPY",0,i+2)
         && iClose("GBPJPY",0,i+3) > iOpen("GBPJPY",0,i+3)
      ){flg_GBPJPY = 1;}
      else if(
         iClose("GBPJPY",0,i+1) < iOpen("GBPJPY",0,i+1)
         && iClose("GBPJPY",0,i+2) < iOpen("GBPJPY",0,i+2)
         && iClose("GBPJPY",0,i+3) < iOpen("GBPJPY",0,i+3)      
      ){flg_GBPJPY = -1;}
      else{flg_GBPJPY = 0;}

      if(
         iClose("AUDJPY",0,i+1) > iOpen("AUDJPY",0,i+1)
         && iClose("AUDJPY",0,i+2) > iOpen("AUDJPY",0,i+2)
         && iClose("AUDJPY",0,i+3) > iOpen("AUDJPY",0,i+3)
      ){flg_AUDJPY = 1;}
      else if(
         iClose("AUDJPY",0,i+1) < iOpen("AUDJPY",0,i+1)
         && iClose("AUDJPY",0,i+2) < iOpen("AUDJPY",0,i+2)
         && iClose("AUDJPY",0,i+3) < iOpen("AUDJPY",0,i+3)      
      ){flg_AUDJPY = -1;}
      else{flg_AUDJPY = 0;}

      if(
         iClose("EURUSD",0,i+1) > iOpen("EURUSD",0,i+1)
         && iClose("EURUSD",0,i+2) > iOpen("EURUSD",0,i+2)
         && iClose("EURUSD",0,i+3) > iOpen("EURUSD",0,i+3)
      ){flg_EURUSD = 1;}
      else if(
         iClose("EURUSD",0,i+1) < iOpen("EURUSD",0,i+1)
         && iClose("EURUSD",0,i+2) < iOpen("EURUSD",0,i+2)
         && iClose("EURUSD",0,i+3) < iOpen("EURUSD",0,i+3)      
      ){flg_EURUSD = -1;}
      else{flg_EURUSD = 0;}

      if(
         iClose("GBPUSD",0,i+1) > iOpen("GBPUSD",0,i+1)
         && iClose("GBPUSD",0,i+2) > iOpen("GBPUSD",0,i+2)
         && iClose("GBPUSD",0,i+3) > iOpen("GBPUSD",0,i+3)
      ){flg_GBPUSD = 1;}
      else if(
         iClose("GBPUSD",0,i+1) < iOpen("GBPUSD",0,i+1)
         && iClose("GBPUSD",0,i+2) < iOpen("GBPUSD",0,i+2)
         && iClose("GBPUSD",0,i+3) < iOpen("GBPUSD",0,i+3)      
      ){flg_GBPUSD = -1;}
      else{flg_GBPUSD = 0;}

      if(
         iClose("AUDUSD",0,i+1) > iOpen("AUDUSD",0,i+1)
         && iClose("AUDUSD",0,i+2) > iOpen("AUDUSD",0,i+2)
         && iClose("AUDUSD",0,i+3) > iOpen("AUDUSD",0,i+3)
      ){flg_AUDUSD = 1;}
      else if(
         iClose("AUDUSD",0,i+1) < iOpen("AUDUSD",0,i+1)
         && iClose("AUDUSD",0,i+2) < iOpen("AUDUSD",0,i+2)
         && iClose("AUDUSD",0,i+3) < iOpen("AUDUSD",0,i+3)      
      ){flg_AUDUSD = -1;}
      else{flg_AUDUSD = 0;}

      if(flg_USDJPY == -1 && flg_EURJPY == -1 && flg_GBPJPY == -1 /*&& flg_AUDJPY == -1*/ && flg_EURUSD == 1 && flg_GBPUSD == 1 /*&& flg_AUDUSD == 1*/){Buf[i] = 1;}
      if(flg_USDJPY == 1 && flg_EURJPY == 1 && flg_GBPJPY == 1 /*&& flg_AUDJPY == 1*/ && flg_EURUSD == -1 && flg_GBPUSD == -1 /*&& flg_AUDUSD == -1*/){Buf[i] = -1;}

	}

	return(0);

}
