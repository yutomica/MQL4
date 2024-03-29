/*

# ST14_BigChance
一代チャンスを見極める
作成日：2019/9/20
更新日：20XX/X/X

【チャート】：
・日足

【テクニカル】：
・移動平均線（50SMA±3%、7SMA）

【ロジック】：
・７日SMAが50日SMA±3%を上/下抜け→Buy/Sell
・エントリー後20日で仕切り
・マネーマネジメントベースのSL


*/

#include <stderror.mqh>
#include <stdlib.mqh>
#include <WinUser32.mqh>
//#include <Original/Application.mqh>
#include <Original/Mylib.mqh>
#include <Original/Basic.mqh>
#include <Original/DateAndTime.mqh>
#include <Original/LotSizing.mqh>
#include <Original/TrailingStop.mqh>
#include <Original/TimeStop.mqh>
#include <Original/Mail.mqh>
#include <Original/Tracker.mqh>
//#include <Original/OrderHandle.mqh>
//#include <Original/OrderReliable.mqh>

#define MAGIC 20190920
#define COMMENT "ST14_BigChance"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern int FastMAPeriod = 7;
extern int SlowMAPeriod = 50;
extern double SlowMABand = 3.0;
extern int ExitBars = 20;


//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    fileHandle;
double order_lots;
double TP,SL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  if(Digits == 3 || Digits == 5){
  }
    
  /*Edge Validation*/
  string outfile = "_tmp.csv";
  fileHandle = FileOpen(outfile,FILE_CSV|FILE_WRITE,",");
  
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  FileClose(fileHandle);
}



/*
エントリー関数
*/
int EntrySignal(int magic)
{
   double pos = MyCurrentOrders(MY_OPENPOS, magic);
   int ret = 0;
   double FastMA[3];
   for(int i=1;i<=2;i++){FastMA[i] = iMA(Symbol(),NULL,FastMAPeriod,0,MODE_SMA,PRICE_CLOSE,i);}
   double MABand_U[3];
   double MABand_L[3];
   for(int j=1;j<=2;j++){
      MABand_U[j] = iEnvelopes(Symbol(),NULL,SlowMAPeriod,MODE_SMA,0,PRICE_CLOSE,SlowMABand,MODE_UPPER,j);
      MABand_L[j] = iEnvelopes(Symbol(),NULL,SlowMAPeriod,MODE_SMA,0,PRICE_CLOSE,SlowMABand,MODE_LOWER,j);
   }
 
   //BUY：
   if(pos == 0
      && FastMA[2] < MABand_U[2] && FastMA[1] > MABand_U[1]
   ) ret = 1;
   
   //Sell：
   if(pos == 0
      && FastMA[2] > MABand_L[2] && FastMA[1] < MABand_L[1]
   ) ret = -1;
   
   return(ret);
   
}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   bool newBar = IsNewBar();
   EdgeValidation(fileHandle,MAGIC);
   
   int sig_entry = EntrySignal(MAGIC);
   
   order_lots = 0.01;
   
   if(newBar==True && sig_entry>0){
      //SL = Ask - 2*iATR(Symbol(),NULL,14,1);
      SL = 0;
      TP = 0;
      MyOrderSend(OP_BUY,order_lots,Ask,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   if(newBar==True && sig_entry<0){
      //SL = Bid + 2*iATR(Symbol(),NULL,14,1);
      SL = 0;
      TP = 0;
      MyOrderSend(OP_SELL,order_lots,Bid,Slippage,SL,TP,COMMENT,MAGIC);
   }
   
   TimeStop_Exit_Force(Slippage,NULL,ExitBars,MAGIC);
  
}