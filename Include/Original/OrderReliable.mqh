//+------------------------------------------------------------------+
//|                                                OrderReliable.mqh |
//|                                     Copyright (c) 2017, りゅーき |
//|                                            http://autofx100.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2017, りゅーき"
#property link      "http://autofx100.com/"
#property version   "1.1"

//+------------------------------------------------------------------+
//| 定数定義                                                         |
//+------------------------------------------------------------------+
#define MAX_RETRY_TIME   10.0 // 秒
#define SLEEP_TIME        0.1 // 秒
#define MILLISEC_2_SEC 1000.0 // ミリ秒

//+------------------------------------------------------------------+
//|【関数】信頼できる仕掛け注文（値幅指定）                          |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aSymbol            通貨ペア                      |
//|         ○      aCmd               注文種別                      |
//|         ○      aVolume            ロット数                      |
//|         ○      aPrice             仕掛け価格                    |
//|         ○      aSlippage          スリッページ（ポイント）      |
//|         ○      aStoplossPips      損切り値幅(pips)              |
//|         ○      aTakeprofitPips    利食い値幅(pips)              |
//|         △      aComment           コメント                      |
//|         △      aMagic             マジックナンバー              |
//|         △      aExpiration        待機注文の有効期限            |
//|         △      aArrow_color       チャート上の矢印の色          |
//|                                                                  |
//|【戻値】チケット番号（エラーの場合は、-1）                        |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
int orderSendReliableRange(string aSymbol, int aCmd, double aVolume, double aPrice, int aSlippage, double aStoplossPips, double aTakeprofitPips, string aComment = NULL, int aMagic = 0, datetime aExpiration = 0, color aArrow_color = CLR_NONE)
{
  int plusMinusSign = 1;

  if(aCmd == OP_SELL || aCmd == OP_SELLLIMIT || aCmd == OP_SELLSTOP){
    plusMinusSign *= -1;
  }

  double sl = 0.0;
  double tp = 0.0;

  if(aStoplossPips > 0.0){
    sl = aPrice - aStoplossPips * gPipsPoint * plusMinusSign;
  }

  if(aTakeprofitPips > 0.0){
    tp = aPrice + aTakeprofitPips * gPipsPoint * plusMinusSign;
  }

  int result = orderSendReliable(aSymbol, aCmd, aVolume, aPrice, aSlippage, sl, tp, aComment, aMagic, aExpiration, aArrow_color);

  return(result);
}

