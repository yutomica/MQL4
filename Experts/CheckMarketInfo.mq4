//+------------------------------------------------------------------+
//|                                              CheckMarketInfo.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

string outfile;
int fileHandle;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
      outfile = "checkmarketinfo.csv";
      fileHandle = FileOpen(outfile,FILE_CSV|FILE_WRITE,",");
      
      //Market Info
      FileWrite(fileHandle,"MODE_MAXLOT : 最大ロット数 = "+MarketInfo(Symbol(), MODE_MAXLOT));
      FileWrite(fileHandle,"MODE_LOTSTEP : ロットの最小変化幅 = "+MarketInfo(Symbol(), MODE_LOTSTEP));
      FileWrite(fileHandle,"MODE_POINT : ポイント = "+MarketInfo(Symbol(), MODE_POINT));      
      FileWrite(fileHandle,"MODE_MINLOT : 最小ロット数 = "+MarketInfo(Symbol(), MODE_MINLOT));
      FileWrite(fileHandle,"MODE_SWAPSHORT : 1ロットあたりの売りポジションのスワップ値(口座通貨) = "+MarketInfo(Symbol(), MODE_SWAPSHORT));
      FileWrite(fileHandle,"MODE_SWAPLONG : 1ロットあたりの買いポジションのスワップ値(口座通貨) = "+MarketInfo(Symbol(), MODE_SWAPLONG));
      FileWrite(fileHandle,"MODE_TICKVALUE : 1ロットあたりの1pipの価格(口座通貨) = "+MarketInfo(Symbol(), MODE_TICKVALUE));
      FileWrite(fileHandle,"MODE_LOTSIZE : 1ロットのサイズ(通貨単位) = "+MarketInfo(Symbol(), MODE_LOTSIZE));
      FileWrite(fileHandle,"MODE_STOPLEVEL : 指値・逆指値の値幅(pips) = "+MarketInfo(Symbol(), MODE_STOPLEVEL));
      FileWrite(fileHandle,"MODE_SPREAD : スプレッド(pips) = "+MarketInfo(Symbol(), MODE_SPREAD));
      FileWrite(fileHandle,"MODE_TIME : 最新のtick時刻 = "+TimeToStr(MarketInfo(Symbol(), MODE_TIME), TIME_DATE|TIME_SECONDS));
      FileWrite(fileHandle,"MODE_HIGH : 当日の高値 = "+MarketInfo(Symbol(), MODE_HIGH));
      FileWrite(fileHandle,"MODE_LOW : 当日の安値 = "+MarketInfo(Symbol(), MODE_LOW));
      
      //Account Info
      int level=AccountStopoutLevel();
      if(AccountStopoutMode()==0) FileWrite(fileHandle,"StopOutLevel = ", level, "%");
      else FileWrite(fileHandle,"StopOutLevel = ", level, " ", AccountCurrency());
      FileWrite(fileHandle,"AccountBalance = ", AccountBalance( ));
      FileWrite(fileHandle,"AccountEquity = ", AccountEquity( ));
      FileWrite(fileHandle,"AccountFreeMargin = ", AccountFreeMargin( ));
      FileWrite(fileHandle,"AccountMargin = ", AccountMargin( ));
      FileWrite(fileHandle,"AccountProfit = ", AccountProfit( ));
      FileWrite(fileHandle,"AccountCredit = ", AccountCredit( ));
      FileWrite(fileHandle,"AccountLeverage = ", AccountLeverage( ));
      FileWrite(fileHandle,"AccountName = ", AccountName( ));
      FileWrite(fileHandle,"AccountNumber = ", AccountNumber( ));
      FileWrite(fileHandle,"AccountCurency = ", AccountCurrency( ));
      FileWrite(fileHandle,"AccountServer = ", AccountServer( ));
      FileWrite(fileHandle,"AccountCompany = ", AccountCompany( ));      
      
      return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
