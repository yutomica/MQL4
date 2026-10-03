//+------------------------------------------------------------------+
//|                  決済需要日限定・東京仲値前後売買EA                 |
//+------------------------------------------------------------------+

/*
運用対象
- USDJPY/M30、決済需要日限定の東京仲値前後売買。
- 日本銀行営業日の5の倍数日または月末最終営業日。休日の前倒しなし。
- JST09:50買い、09:55決済後に売り、10:00に半量決済、残余10:30決済。ATR20shift2の2倍を初期SLとする。
- 冬UTC+2/夏UTC+3（米国DST）を想定。祝日対応は2021～2028年（2028年は暫定）。
- ロットは既定0.1、他EAと異なる正のMAGICを使用する。同一EAの重複装着はしない。

売買ロジック
- エントリー:
  M30確定を待たず指定分内で判定し、MaxSpreadPips超過なら発注を見送る。
  前半買いの未約定・SL・損益によらず後半売りを判定するが、買いが残っている間は売らない。
  サーバー時刻は米国夏時間の日付規則からJSTへ変換し、日本の休場日は新規発注しない。
- エグジット:
  買いはJST09:55、売りはJST10:00に50%を決済し、残余を10:30に決済する。
  約定日の翌日以後へ持ち越した場合は全量を決済する。
  決済失敗時は成立した決済シグナルを保持し、後続ティックで再試行する。
- SL:
  発注時からSLを付け、約定価格からStopATR倍のATR幅へ補正する。固定TPは設定しない。
  SLはtick刻みへ外側に丸める。補正待ちの間も発注時のSLを維持する。
  買いは0.25ATR順行時に建値SLを試みる。TrailATRが正なら同ATR幅以上の
  含み益から追随し、SLは有利な方向だけへ動かす。
- ポジション数・ロット:
  同一Symbol・MAGICの注文がある間は新規発注しない。ロットはFixedLotsの固定値。
  最小・最大ロット、ロットステップに適合しない設定は初期化時に拒否する。
- 決済後休止:
  SLを含む最終決済バーの次のバーから、完了した平日のシグナル時間足バーをCooldownDays本数える。
  決済と同じ足には再エントリーしない。ただし09:55の後半売りには休止と同バー制限を適用しない。
  時刻・曜日はサーバー時刻を使い、土日のバーは休止本数に含めない。
- テスター出力:
  日ごとの有効証拠金と残高をCSVへ記録する。スワップ・手数料はMT4口座計算に従う。
  保有コストの再現性はテスターの銘柄設定・データに依存する。
*/

#property strict

#define MAGIC 20260926
#define COMMENT "STR03_USDJPY_M30"

// Log identity is cached once; logging does not query orders or consume errors.
string gLogIdentity = "";
#property description "USDJPY/M30 決済需要日限定。09:50買い・09:55売り、買い建値SL、売り10:00半量・10:30残余決済。"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern string TradeSymbol = "USDJPY";
extern int SignalTimeframe = PERIOD_M30; // 選定版はM30固定
extern int TokyoEntryMinute = 590;     // JST09:50固定
extern int TokyoExitMinute = 600;      // JST10:00固定
extern int SellFinalMinute = 630;      // 売り残余の決済時刻: 600/615/630/660
extern int SellFirstClosePercent = 50; // 売りのJST10:00部分決済率: 30/50/70%
extern double BuyBreakEvenATR = 0.25;  // 買い建値SL開始: 0/0.125/0.25/0.375/0.5 ATR
extern int SettlementDaysOnly = 1;     // 1=5の倍数日+月末、休日の前倒しなし（固定）
extern double StopATR = 2.0;           // 選定版はATR20shift2の2倍に固定
extern int ATRPeriod = 20;             // ATR期間: 14/20/28/40
extern int CooldownDays = 1;           // 決済後休止: 完了した平日のシグナル時間足バー数（名前は互換性のため維持）
extern double FixedLots = 0.2;
extern double MaxSpreadPips = 2.0;
extern int Slippage = 50;              // point単位、各発注・決済要求に適用
extern string EquityFileName = "";       // 空なら実行時刻を含む一意なCSV名を生成
extern double TrailATR = 0.75;         // 0=無効、含み益が同ATR幅に達したら追随

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
datetime lastBar = 0;
datetime lastClose = 0;
datetime lastTick = 0;
double lastEquity = 0;
double lastBalance = 0;
int equityFile = INVALID_HANDLE;
int exitTicket = -1;
int stopTicket = -1;
double stopTarget = 0;
double stopDistance = 0;
int heldTicket = -1;
string statePrefix = "";
int lastTokyoEntryDate = 0;
int lastTokyoSellDate = 0;
int lastTokyoSellPartialDate = 0;
int blockedBuyDate = 0;
int blockedSellDate = 0;
datetime nextEntryAttempt = 0;
int partialBaseDate = 0;
double partialBaseLots = 0;
int splitStopDate = 0;
double splitStopDistance = 0;
// 2028年は現行祝日法と国立天文台の予測に基づく。2027年2月の官報公表後に再確認。
string tokyoHolidays = ",20210101,20210111,20210211,20210223,20210320,20210429,20210503,20210504,20210505,20210722,20210723,20210808,20210809,20210920,20210923,20211103,20211123,20220101,20220110,20220211,20220223,20220321,20220429,20220503,20220504,20220505,20220718,20220811,20220919,20220923,20221010,20221103,20221123,20230101,20230102,20230109,20230211,20230223,20230321,20230429,20230503,20230504,20230505,20230717,20230811,20230918,20230923,20231009,20231103,20231123,20240101,20240108,20240211,20240212,20240223,20240320,20240429,20240503,20240504,20240505,20240506,20240715,20240811,20240812,20240916,20240922,20240923,20241014,20241103,20241104,20241123,20250101,20250113,20250211,20250223,20250224,20250320,20250429,20250503,20250504,20250505,20250506,20250721,20250811,20250915,20250923,20251013,20251103,20251123,20251124,20260101,20260112,20260211,20260223,20260320,20260429,20260503,20260504,20260505,20260506,20260720,20260811,20260921,20260922,20260923,20261012,20261103,20261123,20270101,20270111,20270211,20270223,20270321,20270322,20270429,20270503,20270504,20270505,20270719,20270811,20270920,20270923,20271011,20271103,20271123,20280101,20280110,20280211,20280223,20280320,20280429,20280503,20280504,20280505,20280717,20280811,20280918,20280922,20281009,20281103,20281123,";