//+------------------------------------------------------------------+
//|【関数】信頼できる仕掛け注文                                      |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aSymbol            通貨ペア                      |
//|         ○      aCmd               注文種別                      |
//|         ○      aVolume            ロット数                      |
//|         ○      aPrice             仕掛け価格                    |
//|         ○      aSlippage          スリッページ（ポイント）      |
//|         ○      aStoploss          損切り価格                    |
//|         ○      aTakeprofit        利食い価格                    |
//|         △      aComment           コメント                      |
//|         △      aMagic             マジックナンバー              |
//|         △      aExpiration        待機注文の有効期限            |
//|         △      aArrow_color       チャート上の矢印の色          |
//|                                                                  |
//|【戻値】チケット番号（エラーの場合は、-1）                        |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
int orderSendReliable(string aSymbol, int aCmd, double aVolume, double aPrice, int aSlippage, double aStoploss, double aTakeprofit, string aComment = NULL, int aMagic = 0, datetime aExpiration = 0, color aArrow_color = CLR_NONE)
{
  int ticket = -1;

  int startTime = (int)GetTickCount();

  int digits = (int)MarketInfo(aSymbol, MODE_DIGITS);

  PrintFormatLog(__FILE__, __FUNCTION__, 
                 "Attempted to send the order.," + aSymbol + "," + orderType2String(aCmd)
                 + ",OpenPrice:," + DoubleToString(aPrice, digits)
                 + ",SL:,"        + DoubleToString(aStoploss, digits)
                 + ",TP:,"        + DoubleToString(aTakeprofit, digits)
                 + ",lot:,"       + DoubleToString(aVolume)
                 + ",Magic:,"     + IntegerToString(aMagic)
                 + ",Slippage:,"  + IntegerToString(aSlippage)
                 + ",Comment:,"   + aComment);

  aStoploss   = NormalizeDouble(aStoploss,   digits);
  aTakeprofit = NormalizeDouble(aTakeprofit, digits);

  double stopLevel   = MarketInfo(aSymbol, MODE_STOPLEVEL) * MarketInfo(aSymbol, MODE_POINT);
  double freezeLevel = MarketInfo(aSymbol, MODE_FREEZELEVEL) * MarketInfo(aSymbol, MODE_POINT);

  while(true){
    if(IsStopped()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Trading is stopped!");
      return(-1);
    }

    if(GetTickCount() - startTime > MAX_RETRY_TIME * MILLISEC_2_SEC){
      PrintFormatLog(__FILE__, __FUNCTION__, "Retry attempts maxed at " + DoubleToString(MAX_RETRY_TIME) + "sec.");
      return(-1);
    }

    // MarketInfo関数でレートを取得しており、定義済変数であるAskとBidは未使用のため、不要のはずだけど、念のため
    RefreshRates();

    double ask = NormalizeDouble(MarketInfo(aSymbol, MODE_ASK), digits);
    double bid = NormalizeDouble(MarketInfo(aSymbol, MODE_BID), digits);

    if(aCmd == OP_BUY){
      aPrice = ask;
    }else if(aCmd == OP_SELL){
      aPrice = bid;
    }

    // 仕掛け／損切り／利食いがストップレベル未満かフリーズレベル以下の場合、エラー
    if(aCmd == OP_BUY){
      if(MathAbs(bid - aStoploss) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - bid) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(bid - aStoploss) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: SL was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - bid) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: TP was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(aCmd == OP_SELL){
      if(MathAbs(aStoploss - ask) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aTakeprofit) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - ask) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: SL was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aTakeprofit) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: TP was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(aCmd == OP_BUYLIMIT){
      if(MathAbs(ask - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aStoploss) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aPrice) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(aCmd == OP_SELLLIMIT){
      if(MathAbs(aPrice - bid) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aTakeprofit) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - bid) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(aCmd == OP_BUYSTOP){
      if(MathAbs(aPrice - ask) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aStoploss) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - ask) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(aCmd == OP_SELLSTOP){
      if(MathAbs(bid - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - aPrice) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aTakeprofit) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(bid - aPrice) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }

    if(IsTradeContextBusy()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Must wait for trade context.");
    }else{
      ticket = OrderSend(aSymbol, aCmd, aVolume, aPrice, aSlippage, aStoploss, aTakeprofit, aComment, aMagic, aExpiration, aArrow_color);

      if(ticket > 0){
        bool selected = OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);
        return(ticket);
      }

      int err = GetLastError();

      // 一時的エラーの場合はリトライするが、恒常的エラーの場合は処理中断（リトライしてもエラーになるため）
      if(err == ERR_NO_ERROR || 
         err == ERR_COMMON_ERROR ||
         err == ERR_SERVER_BUSY ||
         err == ERR_NO_CONNECTION ||
         err == ERR_TRADE_TIMEOUT ||
         err == ERR_INVALID_PRICE ||
         err == ERR_PRICE_CHANGED ||
         err == ERR_OFF_QUOTES ||
         err == ERR_BROKER_BUSY ||
         err == ERR_REQUOTE ||
         err == ERR_TRADE_CONTEXT_BUSY){
        PrintFormatLog(__FILE__, __FUNCTION__, "Temporary Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". waiting.");
      }else{
        PrintFormatLog(__FILE__, __FUNCTION__, "Permanent Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". giving up.");
        return(-1);
      }

      // 最適化とバックテスト時はリトライは不要
      if(IsOptimization() || IsTesting()){
        return(-1);
      }
    }

    Sleep(SLEEP_TIME * MILLISEC_2_SEC);
  }

  return(-1);
}

//+------------------------------------------------------------------+
//|【関数】信頼できる仕切り注文                                      |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aTicket            チケット番号                  |
//|         ○      aLots              ロット数                      |
//|         ○      aPrice             仕切り価格                    |
//|         ○      aSlippage          スリッページ（ポイント）      |
//|         △      aArrow_color       チャート上の矢印の色          |
//|                                                                  |
//|【戻値】true ：正常終了                                           |
//|        false：異常終了                                           |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
bool orderCloseReliable(int aTicket, double aLots, double aPrice, int aSlippage, color aArrow_color = CLR_NONE)
{
  bool result = false;

  int startTime = (int)GetTickCount();

  bool selected = OrderSelect(aTicket, SELECT_BY_TICKET, MODE_TRADES);

  string symbol = OrderSymbol();
  int    type   = OrderType();

  int digits = (int)MarketInfo(symbol, MODE_DIGITS);

  PrintFormatLog(__FILE__, __FUNCTION__, 
                 "Attempted to close the opened order.,#" + IntegerToString(aTicket)
                 + ",ClosePrice:," + DoubleToString(aPrice, digits)
                 + ",lot:,"        + DoubleToString(aLots)
                 + ",Slippage:,"   + IntegerToString(aSlippage));

  while(true){
    if(IsStopped()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Trading is stopped!");
      return(-1);
    }

    if(GetTickCount() - startTime > MAX_RETRY_TIME * MILLISEC_2_SEC){
      PrintFormatLog(__FILE__, __FUNCTION__, "Retry attempts maxed at " + DoubleToString(MAX_RETRY_TIME) + "sec.");
      return(-1);
    }

    // MarketInfo関数でレートを取得しており、定義済変数であるAskとBidは未使用のため、不要のはずだけど、念のため
    RefreshRates();

    if(type == OP_BUY){
      aPrice = MarketInfo(symbol, MODE_BID);
    }else if(type == OP_SELL){
      aPrice = MarketInfo(symbol, MODE_ASK);
    }

    aPrice = NormalizeDouble(aPrice, digits);

    if(IsTradeContextBusy()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Must wait for trade context.");
    }else{
      result = OrderClose(aTicket, aLots, aPrice, aSlippage, aArrow_color);

      if(result){
        return(result);
      }

      int err = GetLastError();

      // 一時的エラーの場合はリトライするが、恒常的エラーの場合は処理中断（リトライしてもエラーになるため）
      if(err == ERR_NO_ERROR || 
         err == ERR_COMMON_ERROR ||
         err == ERR_SERVER_BUSY ||
         err == ERR_NO_CONNECTION ||
         err == ERR_TOO_FREQUENT_REQUESTS ||
         err == ERR_TRADE_TIMEOUT ||
         err == ERR_INVALID_PRICE ||
         err == ERR_TRADE_DISABLED ||
         err == ERR_PRICE_CHANGED ||
         err == ERR_OFF_QUOTES ||
         err == ERR_BROKER_BUSY ||
         err == ERR_REQUOTE ||
         err == ERR_TOO_MANY_REQUESTS ||
         err == ERR_TRADE_CONTEXT_BUSY){
        PrintFormatLog(__FILE__, __FUNCTION__, "Temporary Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". waiting.");
      }else{
        PrintFormatLog(__FILE__, __FUNCTION__, "Permanent Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". giving up.");
        return(result);
      }

      // 最適化とバックテスト時はリトライは不要
      if(IsOptimization() || IsTesting()){
        return(result);
      }
    }

    Sleep(SLEEP_TIME * MILLISEC_2_SEC);
  }

  return(result);
}

//+------------------------------------------------------------------+
//|【関数】信頼できる待機注文削除                                    |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aTicket            チケット番号                  |
//|         △      aArrow_color       チャート上の矢印の色          |
//|                                                                  |
//|【戻値】true ：正常終了                                           |
//|        false：異常終了                                           |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
bool orderDeleteReliable(int aTicket, color aArrow_color = CLR_NONE)
{
  bool result = false;

  int startTime = (int)GetTickCount();

  PrintFormatLog(__FILE__, __FUNCTION__, "Attempted to delete the pending order.,#" + IntegerToString(aTicket));

  while(true){
    if(IsStopped()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Trading is stopped!");
      return(-1);
    }

    if(GetTickCount() - startTime > MAX_RETRY_TIME * MILLISEC_2_SEC){
      PrintFormatLog(__FILE__, __FUNCTION__, "Retry attempts maxed at " + DoubleToString(MAX_RETRY_TIME) + "sec.");
      return(-1);
    }

    if(IsTradeContextBusy()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Must wait for trade context.");
    }else{
      result = OrderDelete(aTicket, aArrow_color);

      if(result){
        return(result);
      }

      int err = GetLastError();

      // 一時的エラーの場合はリトライするが、恒常的エラーの場合は処理中断（リトライしてもエラーになるため）
      if(err == ERR_NO_ERROR || 
         err == ERR_COMMON_ERROR ||
         err == ERR_SERVER_BUSY ||
         err == ERR_NO_CONNECTION ||
         err == ERR_TOO_FREQUENT_REQUESTS ||
         err == ERR_TRADE_TIMEOUT ||
         err == ERR_INVALID_PRICE ||
         err == ERR_TRADE_DISABLED ||
         err == ERR_PRICE_CHANGED ||
         err == ERR_OFF_QUOTES ||
         err == ERR_BROKER_BUSY ||
         err == ERR_REQUOTE ||
         err == ERR_TOO_MANY_REQUESTS ||
         err == ERR_TRADE_CONTEXT_BUSY){
        PrintFormatLog(__FILE__, __FUNCTION__, "Temporary Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". waiting.");
      }else{
        PrintFormatLog(__FILE__, __FUNCTION__, "Permanent Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". giving up.");
        return(result);
      }

      // 最適化とバックテスト時はリトライは不要
      if(IsOptimization() || IsTesting()){
        return(result);
      }
    }

    Sleep(SLEEP_TIME * MILLISEC_2_SEC);
  }

  return(result);
}

//+------------------------------------------------------------------+
//|【関数】信頼できる注文変更                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aTicket            チケット番号                  |
//|         ○      aPrice             待機注文の新しい仕掛け価格    |
//|         ○      aStoploss          損切り価格                    |
//|         ○      aTakeprofit        利食い価格                    |
//|         ○      aExpiration        待機注文の有効期限            |
//|         △      aArrow_color       チャート上の矢印の色          |
//|                                                                  |
//|【戻値】true ：正常終了                                           |
//|        false：異常終了                                           |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
bool orderModifyReliable(int aTicket, double aPrice, double aStoploss, double aTakeprofit, datetime aExpiration, color aArrow_color = CLR_NONE)
{
  bool result = false;

  int startTime = (int)GetTickCount();

  bool selected = OrderSelect(aTicket, SELECT_BY_TICKET, MODE_TRADES);

  string symbol = OrderSymbol();
  int    type   = OrderType();

  int digits = (int)MarketInfo(symbol, MODE_DIGITS);

  PrintFormatLog(__FILE__, __FUNCTION__, 
                 "Attempted to modify the order.,#" + IntegerToString(aTicket)
                 + ",ModifyPrice:," + DoubleToString(aPrice, digits)
                 + ",SL:,"          + DoubleToString(aStoploss, digits)
                 + ",TP:,"          + DoubleToString(aTakeprofit, digits));

  double price      = NormalizeDouble(OrderOpenPrice(), digits);
  double stoploss   = NormalizeDouble(OrderStopLoss(), digits);
  double takeprofit = NormalizeDouble(OrderTakeProfit(), digits);

  aPrice      = NormalizeDouble(aPrice,      digits);
  aStoploss   = NormalizeDouble(aStoploss,   digits);
  aTakeprofit = NormalizeDouble(aTakeprofit, digits);

  double stopLevel   = MarketInfo(symbol, MODE_STOPLEVEL) * MarketInfo(symbol, MODE_POINT);
  double freezeLevel = MarketInfo(symbol, MODE_FREEZELEVEL) * MarketInfo(symbol, MODE_POINT);

  while(true){
    if(IsStopped()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Trading is stopped!");
      return(-1);
    }

    if(GetTickCount() - startTime > MAX_RETRY_TIME * MILLISEC_2_SEC){
      PrintFormatLog(__FILE__, __FUNCTION__, "Retry attempts maxed at " + DoubleToString(MAX_RETRY_TIME) + "sec.");
      return(-1);
    }

    double ask = NormalizeDouble(MarketInfo(symbol, MODE_ASK), digits);
    double bid = NormalizeDouble(MarketInfo(symbol, MODE_BID), digits);

    // 仕掛け／損切り／利食いがストップレベル未満かフリーズレベル以下の場合、エラー
    if(type == OP_BUY){
      if(MathAbs(bid - aStoploss) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - bid) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(bid - aStoploss) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: SL was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - bid) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: TP was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(type == OP_SELL){
      if(MathAbs(aStoploss - ask) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aTakeprofit) < stopLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - ask) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: SL was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aTakeprofit) <= freezeLevel){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: TP was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(type == OP_BUYLIMIT){
      if(MathAbs(ask - aPrice) < stopLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aStoploss) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aStoploss != 0.0 && aStoploss != stoploss))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - aPrice) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aTakeprofit != 0.0 && aTakeprofit != takeprofit))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(ask - aPrice) <= freezeLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(type == OP_SELLLIMIT){
      if(MathAbs(aPrice - bid) < stopLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - aPrice) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aStoploss != 0.0 && aStoploss != stoploss))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aTakeprofit) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aTakeprofit != 0.0 && aTakeprofit != takeprofit))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - bid) <= freezeLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(type == OP_BUYSTOP){
      if(MathAbs(aPrice - ask) < stopLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aStoploss) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aStoploss != 0.0 && aStoploss != stoploss))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aTakeprofit - aPrice) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aTakeprofit != 0.0 && aTakeprofit != takeprofit))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - ask) <= freezeLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }else if(type == OP_SELLSTOP){
      if(MathAbs(bid - aPrice) < stopLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aStoploss - aPrice) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aStoploss != 0.0 && aStoploss != stoploss))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: SL was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(aPrice - aTakeprofit) < stopLevel && ((aPrice != 0.0 && aPrice != price) || (aTakeprofit != 0.0 && aTakeprofit != takeprofit))){
        PrintFormatLog(__FILE__, __FUNCTION__, "StopLevel: TP was too close to brokers min distance (" + DoubleToString(stopLevel) + ").");
        return(-1);
      }else if(MathAbs(bid - aPrice) <= freezeLevel && (aPrice != 0.0 && aPrice != price)){
        PrintFormatLog(__FILE__, __FUNCTION__, "FreezeLevel: OpenPrice was too close to brokers min distance (" + DoubleToString(freezeLevel) + ").");
        return(-1);
      }
    }

    if(IsTradeContextBusy()){
      PrintFormatLog(__FILE__, __FUNCTION__, "Must wait for trade context.");
    }else{
      result = OrderModify(aTicket, aPrice, aStoploss, aTakeprofit, aExpiration, aArrow_color);

      if(result){
        selected = OrderSelect(aTicket, SELECT_BY_TICKET, MODE_TRADES);
        return(result);
      }

      int err = GetLastError();

      // 一時的エラーの場合はリトライするが、恒常的エラーの場合は処理中断（リトライしてもエラーになるため）
      if(err == ERR_NO_ERROR || 
         err == ERR_COMMON_ERROR ||
         err == ERR_SERVER_BUSY ||
         err == ERR_NO_CONNECTION ||
         err == ERR_TRADE_TIMEOUT ||
         err == ERR_INVALID_PRICE ||
         err == ERR_PRICE_CHANGED ||
         err == ERR_OFF_QUOTES ||
         err == ERR_BROKER_BUSY ||
         err == ERR_REQUOTE ||
         err == ERR_TRADE_CONTEXT_BUSY){
        PrintFormatLog(__FILE__, __FUNCTION__, "Temporary Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". waiting.");
      }else{
        PrintFormatLog(__FILE__, __FUNCTION__, "Permanent Error: " + IntegerToString(err) + " " + ErrorDescription(err) + ". giving up.");
        return(result);
      }

      // 最適化とバックテスト時はリトライは不要
      if(IsOptimization() || IsTesting()){
        return(result);
      }
    }

    Sleep(SLEEP_TIME * MILLISEC_2_SEC);
  }

  return(result);
}

//+------------------------------------------------------------------+
//|【関数】注文種別の数値を文字列に変換する                          |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aType              注文種別                      |
//|                                                                  |
//|【戻値】注文種別の数値に対応する文字列                            |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
string orderType2String(int aType)
{
  if(aType == OP_BUY){
    return("BUY");
  }else if(aType == OP_SELL){
    return("SELL");
  }else if(aType == OP_BUYSTOP){
    return("BUY STOP");
  }else if(aType == OP_SELLSTOP){
    return("SELL STOP");
  }else if(aType == OP_BUYLIMIT){
    return("BUY LIMIT");
  }else if(aType == OP_SELLLIMIT){
    return("SELL LIMIT");
  }else{
    return("None (" + IntegerToString(aType) + ")");
  }
}
