//+------------------------------------------------------------------+
//|                                              STR02_USDJPY_H1.mq4 |
//|              H1 RSI(2) EMA(200)方向押し目・戻り売りEA              |
//+------------------------------------------------------------------+

/*
売買ロジック
- エントリー:
  H1の新バーごとに、確定した直近バー（シフト1）だけをシグナル判定に使用する。
  終値がEMA(200)より上でRSI(2)がRSIEntry未満なら買い成行注文を発注する。
  終値がEMA(200)より下でRSI(2)が100-RSIEntryより上なら売り成行注文を発注する。
  実口座・デモ口座・テスターで、USDJPYのH1、かつスプレッドがMaxSpreadPips以内の場合だけ新規エントリーする。
  初期設定はRSIEntry=7.5、StopATR=2.5。実運用では起動後最初のH1バーの新規エントリーを見送る。
  AllowNewEntries=falseで新規発注だけを停止し、既存ポジションの決済管理は継続する。
- エグジット:
  買いはRSIが50を上回った時、売りはRSIが50を下回った時に全量決済する。
  RSIが回復しない場合は、H1でHoldBars本の経過後に決済する。
  時間決済には損益によるフィルターを設けない。
  確定足で成立した決済要求を保持し、毎ティック確認して、失敗時は5秒以上空けて再試行する。
  実運用の決済要求は口座・サーバー・銘柄・Magic・チケット別に端末へ保存し、再起動後も継続する。
  通信断・自動売買禁止・フリーズ中は要求を保持して待機する。端末停止中はEA決済できない。
- TP/SL:
  固定TPは設定しない。初期SLはH1 ATR(14)のStopATR倍をエントリー価格から離して設定し、
  ブローカーのtick刻みに合わせて正規化する。
- ポジションサイズ:
  残高と有効証拠金の小さい方を基準に、初期SL到達時の1ロット当たり損失額と
  EntryRiskPercentからロット数を計算する。ロットステップ単位で切り下げ、最小ロット未満は発注しない。
  発注後の余剰証拠金は資本の30%以上を維持する。
  リスク率0.25%は本EAの1取引単位であり、STR01を含む口座全体の合算リスク上限ではない。
- テスター出力:
  テスター内だけで最新の口座有効証拠金と残高をCSVへ記録し、日付が変わった時点でも記録する。
  実運用では他EAの損益を含む口座全体の値をSTR02単体の成績として出力しない。
*/

#property strict
#property description "H1 RSI(2) EMA(200)方向押し目・戻り売り。USDJPY H1実運用対応版。"

//+------------------------------------------------------------------+
//| ストラテジーパラメータ                                         |
//+------------------------------------------------------------------+
input string TradeSymbol = "USDJPY";
input double RSIEntry = 7.5;
input double StopATR = 2.5;
input int HoldBars = 24;
input double EntryRiskPercent = 0.25;
input double MaxSpreadPips = 2.0;
input int MagicNumber = 20260913;
input bool AllowNewEntries = true; // falseでも既存ポジションの決済は継続する。

datetime lastBar     = 0;
datetime lastTick    = 0;
double   lastEquity  = 0;
double   lastBalance = 0;
int      equityFile  = INVALID_HANDLE;
bool     entryReady  = false;
bool     stateHealthy = true;
string   exitPrefix  = "";
int      exitTickets[];
datetime exitRetryTimes[];

//+------------------------------------------------------------------+
//| EA初期化                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_H1 || TradeSymbol != "USDJPY" ||
      StringSubstr(Symbol(),0,6) != TradeSymbol)
      return(INIT_PARAMETERS_INCORRECT);

   // テスター出力ファイルを開く前に、ストラテジーパラメータを検証する。
   if(RSIEntry <= 0 || RSIEntry >= 50 || StopATR <= 0 || HoldBars < 1 ||
      EntryRiskPercent <= 0 || MaxSpreadPips <= 0 || MagicNumber <= 0)
      return(INIT_PARAMETERS_INCORRECT);

   // サーバー・銘柄をハッシュ化し、保存キーを63文字以内の英数字で構成する。
   string scope = AccountServer() + "|" + Symbol();
   uint scopeHash = 2166136261;
   for(int k = 0; k < StringLen(scope); k++)
      scopeHash = (scopeHash ^ (uint)StringGetCharacter(scope, k)) * 16777619;
   exitPrefix = "STR02." + IntegerToString(AccountNumber()) + "." +
                IntegerToString(MagicNumber) + "." + IntegerToString((int)scopeHash) + ".";
   // 実運用では最初の有効なティックで現在足を既処理化する。テスターは従来の開始判定を維持する。
   entryReady = IsTesting();

   // 有効証拠金曲線はテスター内だけに記録し、銘柄の取引仕様は実運用でも出力する。
   if(IsTesting())
   {
      equityFile = FileOpen("STR02_USDJPY_H1_equity.csv",
                            FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(equityFile == INVALID_HANDLE)
         return(INIT_FAILED);
      FileWrite(equityFile, "time", "equity", "balance");
   }
   Print("SPEC currency=", AccountCurrency(), " capital=", AccountBalance(),
         " tick_size=", MarketInfo(Symbol(), MODE_TICKSIZE),
         " tick_value=", MarketInfo(Symbol(), MODE_TICKVALUE),
         " min_lot=", MarketInfo(Symbol(), MODE_MINLOT),
         " lot_step=", MarketInfo(Symbol(), MODE_LOTSTEP),
         " spread=", MarketInfo(Symbol(), MODE_SPREAD));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EA終了処理                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(equityFile != INVALID_HANDLE)
   {
      // テスター出力ファイルを閉じる前に、最後の観測値を書き出す。
      if(lastTick > 0)
         FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                   DoubleToString(AccountEquity(), 2),
                   DoubleToString(AccountBalance(), 2));
      FileClose(equityFile);
   }
}