//+------------------------------------------------------------------+
//| EA初期化                                                         |
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
   // 売買条件とMAGICは固定し、ロット・執行上限は設定可能。
   if(TradeSymbol != "USDJPY" || SignalTimeframe != PERIOD_M30 ||
      TokyoEntryMinute != 590 || TokyoExitMinute != 600 || SettlementDaysOnly != 1 ||
      ATRPeriod != 20 || MathAbs(StopATR - 2.0) > 1e-9 || CooldownDays != 1)
   {
      Print(gLogIdentity, "event=INIT_PARAMETERS_INVALID message=", "STR03 requires USDJPY/M30, JST590/600, Settlement1 and ATR20/Stop2.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(Period() != SignalTimeframe || StringSubstr(Symbol(), 0, 6) != TradeSymbol ||
      FixedLots <= 0 || MaxSpreadPips <= 0 || Slippage < 0 || MAGIC <= 0)
      return(INIT_PARAMETERS_INCORRECT);
   if(!MathIsValidNumber(TrailATR) || TrailATR < 0)
      return(INIT_PARAMETERS_INCORRECT);
   if((SellFinalMinute != 600 && SellFinalMinute != 615 &&
       SellFinalMinute != 630 && SellFinalMinute != 660) ||
      (SellFirstClosePercent != 30 && SellFirstClosePercent != 50 &&
       SellFirstClosePercent != 70))
      return(INIT_PARAMETERS_INCORRECT);
   if(!MathIsValidNumber(BuyBreakEvenATR) ||
      (BuyBreakEvenATR != 0 && BuyBreakEvenATR != 0.125 &&
       BuyBreakEvenATR != 0.25 && BuyBreakEvenATR != 0.375 && BuyBreakEvenATR != 0.5))
      return(INIT_PARAMETERS_INCORRECT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   if(step <= 0 || FixedLots < MarketInfo(Symbol(), MODE_MINLOT) ||
      FixedLots > MarketInfo(Symbol(), MODE_MAXLOT) ||
      MathAbs(FixedLots / step - MathRound(FixedLots / step)) > 1e-7)
      return(INIT_PARAMETERS_INCORRECT);
   if(SellFinalMinute > TokyoExitMinute)
   {
      double firstLots = NormalizeDouble(MathFloor(FixedLots * SellFirstClosePercent /
                                                   100.0 / step + 1e-9) * step, 8);
      double remainingLots = NormalizeDouble(FixedLots - firstLots, 8);
      if(firstLots < minLot || remainingLots < minLot ||
         MathAbs(firstLots / step - MathRound(firstLots / step)) > 1e-7 ||
         MathAbs(remainingLots / step - MathRound(remainingLots / step)) > 1e-7)
         return(INIT_PARAMETERS_INCORRECT);
   }

   // 運用中に装着・再初期化した場合は新規発注だけを途中参加させない。
   // 既存ポジションの決済・SL補正状態は端末Global Variableから復元する。
   if(!IsTesting())
   {
      lastBar = iTime(Symbol(), SignalTimeframe, 0);
      statePrefix = "STR03." + IntegerToString(AccountNumber()) + "." + Symbol() + "." +
                    IntegerToString(MAGIC);
      if(StringLen(statePrefix) + 18 > 63)
      {
         Print(gLogIdentity, "event=STATE_KEY_INVALID message=", "Persistent state key is too long for Symbol=", Symbol());
         return(INIT_PARAMETERS_INCORRECT);
      }
      string closeKey = statePrefix + ".close";
      string heldKey = statePrefix + ".held";
      if(GlobalVariableCheck(closeKey)) lastClose = (datetime)GlobalVariableGet(closeKey);
      if(GlobalVariableCheck(heldKey)) heldTicket = (int)GlobalVariableGet(heldKey);
      if(GlobalVariableCheck(statePrefix + ".tokyo"))
         lastTokyoEntryDate = (int)GlobalVariableGet(statePrefix + ".tokyo");
      if(GlobalVariableCheck(statePrefix + ".tokyosell"))
         lastTokyoSellDate = (int)GlobalVariableGet(statePrefix + ".tokyosell");
      if(GlobalVariableCheck(statePrefix + ".sellpartial"))
         lastTokyoSellPartialDate = (int)GlobalVariableGet(statePrefix + ".sellpartial");
      if(GlobalVariableCheck(statePrefix + ".buyblock"))
         blockedBuyDate = (int)GlobalVariableGet(statePrefix + ".buyblock");
      if(GlobalVariableCheck(statePrefix + ".sellblock"))
         blockedSellDate = (int)GlobalVariableGet(statePrefix + ".sellblock");
      if(GlobalVariableCheck(statePrefix + ".retry"))
         nextEntryAttempt = (datetime)GlobalVariableGet(statePrefix + ".retry");
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            Print(gLogIdentity, "event=INIT_SELECT_FAILED message=", "Init OrderSelect failed error=", GetLastError());
            continue;
         }
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC ||
            (OrderType() != OP_BUY && OrderType() != OP_SELL)) continue;
         heldTicket = OrderTicket();
         GlobalVariableSet(heldKey, heldTicket);
         string ticketPrefix = statePrefix + "." + IntegerToString(heldTicket);
         if(GlobalVariableCheck(ticketPrefix + ".exit")) exitTicket = heldTicket;
         if(GlobalVariableCheck(ticketPrefix + ".stop"))
         {
            stopTicket = heldTicket;
            stopDistance = GlobalVariableGet(ticketPrefix + ".stop");
         }
      }
      GlobalVariablesFlush();
   }
   if(IsTesting())
   {
      string outputName = EquityFileName;
      datetime localNow = TimeLocal();
      if(StringLen(outputName) == 0)
      {
         string outputBase = StringFormat("STR03_TokyoRound_%d_%d_%s_%d_%04d%02d%02d_%02d%02d%02d_equity",
                                          SignalTimeframe, AccountNumber(), Symbol(), MAGIC,
                                          TimeYear(localNow), TimeMonth(localNow), TimeDay(localNow),
                                          TimeHour(localNow), TimeMinute(localNow), TimeSeconds(localNow));
         outputName = outputBase + ".csv";
         int outputIndex = 1;
         while(FileIsExist(outputName))
         {
            outputName = outputBase + "_" + IntegerToString(outputIndex) + ".csv";
            outputIndex++;
         }
      }
      equityFile = FileOpen(outputName,
                            FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(equityFile == INVALID_HANDLE) return(INIT_FAILED);
      FileWrite(equityFile, "time", "equity", "balance");
      Print(gLogIdentity, "event=EQUITY_OUTPUT message=", "Equity output=", outputName);
   }
   Print(gLogIdentity, "event=SYMBOL_SPEC message=", "SPEC currency=", AccountCurrency(), " capital=", AccountBalance(),
         " tick_size=", SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE),
         " min_lot=", MarketInfo(Symbol(), MODE_MINLOT),
         " lot_step=", step, " spread=", MarketInfo(Symbol(), MODE_SPREAD),
         " swap_type=", MarketInfo(Symbol(), MODE_SWAPTYPE),
         " swap_long=", MarketInfo(Symbol(), MODE_SWAPLONG),
         " swap_short=", MarketInfo(Symbol(), MODE_SWAPSHORT));
   Print(gLogIdentity, "event=INIT_OK");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EA終了処理                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(equityFile != INVALID_HANDLE)
   {
      // 最終観測時点の有効証拠金と残高を記録してファイルを閉じる。
      if(lastTick > 0)
         FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                   DoubleToString(AccountEquity(), 2), DoubleToString(AccountBalance(), 2));
      FileClose(equityFile);
   }
   Print(gLogIdentity, "event=DEINIT reason=", reason);
}

