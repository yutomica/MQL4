//+------------------------------------------------------------------+
//|                                              STR02_USDJPY_H1.mq4 |
//|              H1 RSI(2) EMA(200)方向押し目・戻り売りEA              |
//+------------------------------------------------------------------+

/*
売買ロジック
- エントリー:
  H1の新バーごとに、確定した直近バー（シフト1）だけをシグナル判定に使用する。
  終値がEMA(200)より上でRSI(2)がRSIEntry未満なら買いシグナルとする。
  終値がEMA(200)より下でRSI(2)が100-RSIEntryより上なら売りシグナルとする。
  実口座・デモ口座・テスターで、USDJPYのH1、かつスプレッドがMaxSpreadPips以内の場合だけ新規エントリーする。
  確定H1 ATR(14)が発注時スプレッドのMinATRSpreadRatio倍（初期17.5）未満なら見送る。0で無効。
  EntryPullbackATR>0では、シグナル判定バーの終端まで有効なATR押し目・戻り指値を発注する。0で成行注文。
  初期設定はRSIEntry=7.5、StopATR=2.5。実運用では起動後最初のH1バーの新規エントリーを見送る。
  AllowNewEntries=falseで新規発注だけを停止し、既存ポジションの決済管理は継続する。
- エグジット:
  買いはRSIがRSIExitを上回った時、売りはRSIが100-RSIExitを下回った時に全量決済する。
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

#include <Original/Mail.mqh>
#include <Original/TradeControl.mqh>
#property description "H1 RSI(2) EMA(200)方向押し目・戻り売り。USDJPY H1実運用対応版。"

#define MAGIC 20260913
#define COMMENT "STR02_USDJPY_H1"

// Log identity is cached once; logging does not query orders or consume errors.
string gLogIdentity = "";
int gEntryMailTickets[]; // 約定通知待ちの注文ticket

//+------------------------------------------------------------------+
//| ストラテジーパラメータ                                         |
//+------------------------------------------------------------------+
input string TradeSymbol = "USDJPY";
input double RSIEntry = 7.5;
input double RSIExit = 40.0;
input double StopATR = 2.5;
input int HoldBars = 24;
input double EntryRiskPercent = 0.25;
input double MaxSpreadPips = 2.0;
input bool AllowNewEntries = true; // falseでも既存ポジションの決済は継続する。
input double MinATRSpreadRatio = 17.5; // 0で無効。ATRとAsk-Bidを同じ価格単位で比較する。
input double EntryPullbackATR = 0.2; // 0で従来の成行注文。正値ではATR押し目・戻り指値を発注する。

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
bool     gReleasePending = false;
string   gSendKey = "";
double   gSendNumber = 0;
bool     gSendHandled = false;
bool     entryRetryPending = false;
datetime entryRetryBar = 0;
datetime entryRetryStarted = 0;
datetime entryRetryNext = 0;
int      entryRetryCmd = -1;
int      entryRetrySide = -1;
double   entryRetryLots = 0;
double   entryRetryPrice = 0;
double   entryRetryStop = 0;
double   entryRetryATR = 0;
datetime entryRetryExpiration = 0;

//+------------------------------------------------------------------+
//| EA初期化                                                        |
//+------------------------------------------------------------------+
int OnInit()
{

   // Chart and session distinguish parallel charts and subsequent initializations.
   gLogIdentity = "ea=" + COMMENT + " symbol=" + Symbol() +
                  " tf=" + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) +
                  " magic=" + IntegerToString(MAGIC) +
                  " chart=" + IntegerToString(ChartID()) +
                  " session=" + IntegerToString((long)TimeLocal()) + "-" +
                  IntegerToString((long)GetTickCount()) + " ";
   Print(gLogIdentity, "event=INIT_BEGIN compiled=", __DATETIME__);
   entryRetryPending = false;
   if(Period() != PERIOD_H1 || TradeSymbol != "USDJPY" ||
      StringSubstr(Symbol(),0,6) != TradeSymbol)
      return(INIT_PARAMETERS_INCORRECT);

   // テスター出力ファイルを開く前に、ストラテジーパラメータを検証する。
   if(RSIEntry <= 0 || RSIEntry >= 50 || RSIExit <= 0 || RSIExit >= 50 ||
      StopATR <= 0 || HoldBars < 1 || EntryPullbackATR < 0 || EntryRiskPercent <= 0 ||
      MaxSpreadPips <= 0 || MinATRSpreadRatio < 0 || MAGIC <= 0)
      return(INIT_PARAMETERS_INCORRECT);

   if(!TC_Init(2000)) return(INIT_FAILED);
   gReleasePending = false;

   // サーバー・銘柄をハッシュ化し、保存キーを63文字以内の英数字で構成する。
   string scope = AccountServer() + "|" + Symbol();
   uint scopeHash = 2166136261;
   for(int k = 0; k < StringLen(scope); k++)
      scopeHash = (scopeHash ^ (uint)StringGetCharacter(scope, k)) * 16777619;
   exitPrefix = "STR02." + IntegerToString(AccountNumber()) + "." +
                IntegerToString(MAGIC) + "." + IntegerToString((int)scopeHash) + ".";
   gSendKey = exitPrefix + "send";
   gSendNumber = 0;
   gSendHandled = false;
   if(!IsTesting() && GlobalVariableCheck(gSendKey) &&
      !GlobalVariableGet(gSendKey, gSendNumber)) return(INIT_FAILED);
   if(gSendNumber > 0)
      Print(gLogIdentity, "event=SEND_CHECK_REQUIRED id=", DoubleToString(gSendNumber, 0));
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
   Print(gLogIdentity, "event=SYMBOL_SPEC message=", "SPEC currency=", AccountCurrency(), " capital=", AccountBalance(),
         " tick_size=", MarketInfo(Symbol(), MODE_TICKSIZE),
         " tick_value=", MarketInfo(Symbol(), MODE_TICKVALUE),
         " min_lot=", MarketInfo(Symbol(), MODE_MINLOT),
         " lot_step=", MarketInfo(Symbol(), MODE_LOTSTEP),
         " spread=", MarketInfo(Symbol(), MODE_SPREAD));
   // 起動時に残っている待機注文も、約定後だけ通知する。
   ArrayResize(gEntryMailTickets,0);
   for(int mailIndex=OrdersTotal()-1; mailIndex>=0; mailIndex--)
   {
      if(!OrderSelect(mailIndex,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC ||
         OrderType()<OP_BUYLIMIT || OrderType()>OP_SELLSTOP) continue;
      int mailCount=ArraySize(gEntryMailTickets);
      if(ArrayResize(gEntryMailTickets,mailCount+1)==mailCount+1)
         gEntryMailTickets[mailCount]=OrderTicket();
   }
   Print(gLogIdentity, "event=INIT_OK");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EA終了処理                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gReleasePending) gReleasePending = !TC_End(true);
   if(equityFile != INVALID_HANDLE)
   {
      // テスター出力ファイルを閉じる前に、最後の観測値を書き出す。
      if(lastTick > 0)
         FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                   DoubleToString(AccountEquity(), 2),
                   DoubleToString(AccountBalance(), 2));
      FileClose(equityFile);
   }
   Print(gLogIdentity, "event=DEINIT reason=", reason);
}

//+------------------------------------------------------------------+
//| ティック処理                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   if(gReleasePending) gReleasePending = !TC_End(true);
   // 結果不明の新規注文は実注文・履歴と照合する。見つからない間は再送しない。
   if(gSendNumber > 0)
   {
      string tag = COMMENT + "#" + DoubleToString(gSendNumber, 0);
      int found = -1;
      for(int pool = 0; pool < 2 && found < 0; pool++)
      {
         int total = (pool == 0 ? OrdersTotal() : OrdersHistoryTotal());
         for(int index = total - 1; index >= 0; index--)
         {
            if(!OrderSelect(index, SELECT_BY_POS, pool == 0 ? MODE_TRADES : MODE_HISTORY)) continue;
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC &&
               StringFind(OrderComment(), tag) == 0) { found = OrderTicket(); break; }
         }
      }
      if(found > 0 && (IsTesting() || GlobalVariableSet(gSendKey, -gSendNumber) != 0))
      {
         gSendNumber = -gSendNumber;
         entryRetryPending = false;
         if(!IsTesting()) GlobalVariablesFlush();
         if(!gSendHandled)
         {
            int mailCount = ArraySize(gEntryMailTickets);
            if(ArrayResize(gEntryMailTickets, mailCount + 1) == mailCount + 1)
               gEntryMailTickets[mailCount] = found;
         }
         Print(gLogIdentity, "event=SEND_RECONCILED ticket=", found);
      }
   }
   // 待機注文がBuy/Sellに変わった時だけ通知し、処理済みticketを外す。
   for(int mailIndex=ArraySize(gEntryMailTickets)-1; !gReleasePending && mailIndex>=0; mailIndex--)
   {
      if(!OrderSelect(gEntryMailTickets[mailIndex],SELECT_BY_TICKET)) continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC)
      {
         if(OrderType()==OP_BUY || OrderType()==OP_SELL)
            MySendMail(COMMENT,OrderType()==OP_BUY ? 1 : 2);
         else if(OrderCloseTime()==0)
            continue;
      }
      // 取消・期限切れは通知しない。約定後すぐ決済されたticketも上で確認する。
      int mailLast=ArraySize(gEntryMailTickets)-1;
      gEntryMailTickets[mailIndex]=gEntryMailTickets[mailLast];
      ArrayResize(gEntryMailTickets,mailLast);
   }
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
         Print(gLogIdentity, "event=ORDER_SELECT_FAILED message=", "OrderSelect failed ", GetLastError());
         return;
      }
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC)
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
      bool recovered = historyReady && (side == OP_BUY ? rsi > RSIExit : rsi < 100.0 - RSIExit);
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
            Alert(gLogIdentity, "event=EXIT_REQUEST_RETAIN_FAILED message=", "STR02: cannot retain exit request; new entries blocked. ticket=", ticket);
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
            Alert(gLogIdentity, "event=EXIT_STATE_SAVE_FAILED message=", "STR02: exit state save failed; new entries blocked. ticket=", ticket,
                  " error=", GetLastError());
         }
         else
            GlobalVariablesFlush();
      }
      // 自動売買禁止・通信断・他EAの取引処理中でも、決済要求を取り消さず次のティックへ持ち越す。
      if(gReleasePending || !IsTradeAllowed() || (!IsTesting() && !IsConnected()) || !TC_Begin())
         continue;
      RefreshRates();
      // 再試行直前にチケットを再選択し、SL約定・手動決済済みの注文を再送しない。
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
      {
         int selectError = GetLastError();
         TC_End(false);
         Print(gLogIdentity, "event=EXIT_SELECT_FAILED message=", "Exit OrderSelect failed ticket=", ticket, " error=", selectError);
         continue;
      }
      if(OrderCloseTime() != 0 || OrderSymbol() != Symbol() ||
         OrderMagicNumber() != MAGIC || OrderType() != side)
      { TC_End(false); continue; }
      double price = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

      // ポジションのSLがブローカーのフリーズレベル内にある間は決済要求を保持して待機する。
      if(price <= 0 || (freeze > 0 && OrderStopLoss() > 0 &&
         MathAbs(price - OrderStopLoss()) <= freeze) ||
         !IsTradeAllowed() || (!IsTesting() && !IsConnected()))
      { TC_End(false); continue; }
      ResetLastError();
      bool closed = OrderClose(ticket, OrderLots(), price, slippage, clrNONE);
      int closeError = GetLastError();
      gReleasePending = !TC_End(true);
      exitRetryTimes[pendingIndex] = TimeCurrent() + 5;
      if(!closed)
         Print(gLogIdentity, "event=EXIT_FAILED message=", "Exit failed ticket=", ticket, " error=", closeError, "; retry after >=5 seconds");
      else
      {
         exitTickets[pendingIndex] = exitTickets[ArraySize(exitTickets) - 1];
         exitRetryTimes[pendingIndex] = exitRetryTimes[ArraySize(exitTickets) - 1];
         ArrayResize(exitTickets, ArraySize(exitTickets) - 1);
         ArrayResize(exitRetryTimes, ArraySize(exitTickets));
         if(!IsTesting() && GlobalVariableCheck(exitKey))
         {
            if(!GlobalVariableDel(exitKey))
               Print(gLogIdentity, "event=EXIT_STATE_CLEANUP_FAILED message=", "Exit state cleanup failed ticket=", ticket, " error=", GetLastError());
            GlobalVariablesFlush();
         }
      }
   }
   if(entryRetryPending && (!historyReady || !AllowNewEntries || !stateHealthy || occupied ||
      bar != entryRetryBar || (entryRetryStarted > 0 && now > entryRetryStarted + 5) ||
      (entryRetryExpiration > 0 && now >= entryRetryExpiration)))
      entryRetryPending = false;
   // このEAのポジションがある場合、そのバーでは新規エントリーしない。決済したバーも再発注しない。
   if(!entryRetryPending && gSendNumber <= 0 && !occupied && newBar && historyReady && AllowNewEntries && stateHealthy)
   {
      // 他EAの送信中でも候補を保存する。自動売買OFF時は従来どおりそのバーを見送る。
      if((IsTesting() && !IsTradeAllowed()) || (!IsTesting() &&
         (!IsConnected() || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))))
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
      // 費用に対する回復値幅が小さい局面を除外する。閾値と等しい場合は許可する。
      if(MinATRSpreadRatio > 0 && atr < MinATRSpreadRatio * (Ask - Bid))
         return;
      int orderCmd = side;
      datetime expiration = 0;
      double entry = (side == OP_BUY ? Ask : Bid);
      if(EntryPullbackATR > 0)
      {
         orderCmd = (side == OP_BUY ? OP_BUYLIMIT : OP_SELLLIMIT);
         entry = (side == OP_BUY ? Ask - EntryPullbackATR * atr : Bid + EntryPullbackATR * atr);
         entry = NormalizeDouble((side == OP_BUY ? MathFloor(entry / tick) : MathCeil(entry / tick)) * tick,
                                 Digits);
         expiration = bar + 3600;
      }
      double stop = entry + (side == OP_BUY ? -1.0 : 1.0) * StopATR * atr;

      // 不利な方向へ丸め、SLがtick刻み上で有効になるように整列する。
      stop = NormalizeDouble((side == OP_BUY ? MathFloor(stop / tick) : MathCeil(stop / tick)) * tick,
                             Digits);
      double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick;
      if(EntryPullbackATR > 0)
      {
         if(side == OP_BUY && (Ask - entry < minDistance || entry - stop < minDistance))
            return;
         if(side == OP_SELL && (entry - Bid < minDistance || stop - entry < minDistance))
            return;
      }
      else
      {
         if(side == OP_BUY && Bid - stop < minDistance)
            return;
         if(side == OP_SELL && stop - Ask < minDistance)
            return;
      }
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
      // 新バーで確定した要求を保存する。未送信では5秒の再送期限を開始しない。
      entryRetryPending = true;
      entryRetryBar = bar;
      entryRetryStarted = 0;
      entryRetryNext = 0;
      entryRetryCmd = orderCmd;
      entryRetrySide = side;
      entryRetryLots = lots;
      entryRetryPrice = entry;
      entryRetryStop = stop;
      entryRetryATR = atr;
      entryRetryExpiration = expiration;
   }
   // 初回未送信と8/141の再送を区別し、保存した要求を同じH1バー内で処理する。
   if(entryRetryPending)
   {
      if(!historyReady || !AllowNewEntries || !stateHealthy || occupied || bar != entryRetryBar || (entryRetryStarted > 0 && now > entryRetryStarted + 5) ||
         (entryRetryExpiration > 0 && now >= entryRetryExpiration))
      {
         entryRetryPending = false;
      }
      else if(!gReleasePending && gSendNumber <= 0 && now >= entryRetryNext)
      {
         // 送信直前にも安全条件を確認する。指値価格・SL・数量は保持し、成行価格は直前に更新する。
         if(IsTradeAllowed() && (IsTesting() || IsConnected()) && TC_Begin())
         {
            bool retryOccupied = false;
            bool retryReadable = true;
            for(int check = OrdersTotal() - 1; check >= 0; check--)
            {
               if(!OrderSelect(check, SELECT_BY_POS, MODE_TRADES)) { retryReadable = false; break; }
               if(OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC) retryOccupied = true;
            }
            RefreshRates();
            double retryTick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double retryStep = MarketInfo(Symbol(), MODE_LOTSTEP);
            double retryMinDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + retryTick;
            double retryCapital = MathMin(AccountBalance(), AccountEquity());
            bool retryValid = (retryReadable && !retryOccupied && AllowNewEntries && stateHealthy &&
                               iTime(Symbol(), PERIOD_H1, 0) == entryRetryBar &&
                               (entryRetryExpiration == 0 || TimeCurrent() < entryRetryExpiration) &&
                               (entryRetryStarted == 0 || TimeCurrent() <= entryRetryStarted + 5) &&
                               Bid > 0 && Ask > Bid && retryTick > 0 && retryStep > 0 &&
                               Ask - Bid <= MaxSpreadPips * pip &&
                               (MinATRSpreadRatio <= 0 || entryRetryATR >= MinATRSpreadRatio * (Ask - Bid)) &&
                               entryRetryLots >= MarketInfo(Symbol(), MODE_MINLOT) &&
                               entryRetryLots <= MarketInfo(Symbol(), MODE_MAXLOT) &&
                               MathAbs(entryRetryLots / retryStep - MathRound(entryRetryLots / retryStep)) <= 1.0e-8);
            if(entryRetryCmd == OP_BUYLIMIT)
               retryValid = retryValid && Ask - entryRetryPrice >= retryMinDistance &&
                            entryRetryPrice - entryRetryStop >= retryMinDistance;
            else if(entryRetryCmd == OP_SELLLIMIT)
               retryValid = retryValid && entryRetryPrice - Bid >= retryMinDistance &&
                            entryRetryStop - entryRetryPrice >= retryMinDistance;
            else
               retryValid = retryValid && (entryRetrySide == OP_BUY ?
                            Bid - entryRetryStop : entryRetryStop - Ask) >= retryMinDistance;
            ResetLastError();
            double retryFreeAfter = retryValid ? AccountFreeMarginCheck(Symbol(), entryRetrySide,
                                                                         entryRetryLots) : -1;
            int retryMarginError = GetLastError();
            retryValid = retryValid && retryMarginError == 0 &&
                         retryFreeAfter >= 0.3 * retryCapital;
            if(!retryValid)
            {
               TC_End(false);
               Print(gLogIdentity, "event=ENTRY_RETRY_CANCELLED message=", "Entry retry cancelled: current safety condition failed.");
               entryRetryPending = false;
            }
            else
            {
               bool retrying = (entryRetryStarted > 0);
               gSendHandled = false;
               gSendNumber = MathMax(MathAbs(gSendNumber) + 1, (double)TimeLocal() * 1000.0);
               if(!IsTesting() && GlobalVariableSet(gSendKey, gSendNumber) == 0)
               {
                  TC_End(false);
                  stateHealthy = false;
                  entryRetryPending = false;
                  Print(gLogIdentity, "event=SEND_SAVE_FAILED");
                  return;
               }
               if(!IsTesting()) GlobalVariablesFlush();
               RefreshRates();
               bool sendValid = iTime(Symbol(), PERIOD_H1, 0) == entryRetryBar &&
                                (entryRetryExpiration == 0 || TimeCurrent() < entryRetryExpiration) &&
                                (entryRetryStarted == 0 || TimeCurrent() <= entryRetryStarted + 5) &&
                                Bid > 0 && Ask > Bid && Ask - Bid <= MaxSpreadPips * pip &&
                                (MinATRSpreadRatio <= 0 || entryRetryATR >= MinATRSpreadRatio * (Ask - Bid));
               if(entryRetryCmd == OP_BUYLIMIT)
                  sendValid = sendValid && Ask - entryRetryPrice >= retryMinDistance;
               else if(entryRetryCmd == OP_SELLLIMIT)
                  sendValid = sendValid && entryRetryPrice - Bid >= retryMinDistance;
               else
                  sendValid = sendValid && (entryRetrySide == OP_BUY ?
                              Bid - entryRetryStop : entryRetryStop - Ask) >= retryMinDistance;
               // 指値は予約価格を維持。成行は最新気配を使い、固定したSL・数量のリスクを再確認する。
               double sendPrice = (entryRetryCmd == OP_BUY ? Ask :
                                   entryRetryCmd == OP_SELL ? Bid : entryRetryPrice);
               double sendTickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
               double sendRisk = MathAbs(sendPrice - entryRetryStop) / retryTick * sendTickValue * entryRetryLots;
               sendValid = sendValid && sendTickValue > 0 &&
                           sendRisk <= MathMin(AccountBalance(), AccountEquity()) * EntryRiskPercent / 100.0 + 1e-8;
               if(!sendValid || !IsTradeAllowed() || (!IsTesting() && !IsConnected()))
               {
                  if(IsTesting() || GlobalVariableSet(gSendKey, -gSendNumber) != 0)
                     gSendNumber = -gSendNumber;
                  if(!IsTesting()) GlobalVariablesFlush();
                  TC_End(false);
                  entryRetryPending = sendValid && gSendNumber <= 0;
                  return;
               }
               ResetLastError();
               int retryTicket = OrderSend(Symbol(), entryRetryCmd, entryRetryLots,
                                           sendPrice, slippage, entryRetryStop, 0,
                                           COMMENT + "#" + DoubleToString(gSendNumber, 0), MAGIC, entryRetryExpiration, clrNONE);
               int retryError = GetLastError();
               gReleasePending = !TC_End(true);
               bool unknown = retryTicket < 0 && (retryError == 0 || retryError == 1 ||
                              retryError == 2 || retryError == 6 || retryError == 128);
               bool saved = !unknown && (IsTesting() || GlobalVariableSet(gSendKey, -gSendNumber) != 0);
               if(saved) gSendNumber = -gSendNumber;
               if(!IsTesting()) GlobalVariablesFlush();
               if(retryTicket >= 0)
               {
                  gSendHandled = true;
                  if(retrying)
                     Print(gLogIdentity, "event=ENTRY_RETRY_OK message=", "Pending entry retry succeeded ticket=", retryTicket);
                  else if(entryRetryCmd >= OP_BUYLIMIT)
                     Print(gLogIdentity, "event=ENTRY_PENDING message=", "Pending entry ticket=", retryTicket,
                           " side=", (entryRetrySide == OP_BUY ? "BUY" : "SELL"),
                           " entryATR=", DoubleToString(entryRetryATR, Digits),
                           " limit=", DoubleToString(entryRetryPrice, Digits),
                           " expiration=", TimeToString(entryRetryExpiration, TIME_DATE | TIME_SECONDS));
                  entryRetryPending = false;
                  int mailCount=ArraySize(gEntryMailTickets);
                  if(!gReleasePending && OrderSelect(retryTicket, SELECT_BY_TICKET) &&
                     (OrderType() == OP_BUY || OrderType() == OP_SELL))
                     MySendMail(COMMENT, OrderType() == OP_BUY ? 1 : 2);
                  else if(ArrayResize(gEntryMailTickets,mailCount+1)==mailCount+1)
                     gEntryMailTickets[mailCount]=retryTicket;
               }
               else
               {
                  Print(gLogIdentity, retrying ? "event=ENTRY_RETRY_FAILED message=" : "event=ENTRY_FAILED message=",
                        "Entry failed error=", retryError);
                  if(saved && entryRetryCmd >= OP_BUYLIMIT && (retryError == 8 || retryError == 141))
                  {
                     if(entryRetryStarted == 0) entryRetryStarted = TimeCurrent();
                     entryRetryNext = TimeCurrent() + 2;
                  }
                  else
                     entryRetryPending = false;
               }
            }
         }
      }
   }
}