//+------------------------------------------------------------------+
//| ティック処理                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now=TimeCurrent();

   // サーバー時刻の日付が変わったら、直前の日の最後の観測値を記録する。
   if(equityFile != INVALID_HANDLE && lastTick > 0 &&
      (long)now / 86400 != (long)lastTick / 86400)
      FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                DoubleToString(lastEquity, 2), DoubleToString(lastBalance, 2));
   lastTick = now;
   lastEquity = AccountEquity();
   lastBalance = AccountBalance();
   // 新規発注はH1新バーごとに1回だけ判定し、既存ポジションの決済管理は毎ティック実行する。
   datetime bar = iTime(Symbol(), PERIOD_H1, 0);
   bool historyReady = (bar > 0 && iBars(Symbol(), PERIOD_H1) >= 220);
   if(!entryReady && bar > 0)
   {
      lastBar = bar;
      entryReady = true;
   }
   bool newBar = (bar > 0 && bar != lastBar);
   if(newBar) lastBar = bar;
   // RSIシグナルには確定済みのH1バーだけを使用する。履歴不足でも保存済み決済要求は処理する。
   double rsi = (historyReady ? iRSI(Symbol(), PERIOD_H1, 2, PRICE_CLOSE, 1) : 0);
   double pip = Point * (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
   int slippage = (int)MathRound(2.0 * pip / Point); // 元の3桁USDJPYの20 points = 2 pips。
   bool occupied = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         Print("OrderSelect failed ", GetLastError());
         return;
      }
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      occupied = true;
      int side = OrderType();
      if(side != OP_BUY && side != OP_SELL)
         continue;

      // RSI回復、または回復しない場合の保有期間上限で決済要求を保持する。
      int ticket = OrderTicket();
      string exitKey = exitPrefix + IntegerToString(ticket);
      int pendingIndex = -1;
      for(int j = 0; j < ArraySize(exitTickets); j++)
         if(exitTickets[j] == ticket) pendingIndex = j;
      bool savedExit = (!IsTesting() && GlobalVariableCheck(exitKey));
      bool recovered = historyReady && (side == OP_BUY ? rsi > 50 : rsi < 50);
      int heldBars = iBarShift(Symbol(), PERIOD_H1, OrderOpenTime(), false);
      if(pendingIndex < 0 && !savedExit && !recovered && heldBars < HoldBars)
         continue;
      if(pendingIndex < 0)
      {
         pendingIndex = ArraySize(exitTickets);
         if(ArrayResize(exitRetryTimes, pendingIndex + 1) != pendingIndex + 1 ||
            ArrayResize(exitTickets, pendingIndex + 1) != pendingIndex + 1)
         {
            stateHealthy = false;
            Alert("STR02: cannot retain exit request; new entries blocked. ticket=", ticket);
            return;
         }
         exitTickets[pendingIndex] = ticket;
         exitRetryTimes[pendingIndex] = 0;
      }
      // 保存失敗でもメモリ上の決済要求は維持する。新規発注を停止し、次の再試行時にも保存を試みる。
      if(now < exitRetryTimes[pendingIndex]) continue;
      if(!IsTesting() && !savedExit)
      {
         ResetLastError();
         if(GlobalVariableSet(exitKey, 1.0) == 0)
         {
            stateHealthy = false;
            Alert("STR02: exit state save failed; new entries blocked. ticket=", ticket,
                  " error=", GetLastError());
         }
         else
            GlobalVariablesFlush();
      }
      // 自動売買禁止・通信断・他EAの取引処理中でも、決済要求を取り消さず次のティックへ持ち越す。
      exitRetryTimes[pendingIndex] = now + 5;
      if(!IsTradeAllowed() || (!IsTesting() && !IsConnected()))
         continue;
      RefreshRates();
      // 再試行直前にチケットを再選択し、SL約定・手動決済済みの注文を再送しない。
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
      {
         Print("Exit OrderSelect failed ticket=", ticket, " error=", GetLastError());
         continue;
      }
      if(OrderCloseTime() != 0 || OrderSymbol() != Symbol() ||
         OrderMagicNumber() != MagicNumber || OrderType() != side)
         continue;
      double price = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

      // ポジションのSLがブローカーのフリーズレベル内にある間は決済要求を保持して待機する。
      if(price <= 0 || (freeze > 0 && OrderStopLoss() > 0 &&
         MathAbs(price - OrderStopLoss()) <= freeze))
         continue;
      ResetLastError();
      if(!OrderClose(ticket, OrderLots(), price, slippage, clrNONE))
         Print("Exit failed ticket=", ticket, " error=", GetLastError(), "; retry after >=5 seconds");
      else
      {
         exitTickets[pendingIndex] = exitTickets[ArraySize(exitTickets) - 1];
         exitRetryTimes[pendingIndex] = exitRetryTimes[ArraySize(exitTickets) - 1];
         ArrayResize(exitTickets, ArraySize(exitTickets) - 1);
         ArrayResize(exitRetryTimes, ArraySize(exitTickets));
         if(!IsTesting() && GlobalVariableCheck(exitKey))
         {
            if(!GlobalVariableDel(exitKey))
               Print("Exit state cleanup failed ticket=", ticket, " error=", GetLastError());
            GlobalVariablesFlush();
         }
      }
   }
   // このEAのポジションがある場合、そのバーでは新規エントリーしない。決済したバーも再発注しない。
   if(occupied || !newBar || !historyReady || !AllowNewEntries || !stateHealthy)
      return;
   // 新規注文の失敗は同じバーで再送しない。タイムアウト時の二重発注を避ける。
   if(!IsTradeAllowed() || (!IsTesting() && !IsConnected()))
      return;
   RefreshRates();
   if(Bid <= 0 || Ask <= Bid || Ask - Bid > MaxSpreadPips * pip)
      return;
   // EMA(200)で方向を判定し、確定済みRSI(2)の押し目・戻りを探す。
   double trend = iMA(Symbol(), PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1 = iClose(Symbol(), PERIOD_H1, 1);
   int side = -1;
   if(close1 > trend && rsi < RSIEntry)
      side = OP_BUY;
   if(close1 < trend && rsi > 100.0 - RSIEntry)
      side = OP_SELL;
   if(side < 0)
      return;
   // ATRベースのSLを作成し、銘柄のtick・取引数量設定を検証する。
   double atr = iATR(Symbol(), PERIOD_H1, 14, 1);
   double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(atr <= 0 || tick <= 0 || tickValue <= 0 || step <= 0)
      return;
   double entry = (side == OP_BUY ? Ask : Bid);
   double stop = entry + (side == OP_BUY ? -1.0 : 1.0) * StopATR * atr;

   // 不利な方向へ丸め、SLがtick刻み上で有効になるように整列する。
   stop = NormalizeDouble((side == OP_BUY ? MathFloor(stop / tick) : MathCeil(stop / tick)) * tick,
                          Digits);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick;
   if(side == OP_BUY && Bid - stop < minDistance)
      return;
   if(side == OP_SELL && stop - Ask < minDistance)
      return;
   // 計算したSLまでの金銭的リスクを基準にポジションサイズを決定する。
   double capital = MathMin(AccountBalance(), AccountEquity());
   double riskPerLot = MathAbs(entry - stop) / tick * tickValue;
   double lots = MathMin(capital * EntryRiskPercent / 100.0 / riskPerLot,
                         MarketInfo(Symbol(), MODE_MAXLOT));
   lots = NormalizeDouble(MathFloor((lots + 1e-10) / step) * step, 8);
   if(lots < MarketInfo(Symbol(), MODE_MINLOT))
      return;

   // 発注後も資本の30%を余剰証拠金として残せることを確認する。
   ResetLastError();
   double freeAfter = AccountFreeMarginCheck(Symbol(), side, lots);
   if(GetLastError() != 0 || freeAfter < 0.3 * capital)
      return;
   // ATR初期SLを付け、TPなしの成行注文を送信する。
   int ticket = OrderSend(Symbol(), side, lots, entry, slippage, stop, 0,
                          "STR02 trend pullback", MagicNumber, 0, clrNONE);
   if(ticket < 0)
      Print("Entry failed error=", GetLastError());
}