//+------------------------------------------------------------------+
//| ティック処理                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   // このティックのサーバー時刻を取得し、売買できない場合も資産の観測値を更新する。
   datetime now = TimeCurrent();
   RecordEquitySnapshot(now);

   // 発注不能な間はシグナル足を消費せず、最初の発注可能なティックを待つ。
   // テスターでは銘柄の売買許可が0を返す場合があるため、実運用時だけ確認する。
   if(!IsTradeAllowed() || (!IsTesting() && MarketInfo(Symbol(), MODE_TRADEALLOWED) == 0))
   {
      return;
   }
   RefreshRates();
   if(Bid <= 0 || Ask <= 0 || Ask < Bid)
   {
      return;
   }
   double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0)
   {
      return;
   }

   // 売買時刻の判定に使うJSTの日付と分を求める。
   int tokyoDate = 0;
   int tokyoMinute = -1;
   bool dstTransitionSunday = false;
   datetime tokyoNow = 0;
   GetTokyoClock(now, tokyoNow, tokyoDate, tokyoMinute, dstTransitionSunday);

   // 成立済みの決済を優先し、SL補正、保有注文の時刻決済の順で処理する。
   // 決済を一度試みたら、同じティックでは再度試みない。
   bool exitAttempted = false;
   RetryPendingExit(exitAttempted);

   CorrectPendingStop(tick);

   datetime bar = iTime(Symbol(), SignalTimeframe, 0);
   bool newBar = (bar > 0 && bar != lastBar);

   if(!ManageOpenOrders(tokyoDate, tokyoMinute, exitAttempted, bar, newBar)) return;

   // 保有注文がない場合だけ、直前の決済確認と新規発注の判定へ進む。
   if(!ResolveLastClosedOrder()) return;

   // 09:55売りと09:50買いはM30境界を待たず判定する。
   bool tokyoSellWindow = (tokyoMinute == 9 * 60 + 55);
   bool tokyoShortBuyWindow = (tokyoMinute == TokyoEntryMinute);
   if(!newBar && !tokyoSellWindow && !tokyoShortBuyWindow) return;
   // 決済履歴を同期し、買いのエントリーに必要な休止期間を確認する。
   if(!PrepareEntryAfterClose(bar, tokyoSellWindow)) return;

   // 対象の銀行営業日か、指定時刻内か、同じ方向で当日発注済みでないかを確認する。
   if(!CheckTokyoEntry(tokyoNow, tokyoDate, tokyoMinute,
                      dstTransitionSunday, tokyoSellWindow)) return;

   // 発注直前の価格・スプレッド・証拠金を確認し、SL付きで注文を送る。
   OpenTokyoPosition(now, tick, tokyoDate, tokyoSellWindow);
}

//+------------------------------------------------------------------+
// 日次の有効証拠金・残高を記録し、最新の観測値を保持する。
//+------------------------------------------------------------------+
void RecordEquitySnapshot(const datetime now)
{
   // サーバー日付が変わったら、直前の日の最後の観測値を記録する。
   if(equityFile != INVALID_HANDLE && lastTick > 0 &&
      (long)now / 86400 != (long)lastTick / 86400)
      FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                DoubleToString(lastEquity, 2), DoubleToString(lastBalance, 2));
   // 翌日の最初のティックで出力できるように、今回の観測値を保持する。
   lastTick = now;
   lastEquity = AccountEquity();
   lastBalance = AccountBalance();
}

//+------------------------------------------------------------------+
// 米国DSTの日付規則でサーバー時刻をJSTへ変換する。
// JSTの時刻・日付・分と、夏時間の切替日かどうかを呼び出し元へ返す。
//+------------------------------------------------------------------+
void GetTokyoClock(const datetime now, datetime &tokyoNow, int &tokyoDate,
                   int &tokyoMinute, bool &dstTransitionSunday)
{
   int serverYear = TimeYear(now);
   datetime marchFirst = StringToTime(IntegerToString(serverYear) + ".03.01 00:00");
   datetime novemberFirst = StringToTime(IntegerToString(serverYear) + ".11.01 00:00");
   // 米国の夏時間は3月第2日曜日に始まり、11月第1日曜日に終わる。
   int marchSunday = 8 + (7 - TimeDayOfWeek(marchFirst)) % 7;
   int novemberSunday = 1 + (7 - TimeDayOfWeek(novemberFirst)) % 7;
   int serverDate = serverYear * 10000 + TimeMonth(now) * 100 + TimeDay(now);
   int marchDate = serverYear * 10000 + 300 + marchSunday;
   int novemberDate = serverYear * 10000 + 1100 + novemberSunday;
   bool summerTime = (serverDate >= marchDate && serverDate < novemberDate);
   dstTransitionSunday = (serverDate == marchDate || serverDate == novemberDate);
   // サーバーが夏UTC+3なら6時間、冬UTC+2なら7時間を加えてJSTにする。
   tokyoNow = now + (summerTime ? 6 : 7) * 3600;
   tokyoDate = TimeYear(tokyoNow) * 10000 + TimeMonth(tokyoNow) * 100 + TimeDay(tokyoNow);
   tokyoMinute = TimeHour(tokyoNow) * 60 + TimeMinute(tokyoNow);
}

