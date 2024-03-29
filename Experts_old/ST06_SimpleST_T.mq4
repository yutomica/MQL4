/*

# ST06_SimpleST_T
作成日：2017/7/2

・「ボリンジャーバンドとMACDによるデイトレード」、時間足でのトレード戦略
・エキジットにはADRの代わりにATRを使用

*/


#include <MyLib.mqh>

#define MAGIC 20170702
#define COMMENT "ST06_SimpleST_T"

extern int Slippage = 3;


/*
エントリー関数
*/
extern int BBPeriod = 12;
extern int BBSigma = 2;
extern int RSIPeriod = 7;
extern int MACD_LTPeriod = 26;
extern int MACD_STPeriod = 12;
extern int MACD_SGPeriod = 9;

int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   double rsi;
   double BB_U1;double BB_U0;double BB_L1;double BB_L0;
   double MACD_main;double MACD_sig;
   int ret = 0;
   
   rsi = iRSI(NULL,0,RSIPeriod,PRICE_CLOSE,0);
   BB_U1 = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,2);
   BB_U0 = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,1);
   BB_L1 = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,2);
   BB_L0 = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,1);
   MACD_main = iMACD(NULL,0,MACD_STPeriod,MACD_LTPeriod,MACD_SGPeriod,PRICE_CLOSE,MODE_MAIN,1);   
   MACD_main = iMACD(NULL,0,MACD_STPeriod,MACD_LTPeriod,MACD_SGPeriod,PRICE_CLOSE,MODE_SIGNAL,1);
   
   /*Buy Signal*/
   if(pos == 0 && MACD_main>0 && MACD_main>MACD_sig && BB_U1 < BB_U0 && rsi > 70) ret = 1;
   
   /*Sell Signal*/
   if(pos == 0 && MACD_main<0 && MACD_main<MACD_sig && BB_L1 > BB_L0 && rsi < 30) ret = -1;
   
   return(ret);
}

extern int ATRPeriod = 7;
extern double ATRMult_tp = 0.15;
extern double ATRMult_sl = 0.10;
int start()
{
   double tp;
   double sl;
   double BB_U;
   double BB_L;
   
   int sig_entry = EntrySignal(MAGIC);
   
   //ロット数計算
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*0.3)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   //Print("lotsize=",lotsize," order_lots=",order_lots);
   order_lots = 0.01;
   
   
   //Buy Order
   if(sig_entry > 0)
   {
      tp = Ask + iATR(NULL,PERIOD_D1,ATRPeriod,1)*ATRMult_tp;
      sl = Ask - iATR(NULL,PERIOD_D1,ATRPeriod,1)*ATRMult_sl;
      BB_U = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_UPPER,0);
      MyOrderSend(OP_BUY,order_lots,BB_U,Slippage,sl,tp,COMMENT,MAGIC);
   }
   
   //Sell Order
   if(sig_entry < 0)
   {
      tp = Bid - iATR(NULL,PERIOD_D1,ATRPeriod,1)*ATRMult_tp;
      sl = Bid + iATR(NULL,PERIOD_D1,ATRPeriod,1)*ATRMult_sl;
      BB_L = iBands(NULL,0,BBPeriod,2,0,PRICE_CLOSE,MODE_LOWER,0);
      MyOrderSend(OP_SELL,order_lots,BB_L,Slippage,sl,tp,COMMENT,MAGIC);
   }
   
   
   return(0);
}