//+------------------------------------------------------------------+
// 成立済みの決済を再試行する。試行済みなら同一ティックの再決済を抑止する。
//+------------------------------------------------------------------+
void RetryPendingExit(bool &exitAttempted)
{
   if(exitTicket >= 0)
   {
      int pendingExit = exitTicket;
      if(!OrderSelect(pendingExit, SELECT_BY_TICKET))
         Print(gLogIdentity, "event=EXIT_SELECT_FAILED message=", "Exit OrderSelect failed ticket=", pendingExit, " error=", GetLastError());
      else if(OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC &&
              (OrderType() == OP_BUY || OrderType() == OP_SELL))
      {
         string pendingPrefix = statePrefix + "." + IntegerToString(pendingExit);
         // SLなどですでに決済されていれば、決済待ちとSL補正待ちを解除する。
         if(OrderCloseTime() > 0)
         {
            lastClose = OrderCloseTime();
            exitTicket = -1;
            if(stopTicket == pendingExit) stopTicket = -1;
            if(!IsTesting())
            {
               GlobalVariableSet(statePrefix + ".close", lastClose);
               GlobalVariableSet(pendingPrefix + ".closed", lastClose);
               GlobalVariableDel(pendingPrefix + ".exit");
               GlobalVariableDel(pendingPrefix + ".stop");
               GlobalVariablesFlush();
            }
         }
         else
         {
            // 決済が成立しなくても、今回のティックでは試行済みとして扱う。
            // 決済待ちのチケットを残しておくことで、後続ティックで再試行できる。
            exitAttempted = true;
            int pendingSide = OrderType();
            double pendingPrice = (pendingSide == OP_BUY ? Bid : Ask);
            double pendingFreeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
            // 既存SLが凍結範囲内にある間は決済を保留する。
            if(pendingFreeze <= 0 || OrderStopLoss() <= 0 ||
               MathAbs(pendingPrice - OrderStopLoss()) > pendingFreeze)
            {
               if(OrderClose(pendingExit, OrderLots(), pendingPrice, Slippage, clrNONE))
               {
                  lastClose = TimeCurrent();
                  exitTicket = -1;
                  if(stopTicket == pendingExit) stopTicket = -1;
                  if(!IsTesting())
                  {
                     GlobalVariableSet(statePrefix + ".close", lastClose);
                     GlobalVariableSet(pendingPrefix + ".closed", lastClose);
                     GlobalVariableDel(pendingPrefix + ".exit");
                     GlobalVariableDel(pendingPrefix + ".stop");
                     GlobalVariablesFlush();
                  }
               }
               else Print(gLogIdentity, "event=EXIT_FAILED message=", "Exit failed ticket=", pendingExit, " error=", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// 約定価格を基準に、未完了の初期SL補正を再試行する。
// 制約やエラーで補正できなければ、既存SLと補正待ちの状態を保持する。
//+------------------------------------------------------------------+
void CorrectPendingStop(const double tick)
{
   // スリッページがあれば、約定価格を基準に初期SLを補正する。既存SLは外さない。
   if(stopTicket >= 0)
   {
      if(!OrderSelect(stopTicket, SELECT_BY_TICKET))
         Print(gLogIdentity, "event=SL_SELECT_FAILED message=", "SL OrderSelect failed error=", GetLastError());
      else
      {
         int pendingStop = stopTicket;
         string stopPrefix = statePrefix + "." + IntegerToString(pendingStop);
         if(OrderCloseTime() > 0)
         {
            lastClose = OrderCloseTime();
            stopTicket = -1;
            if(!IsTesting())
            {
               GlobalVariableSet(statePrefix + ".close", lastClose);
               GlobalVariableSet(stopPrefix + ".closed", lastClose);
               GlobalVariableDel(stopPrefix + ".stop");
               GlobalVariablesFlush();
            }
         }
         else if(OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC &&
                 (OrderType() == OP_BUY || OrderType() == OP_SELL))
         {
            // 発注時に保存したATR幅を使い、約定価格からSLを計算し直す。
            // 買いは下側、売りは上側の有効な価格刻みへ丸める。
            double target = OrderOpenPrice() + (OrderType() == OP_BUY ? -1.0 : 1.0) * stopDistance;
            stopTarget = NormalizeDouble((OrderType() == OP_BUY ? MathFloor(target / tick) : MathCeil(target / tick)) * tick,
                                         Digits);
            // すでに目標のSLになっていれば、補正完了として保存状態を消す。
            if(MathAbs(OrderStopLoss() - stopTarget) < tick / 2)
            {
               stopTicket = -1;
               splitStopDistance = 0;
               if(!IsTesting())
               {
                  GlobalVariableDel(stopPrefix + ".stop");
                  GlobalVariableDel(statePrefix + ".sstop." + IntegerToString(splitStopDate));
                  GlobalVariablesFlush();
               }
            }
            else
            {
               double market = (OrderType() == OP_BUY ? Bid : Ask);
               double distance = (OrderType() == OP_BUY ? market - stopTarget : stopTarget - market);
               double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
               if(distance >= MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick && distance > freeze)
               {
                  if(OrderModify(pendingStop, OrderOpenPrice(), stopTarget,
                                 OrderTakeProfit(), 0, clrNONE))
                  {
                     stopTicket = -1;
                     splitStopDistance = 0;
                     if(!IsTesting())
                     {
                        GlobalVariableDel(stopPrefix + ".stop");
                        GlobalVariableDel(statePrefix + ".sstop." + IntegerToString(splitStopDate));
                        GlobalVariablesFlush();
                     }
                  }
                  else Print(gLogIdentity, "event=SL_MODIFY_FAILED message=", "SL correction failed ticket=", pendingStop, " error=", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// 保有注文を照合して時刻決済を行う。新規発注へ進める場合だけtrueを返す。
// 注文を見つけたティックでは、決済が成功してもfalseを返して新規発注を止める。
//+------------------------------------------------------------------+
bool ManageOpenOrders(const int tokyoDate, const int tokyoMinute,
                      bool exitAttempted, const datetime bar, const bool newBar)
{
   // 同一銘柄・Magicの注文を照合し、JSTの決済時刻を判定する。
   bool occupied = false;
   bool orderScanOk = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         Print(gLogIdentity, "event=ORDER_SELECT_FAILED message=", "OrderSelect failed error=", GetLastError());
         orderScanOk = false;
         continue;
      }
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC) continue;
      // 待機注文を含め、同じ銘柄・Magicの注文があれば新規発注を止める。
      occupied = true;
      int side = OrderType();
      if(side != OP_BUY && side != OP_SELL) continue;
      int activeTicket = OrderTicket();
      heldTicket = activeTicket;
      string activePrefix = statePrefix + "." + IntegerToString(activeTicket);
      if(!IsTesting())
      {
         GlobalVariableSet(statePrefix + ".held", activeTicket);
         if(GlobalVariableCheck(activePrefix + ".exit")) exitTicket = activeTicket;
      }

      int openTokyoDate = 0;
      {
         // 約定時点の夏時間を使って約定日をJSTへ変換する。
         // 買いは09:55、売りは最終決済時刻、持ち越しは翌日以降に決済する。
         datetime openTime = OrderOpenTime();
         int openYear = TimeYear(openTime);
         datetime openMarchFirst = StringToTime(IntegerToString(openYear) + ".03.01 00:00");
         datetime openNovemberFirst = StringToTime(IntegerToString(openYear) + ".11.01 00:00");
         int openMarchSunday = 8 + (7 - TimeDayOfWeek(openMarchFirst)) % 7;
         int openNovemberSunday = 1 + (7 - TimeDayOfWeek(openNovemberFirst)) % 7;
         int openServerDate = openYear * 10000 + TimeMonth(openTime) * 100 + TimeDay(openTime);
         int openMarchDate = openYear * 10000 + 300 + openMarchSunday;
         int openNovemberDate = openYear * 10000 + 1100 + openNovemberSunday;
         bool openSummerTime = (openServerDate >= openMarchDate && openServerDate < openNovemberDate);
         datetime openTokyoTime = openTime + (openSummerTime ? 6 : 7) * 3600;
         openTokyoDate = TimeYear(openTokyoTime) * 10000 +
                         TimeMonth(openTokyoTime) * 100 + TimeDay(openTokyoTime);
         int tokyoCloseMinute = (side == OP_BUY ? 9 * 60 + 55 : SellFinalMinute);
         if(tokyoDate > openTokyoDate || tokyoMinute >= tokyoCloseMinute)
         {
            // 先に決済意思を保存する。発注失敗や再起動があっても再試行できる。
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print(gLogIdentity, "event=EXIT_STATE_SAVE_FAILED message=", "Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      // 部分決済でticketが変わっても、残余へ発注時のSL補正幅を引き継ぐ。
      string splitStopKey = statePrefix + ".sstop." + IntegerToString(openTokyoDate);
      if(side == OP_SELL)
      {
         if(!IsTesting() && GlobalVariableCheck(splitStopKey))
         {
            splitStopDate = openTokyoDate;
            splitStopDistance = GlobalVariableGet(splitStopKey);
         }
         if(splitStopDate == openTokyoDate && splitStopDistance > 0)
         {
            stopTicket = activeTicket;
            stopDistance = splitStopDistance;
         }
      }
      // 売りは10:00以降に一度だけ分割し、残りを最終時刻まで保有する。
      // 全量決済を優先し、初期SL補正待ちでも時刻による分割決済を行う。
      if(side == OP_SELL && SellFinalMinute > TokyoExitMinute &&
         tokyoDate == openTokyoDate && tokyoMinute >= TokyoExitMinute &&
         tokyoMinute < SellFinalMinute && exitTicket != activeTicket)
      {
         double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
         double minLot = MarketInfo(Symbol(), MODE_MINLOT);
         double actualLots = OrderLots();
         double lotTolerance = MathMax(lotStep * 1e-7, 1e-9);
         // 設定値ではなく、最初の部分決済要求前の実数量と比較する。
         string partialBaseKey = statePrefix + ".split." + IntegerToString(openTokyoDate);
         if(partialBaseDate != openTokyoDate)
         {
            partialBaseDate = openTokyoDate;
            partialBaseLots = actualLots;
            if(!IsTesting() && GlobalVariableCheck(partialBaseKey))
               partialBaseLots = GlobalVariableGet(partialBaseKey);
         }
         if(actualLots < partialBaseLots - lotTolerance &&
            lastTokyoSellPartialDate != openTokyoDate)
         {
            lastTokyoSellPartialDate = openTokyoDate;
            if(!IsTesting())
            {
               GlobalVariableSet(statePrefix + ".sellpartial", lastTokyoSellPartialDate);
               GlobalVariablesFlush();
            }
         }
         if(lastTokyoSellPartialDate != openTokyoDate)
         {
            double firstLots = (lotStep > 0 ?
                                NormalizeDouble(MathFloor(actualLots * SellFirstClosePercent /
                                                         100.0 / lotStep + 1e-9) * lotStep, 8) : 0);
            double remainingLots = NormalizeDouble(actualLots - firstLots, 8);
            bool validSplit = (lotStep > 0 && firstLots >= minLot && remainingLots >= minLot &&
                               MathAbs(firstLots / lotStep - MathRound(firstLots / lotStep)) <= 1e-7 &&
                               MathAbs(remainingLots / lotStep - MathRound(remainingLots / lotStep)) <= 1e-7);
            if(!validSplit)
            {
               // 運用中に数量条件が変わり分割不能なら、10:00以降は全量決済へ切り替える。
               exitTicket = activeTicket;
               if(!IsTesting())
               {
                  if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                     Print(gLogIdentity, "event=EXIT_STATE_SAVE_FAILED message=", "Exit state save failed ticket=", activeTicket,
                           " error=", GetLastError());
                  GlobalVariablesFlush();
               }
            }
            else
            {
               RefreshRates();
               double partialPrice = Ask;
               double partialFreeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
               if(partialFreeze <= 0 || OrderStopLoss() <= 0 ||
                  MathAbs(partialPrice - OrderStopLoss()) > partialFreeze)
               {
                  // 数量と補正幅を先に保存し、約定直後の再起動にも備える。
                  if(stopTicket == activeTicket)
                  {
                     splitStopDate = openTokyoDate;
                     splitStopDistance = stopDistance;
                  }
                  if(!IsTesting())
                  {
                     if(GlobalVariableSet(partialBaseKey, partialBaseLots) == 0 ||
                        (splitStopDate == openTokyoDate && splitStopDistance > 0 &&
                         GlobalVariableSet(splitStopKey, splitStopDistance) == 0))
                     {
                        Print(gLogIdentity, "event=PARTIAL_STATE_SAVE_FAILED message=", "Partial state save failed ticket=", activeTicket,
                              " error=", GetLastError());
                        continue;
                     }
                     GlobalVariablesFlush();
                  }
                  RefreshRates();
                  partialPrice = Ask;
                  if(OrderClose(activeTicket, firstLots, partialPrice, Slippage, clrNONE))
                  {
                     lastTokyoSellPartialDate = openTokyoDate;
                     if(!IsTesting())
                     {
                        GlobalVariableSet(statePrefix + ".sellpartial", lastTokyoSellPartialDate);
                        GlobalVariablesFlush();
                     }
                     continue;
                  }
                  else Print(gLogIdentity, "event=PARTIAL_EXIT_FAILED message=", "Partial exit failed ticket=", activeTicket,
                             " lots=", DoubleToString(firstLots, 8),
                             " error=", GetLastError());
               }
               continue;
            }
         }
      }
      // 買いは指定ATR幅の含み益に達したら、約定水準へSLを前進させる。
      if(side == OP_BUY && BuyBreakEvenATR > 0 &&
         exitTicket != activeTicket && stopTicket != activeTicket)
      {
         double breakEvenAtrValue = iATR(Symbol(), SignalTimeframe, ATRPeriod, 2);
         double breakEvenTick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
         RefreshRates();
         double breakEvenMarket = Bid;
         double breakEvenFavorable = breakEvenMarket - OrderOpenPrice();
         if(breakEvenAtrValue > 0 && breakEvenTick > 0 &&
            breakEvenFavorable >= BuyBreakEvenATR * breakEvenAtrValue)
         {
            // 刻み上の約定値が浮動小数誤差で余分に1tick外側へ丸められるのを防ぐ。
            double breakEvenStop = NormalizeDouble(MathFloor(OrderOpenPrice() /
                                                              breakEvenTick + 1e-9) * breakEvenTick,
                                                    Digits);
            double breakEvenGap = breakEvenMarket - breakEvenStop;
            double breakEvenFreeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
            bool breakEvenImproves = (OrderStopLoss() <= 0 ||
                                      breakEvenStop > OrderStopLoss() + breakEvenTick / 2);
            if(breakEvenImproves && breakEvenStop > 0 &&
               breakEvenGap >= MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + breakEvenTick &&
               breakEvenGap > breakEvenFreeze &&
               (breakEvenFreeze <= 0 || OrderStopLoss() <= 0 ||
                MathAbs(breakEvenMarket - OrderStopLoss()) > breakEvenFreeze))
            {
               if(OrderModify(activeTicket, OrderOpenPrice(), breakEvenStop,
                              OrderTakeProfit(), 0, clrNONE))
                  continue;
               Print(gLogIdentity, "event=BREAK_EVEN_FAILED message=", "Break-even SL failed ticket=", activeTicket,
                     " error=", GetLastError());
            }
         }
      }
      // 時刻決済と初期SL補正を優先し、利益が伸びた建玉だけのSLを追随させる。
      if(exitTicket != activeTicket && stopTicket != activeTicket && TrailATR > 0)
      {
         double trailAtr = iATR(Symbol(), SignalTimeframe, ATRPeriod, 2);
         double trailDistance = TrailATR * trailAtr;
         double trailTick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
         RefreshRates();
         double trailMarket = (side == OP_BUY ? Bid : Ask);
         double favorable = (side == OP_BUY ? trailMarket - OrderOpenPrice() :
                                             OrderOpenPrice() - trailMarket);
         if(trailDistance > 0 && trailTick > 0 && favorable >= trailDistance)
         {
            double trailTarget = trailMarket + (side == OP_BUY ? -1.0 : 1.0) * trailDistance;
            double trailStop = NormalizeDouble((side == OP_BUY ? MathFloor(trailTarget / trailTick) :
                                                                  MathCeil(trailTarget / trailTick)) * trailTick,
                                                Digits);
            double trailGap = (side == OP_BUY ? trailMarket - trailStop : trailStop - trailMarket);
            double trailFreeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
            bool improves = (OrderStopLoss() <= 0 ||
                             (side == OP_BUY && trailStop > OrderStopLoss() + trailTick / 2) ||
                             (side == OP_SELL && trailStop < OrderStopLoss() - trailTick / 2));
            if(improves && trailStop > 0 &&
               trailGap >= MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + trailTick &&
               trailGap > trailFreeze &&
               (trailFreeze <= 0 || OrderStopLoss() <= 0 ||
                MathAbs(trailMarket - OrderStopLoss()) > trailFreeze))
            {
               if(!OrderModify(activeTicket, OrderOpenPrice(), trailStop,
                               OrderTakeProfit(), 0, clrNONE))
                  Print(gLogIdentity, "event=TRAIL_MODIFY_FAILED message=", "Trailing SL failed ticket=", activeTicket, " error=", GetLastError());
            }
         }
      }
      if(exitTicket != activeTicket || exitAttempted) continue;
      exitAttempted = true;
      RefreshRates();
      double price = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      if(freeze > 0 && OrderStopLoss() > 0 && MathAbs(price - OrderStopLoss()) <= freeze) continue;
      if(OrderClose(activeTicket, OrderLots(), price, Slippage, clrNONE))
      {
         lastClose = TimeCurrent();
         exitTicket = -1;
         if(stopTicket == activeTicket) stopTicket = -1;
         if(!IsTesting())
         {
            GlobalVariableSet(statePrefix + ".close", lastClose);
            GlobalVariableSet(activePrefix + ".closed", lastClose);
            GlobalVariableDel(activePrefix + ".exit");
            GlobalVariableDel(activePrefix + ".stop");
            GlobalVariablesFlush();
         }
      }
      else Print(gLogIdentity, "event=EXIT_FAILED message=", "Exit failed ticket=", activeTicket, " error=", GetLastError());
   }
   // 照合に失敗した場合は、注文がないと断定せず新規発注を見送る。
   if(!orderScanOk) return false;
   if(occupied)
   {
      if(newBar) lastBar = bar;
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// 最後に保有していた注文の決済を確認し、確認できた場合はtrueを返す。
// 保存済みの決済時刻を優先し、なければチケットから履歴を確認する。
//+------------------------------------------------------------------+
bool ResolveLastClosedOrder()
{
   // 最後に保有していたticketが消えた場合、決済時刻を取得できるまで新規発注しない。
   if(heldTicket >= 0)
   {
      string heldPrefix = statePrefix + "." + IntegerToString(heldTicket);
      bool heldResolved = false;
      if(!IsTesting() && GlobalVariableCheck(heldPrefix + ".closed"))
      {
         datetime savedClose = (datetime)GlobalVariableGet(heldPrefix + ".closed");
         if(savedClose > lastClose) lastClose = savedClose;
         heldResolved = true;
      }
      else if(OrderSelect(heldTicket, SELECT_BY_TICKET) && OrderCloseTime() > 0 &&
              OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC)
      {
         if(OrderCloseTime() > lastClose) lastClose = OrderCloseTime();
         heldResolved = true;
         if(!IsTesting())
         {
            GlobalVariableSet(statePrefix + ".close", lastClose);
            GlobalVariableSet(heldPrefix + ".closed", lastClose);
            GlobalVariableDel(heldPrefix + ".exit");
            GlobalVariableDel(heldPrefix + ".stop");
            GlobalVariablesFlush();
         }
      }
      // 注文一覧から消えただけでは決済済みと扱わず、確認できるまで待つ。
      if(!heldResolved)
      {
         Print(gLogIdentity, "event=HELD_TICKET_UNRESOLVED message=", "Last held ticket unresolved; entry suspended ticket=", heldTicket,
               " error=", GetLastError());
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
// 最終決済時刻を同期し、新規判定のバー状態と決済後休止を処理する。
// 履歴を確認できない場合や必要な休止期間が不足する場合はfalseを返す。
//+------------------------------------------------------------------+
bool PrepareEntryAfterClose(const datetime bar, const bool tokyoSellWindow)
{
   // SL・手動決済も含め、履歴の並び順に依存せず最終決済時刻を取得する。
   for(int h = OrdersHistoryTotal() - 1; h >= 0; h--)
   {
      if(!OrderSelect(h, SELECT_BY_POS, MODE_HISTORY))
      {
         Print(gLogIdentity, "event=HISTORY_SELECT_FAILED message=", "History OrderSelect failed error=", GetLastError());
         return false;
      }
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MAGIC &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) && OrderCloseTime() > lastClose)
         lastClose = OrderCloseTime();
   }
   if(!IsTesting() && lastClose > 0)
   {
      GlobalVariableSet(statePrefix + ".close", lastClose);
      GlobalVariablesFlush();
   }
   // 履歴の確認後に判定済みバーを更新し、残っていた決済待ちを解除する。
   lastBar = bar;
   exitTicket = -1;

   // 後半売りは、同日09:55に完了した前半決済の休止と同バー制限を適用しない。
   if(lastClose > 0 && !tokyoSellWindow)
   {
      int closeShift = iBarShift(Symbol(), SignalTimeframe, lastClose, false);
      if(closeShift <= 0)
      {
         return false;
      }
      // 決済した足と現在足を除き、完了した平日の足だけを数える。
      int days = 0;
      for(int d = closeShift - 1; d >= 1 && days < CooldownDays; d--)
      {
         int weekday = TimeDayOfWeek(iTime(Symbol(), SignalTimeframe, d));
         if(weekday >= 1 && weekday <= 5) days++;
      }
      if(days < CooldownDays)
      {
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
// 営業日・指定時刻を確認し、同日の同方向への重複発注を防ぐ。
// 発注可能な場合はtrueを返す。履歴で当日の発注を見つけた場合は記録も更新する。
//+------------------------------------------------------------------+
bool CheckTokyoEntry(const datetime tokyoNow, const int tokyoDate,
                     const int tokyoMinute, const bool dstTransitionSunday,
                     const bool tokyoSellWindow)
{
   int tokyoYear = TimeYear(tokyoNow);
   int tokyoMonth = TimeMonth(tokyoNow);
   int tokyoDay = TimeDay(tokyoNow);
   int tokyoWeekday = TimeDayOfWeek(tokyoNow);
   bool tokyoEntryWindow = (tokyoMinute == TokyoEntryMinute || tokyoSellWindow);
   // 祝日表の対象年、銀行の休業日、指定分内かどうかを確認する。
   if(tokyoYear < 2021 || tokyoYear > 2028 || dstTransitionSunday ||
      tokyoWeekday == 0 || tokyoWeekday == 6 ||
      (tokyoMonth == 12 && tokyoDay == 31) ||
      (tokyoMonth == 1 && tokyoDay <= 3) ||
      StringFind(tokyoHolidays, "," + IntegerToString(tokyoDate) + ",") >= 0 ||
      !tokyoEntryWindow)
      return false;
   if(SettlementDaysOnly == 1 && tokyoDay % 5 != 0)
   {
      // 同月内に後続の銀行営業日があれば、今日は月末最終営業日ではない。
      for(datetime nextDay = tokyoNow + 86400; TimeMonth(nextDay) == tokyoMonth; nextDay += 86400)
      {
         int nextWeekday = TimeDayOfWeek(nextDay);
         int nextDate = TimeYear(nextDay) * 10000 + TimeMonth(nextDay) * 100 + TimeDay(nextDay);
         if(nextWeekday != 0 && nextWeekday != 6 &&
            !(TimeMonth(nextDay) == 12 && TimeDay(nextDay) == 31) &&
            !(TimeMonth(nextDay) == 1 && TimeDay(nextDay) <= 3) &&
            StringFind(tokyoHolidays, "," + IntegerToString(nextDate) + ",") < 0)
            return false;
      }
   }
   // 買いと売りを別々に確認するため、買いが未約定でも09:55の売りは判定する。
   bool tokyoSellLeg = tokyoSellWindow;
   int lastTokyoLegDate = (tokyoSellLeg ?
                           lastTokyoSellDate : lastTokyoEntryDate);
   // 再起動後も重複発注しないように、メモリ上の記録に加えて履歴を確認する。
   if(lastTokyoLegDate != tokyoDate)
   {
      for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
      {
         if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
         {
            Print(gLogIdentity, "event=TOKYO_HISTORY_SELECT_FAILED message=", "Tokyo history OrderSelect failed error=", GetLastError());
            return false;
         }
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MAGIC) continue;
         if(OrderType() != (tokyoSellLeg ? OP_SELL : OP_BUY)) continue;
         datetime historyOpen = OrderOpenTime();
         int historyYear = TimeYear(historyOpen);
         datetime historyMarchFirst = StringToTime(IntegerToString(historyYear) + ".03.01 00:00");
         datetime historyNovemberFirst = StringToTime(IntegerToString(historyYear) + ".11.01 00:00");
         int historyMarchSunday = 8 + (7 - TimeDayOfWeek(historyMarchFirst)) % 7;
         int historyNovemberSunday = 1 + (7 - TimeDayOfWeek(historyNovemberFirst)) % 7;
         int historyServerDate = historyYear * 10000 +
                                 TimeMonth(historyOpen) * 100 + TimeDay(historyOpen);
         int historyMarchDate = historyYear * 10000 + 300 + historyMarchSunday;
         int historyNovemberDate = historyYear * 10000 + 1100 + historyNovemberSunday;
         bool historySummerTime = (historyServerDate >= historyMarchDate &&
                                   historyServerDate < historyNovemberDate);
         datetime historyTokyoTime = historyOpen + (historySummerTime ? 6 : 7) * 3600;
         int historyTokyoDate = TimeYear(historyTokyoTime) * 10000 +
                                TimeMonth(historyTokyoTime) * 100 + TimeDay(historyTokyoTime);
         if(historyTokyoDate == tokyoDate)
         {
            if(tokyoSellLeg)
               lastTokyoSellDate = tokyoDate;
            else
               lastTokyoEntryDate = tokyoDate;
            break;
         }
      }
   }
   if((tokyoSellLeg ? lastTokyoSellDate : lastTokyoEntryDate) == tokyoDate)
      return false;
   return true;
}

//+------------------------------------------------------------------+
// 執行条件を確認して発注し、約定状態の保存と初期SL補正を行う。
//+------------------------------------------------------------------+
void OpenTokyoPosition(const datetime now, const double tick,
                       const int tokyoDate, const bool tokyoSellWindow)
{
   // 成否不明・恒久エラーの同日同方向再送を止め、一時エラーの連発を抑える。
   if((tokyoSellWindow ? blockedSellDate : blockedBuyDate) == tokyoDate ||
      TimeCurrent() < nextEntryAttempt) return;
   // 指定分内でスプレッドを再判定する。
   RefreshRates();
   long bidPoints = (long)MathRound(Bid / Point);
   long askPoints = (long)MathRound(Ask / Point);
   long spreadPoints = askPoints - bidPoints;
   double pointsPerPip = (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
   // 端数pointは許容せず、入力上限を整数pointへ切り捨てる。
   long maxSpreadPoints = (long)MathFloor(MaxSpreadPips * pointsPerPip + 1e-9);
   if(spreadPoints > maxSpreadPoints) return;
   // SL幅にはシグナル時間足のシフト2のATRを使い、形成中の足を含めない。
   if(iBars(Symbol(), SignalTimeframe) < ATRPeriod + 3) return;
   double atr = iATR(Symbol(), SignalTimeframe, ATRPeriod, 2);
   if(atr <= 0) return;
   int side = (tokyoSellWindow ? OP_SELL : OP_BUY);

   // 固定ロット・ATR幅のSLで発注する。ストップ制約を満たせない場合は見送る。
   double entry = (side == OP_BUY ? Ask : Bid);
   double stop = entry + (side == OP_BUY ? -1.0 : 1.0) * StopATR * atr;
   stop = NormalizeDouble((side == OP_BUY ? MathFloor(stop / tick) : MathCeil(stop / tick)) * tick,
                          Digits);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick;
   if(stop <= 0 || (side == OP_BUY && Bid - stop < minDistance) ||
      (side == OP_SELL && stop - Ask < minDistance)) return;
   // 必要証拠金を確認する前に、以前の処理で残ったエラーを消しておく。
   ResetLastError();
   double freeAfter = AccountFreeMarginCheck(Symbol(), side, FixedLots);
   if(GetLastError() != 0 || freeAfter <= 0)
   {
      Print(gLogIdentity, "event=ENTRY_MARGIN_REJECTED message=", "Entry skipped: insufficient margin for FixedLots=", FixedLots);
      return;
   }
   // 処理中に指定分を過ぎた場合も、遅刻発注は行わない。
   if(TimeCurrent() >= now - TimeSeconds(now) + 60) return;
   // 送信前に保留を永続化する。成否不明や送信中の再起動では再送しない。
   string blockKey = statePrefix + (side == OP_SELL ? ".sellblock" : ".buyblock");
   if(side == OP_SELL) blockedSellDate = tokyoDate;
   else blockedBuyDate = tokyoDate;
   if(!IsTesting())
   {
      if(GlobalVariableSet(blockKey, tokyoDate) == 0)
      {
         Print(gLogIdentity, "event=ENTRY_STATE_SAVE_FAILED message=", "Entry state save failed; entry suspended error=", GetLastError());
         return;
      }
      GlobalVariablesFlush();
   }
   if(TimeCurrent() >= now - TimeSeconds(now) + 60) return;
   int ticket = OrderSend(Symbol(), side, FixedLots, entry, Slippage, stop, 0,
                          COMMENT, MAGIC, 0, clrNONE);
   if(ticket < 0)
   {
      int error = GetLastError();
      Print(gLogIdentity, "event=ENTRY_FAILED message=", "Entry failed error=", error);
      // 未約定が明確な一時エラーだけ、1秒後以降のティックで再試行する。
      // 128(timeout)等の成否不明と恒久エラーは、当日の同方向を保留したままにする。
      if(error == 4 || error == 8 || error == 129 || error == 135 ||
         error == 136 || error == 137 || error == 138 || error == 141 || error == 146)
      {
         nextEntryAttempt = TimeCurrent() + 1;
         if(!IsTesting())
         {
            if(GlobalVariableSet(statePrefix + ".retry", nextEntryAttempt) == 0 ||
               !GlobalVariableDel(blockKey))
            {
               Print(gLogIdentity, "event=ENTRY_RETRY_STATE_FAILED message=", "Entry retry state failed; entry suspended error=", GetLastError());
               return;
            }
            GlobalVariablesFlush();
         }
         if(side == OP_SELL) blockedSellDate = 0;
         else blockedBuyDate = 0;
      }
      return;
   }
   // 発注成功後にだけ、保有チケット、固定SL幅、当日の売買実績を更新する。
   stopTicket = ticket;
   stopDistance = StopATR * atr;
   heldTicket = ticket;
   if(side == OP_SELL)
      lastTokyoSellDate = tokyoDate;
   else
      lastTokyoEntryDate = tokyoDate;
   if(!IsTesting())
   {
      // 実運用では端末にも保存し、再初期化後に保有状態とSL補正を復元できるようにする。
      string sentPrefix = statePrefix + "." + IntegerToString(ticket);
      GlobalVariableSet(statePrefix + ".held", ticket);
      if(side == OP_SELL)
         GlobalVariableSet(statePrefix + ".tokyosell", lastTokyoSellDate);
      else
         GlobalVariableSet(statePrefix + ".tokyo", lastTokyoEntryDate);
      if(GlobalVariableSet(sentPrefix + ".stop", stopDistance) == 0)
         Print(gLogIdentity, "event=SL_STATE_SAVE_FAILED message=", "SL state save failed ticket=", ticket, " error=", GetLastError());
      GlobalVariablesFlush();
   }
   // 約定価格を取得する。失敗しても補正待ちの状態は残し、後続ティックで扱う。
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print(gLogIdentity, "event=FILL_SELECT_FAILED message=", "Fill OrderSelect failed ticket=", ticket, " error=", GetLastError());
      return;
   }
   double target = OrderOpenPrice() + (side == OP_BUY ? -1.0 : 1.0) * stopDistance;
   stopTarget = NormalizeDouble((side == OP_BUY ? MathFloor(target / tick) : MathCeil(target / tick)) * tick,
                                Digits);
   // 約定直後に補正を試み、制約や失敗で未完了なら後続ティックへ引き継ぐ。
   if(OrderCloseTime() > 0 || MathAbs(OrderStopLoss() - stopTarget) < tick / 2)
   {
      stopTicket = -1;
      if(!IsTesting())
      {
         GlobalVariableDel(statePrefix + "." + IntegerToString(ticket) + ".stop");
         GlobalVariablesFlush();
      }
   }
   else
   {
      RefreshRates();
      double market = (side == OP_BUY ? Bid : Ask);
      double distance = (side == OP_BUY ? market - stopTarget : stopTarget - market);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      if(distance >= MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick &&
         distance > freeze)
      {
         if(OrderModify(ticket, OrderOpenPrice(), stopTarget,
                        OrderTakeProfit(), 0, clrNONE))
         {
            stopTicket = -1;
            if(!IsTesting())
            {
               GlobalVariableDel(statePrefix + "." + IntegerToString(ticket) + ".stop");
               GlobalVariablesFlush();
            }
         }
         else Print(gLogIdentity, "event=SL_MODIFY_FAILED message=", "SL correction failed ticket=", ticket, " error=", GetLastError());
      }
   }
}
