//+------------------------------------------------------------------+
//|                                                        STR03.mq4 |
//|                  決済需要日限定・東京仲値前後売買EA             |
//+------------------------------------------------------------------+

/*
運用対象（2026-09-23選定）
- USDJPY/M30、StrategyMode5、SettlementDaysOnly1。
- 日本銀行営業日の5の倍数日または月末最終営業日。休日の前倒しなし。
- JST09:50買い、09:55決済後に売り、10:00決済。ATR20shift2の2倍を固定SLとする。
- FXTFの冬UTC+2/夏UTC+3（米国DST）を想定。祝日対応は2017～2027年。
- ロットは既定0.1、他EAと異なる正のMagicNumberを使用する。同一EAの重複装着はしない。
- 過去の比較分岐と入力名は再現互換性のため保持するが、専用プロファイル以外は起動しない。
- 売買成績の保証・旧OOS最低PF目標の達成を意味しない。

売買ロジック
- エントリー:
  StrategyMode=0は、
  シグナル時間足の確定終値（シフト1）が、シフト2からEntryBars本の最高値にBreakoutBufferATR倍の
  ATRを加えた値より上なら買い、最安値から同幅を引いた値より下なら売る。
  ATRもシグナル足を除き、シフト2のATRPeriod期間で計算する。
  Mode0でBreakoutTiming=1なら、シフト1からのチャネルとATRを現在足ごとに固定し、現在Bidで判定する。
  TrendMAPeriodが2以上なら、確定終値が同時間足EMAより上の買い・下の売りだけを許可する。
  MinSignalRangeATRが正なら、確定シグナル足の高安幅が事前ATRの指定倍率以上の場合だけ許可する。
  StrategyMode=1は、同じチャネルを一時的に上抜けて内側で確定したら売り、
  一時的に下抜けて内側で確定したら買う。上下両方を抜けた足は見送る。
  Mode1のMinPathEfficiencyが正なら、事前EntryBars本の終値変化/TR合計が下限以上の場合だけ許可する。
  Mode1の新規発注は、現在のシグナル時間足バーの開始時刻がEntryStartHour以降の場合だけ許可する。
  時間帯制限は建玉管理や決済には適用しない。時刻はブローカー時刻、0なら終日許可。
  StrategyMode=2は、確定終値がEMAより上でRSI(2)が下限以下なら買い、
  EMAより下でRSI(2)が100-下限以上なら売る。短期平均への押し目・戻りを狙う。
  StrategyMode=3は、営業日のTokyoEntryMinuteにUSDJPYを買い、同日JST09:55以後に決済する。
  StrategyMode=4は、営業日のJST09:55分内にUSDJPYを売り、TokyoExitMinute以後に決済する。
  StrategyMode=5は、営業日のTokyoEntryMinuteに買って09:55に決済し、その決済後に売ってTokyoExitMinuteに決済する。
  Mode5は08:00買い/11:30～12:30決済、または09:50買い/10:00決済の固定ペアを許可する。
  SettlementDaysOnly=1は後者を5の倍数日・月末最終銀行営業日に限定する。休日の前倒しは行わない。
  前半買いの未約定・SL・損益によらず後半売りを判定するが、買いが残っている間は売らない。
  StrategyMode=6は、確定終値がシフト2のEntryBars期間SMAからDeviationATR倍の事前ATR以上
  乖離した場合に、SMAへの回帰方向へ売買する。
  StrategyMode=7は、England and Wales銀行営業日のLondon16:05分内にEURUSDを買う。
  StrategyMode=8は、同じ銀行営業日のFXTFサーバー14:45分内にEURUSDを売る。
  StrategyMode=9は、同じ銀行営業日のFXTFサーバー15:00分内にEURUSDを買う。
  StrategyMode=10は、2017～2027年の全平日London07:00分内にEURUSDを売る。
  StrategyMode=11は、USDJPYの確定M30足が0.50円格子を一つだけ越えた方向へ売買する。
  StrategyMode=12は、USDJPYの連続ティックが0.50円格子を一つだけ越えた方向へ売買する。
  StrategyMode=13は、USDJPYの連続ティックが1.00円格子へ到達した時に逆方向へ売買する。
  StrategyMode=14は、EURUSDの前NY17:00からLondon07:00までのH1レンジを現在Bidで突破した方向へ売買する。
  Mode4/5の09:55売りとMode5の09:50買いは、M30確定を待たず指定分内で判定する。
  FXTFサーバー時刻は米国夏時間の日付規則からJSTへ変換し、日本の休場日は新規発注しない。
  シグナル時間足確定後の最初の発注可能なティックで判定し、MaxSpreadPips超過なら当該足のシグナルを見送る。
- エグジット:
  StrategyMode=0でTrailATR=0の場合、買いは確定終値がシフト2からExitBars本の最安値を
  下回ったら全量決済し、売りは確定終値が同期間の最高値を上回ったら全量決済する。
  TrailATRが正なら、約定足以後の最高値・最安値から固定事前ATR幅を戻した確定終値で決済する。
  StrategyMode=1/2/6は、約定バーを1本目としてEntryBars本が終了したら全量決済する。
  StrategyMode=3は、JST09:55以後または約定日の翌日以後の最初の約定可能ティックで決済する。
  StrategyMode=4は、JSTのTokyoExitMinute以後または約定日の翌日以後に決済する。
  StrategyMode=5は、買いをJST09:55、売りをTokyoExitMinute以後または翌日以後に決済する。
  StrategyMode=7は、FXTFの週末閉場前となるサーバー23:45以後または翌サーバー日以後に決済する。
  StrategyMode=8は、FXTFサーバー15:00以後または翌サーバー日以後に決済する。
  StrategyMode=9は、FXTFサーバー15:15以後または翌サーバー日以後に決済する。
  StrategyMode=10は、FXTFサーバー15:00以後または翌サーバー日以後に決済する。
  StrategyMode=11は、約定から1時間後、サーバー23:00以後、または翌サーバー日以後に決済する。
  StrategyMode=12もStrategyMode=11と同じ時刻条件で決済する。
  StrategyMode=13は、約定から30分後、サーバー23:00以後、または翌サーバー日以後に決済する。
  StrategyMode=14は、FXTFサーバー15:00以後または翌サーバー日以後に決済する。
  決済失敗時は成立した決済シグナルを保持し、後続ティックで再試行する。
- TP/SL:
  StrategyMode=0は固定TPを設定しない。StrategyMode=1は発注時のチャネル中央を固定TPとする。
  StrategyMode=2は、シフト2のEntryBars期間SMAを発注時の固定TPとする。
  StrategyMode=6もシグナル判定に使用した同じSMAを固定TPとする。
  発注時からSLを付け、約定価格からStopATR倍のATR幅へ補正する。
  SLはtick刻みへ外側に丸める。補正待ちの間も発注時のSLを維持し、トレーリングは行わない。
- ポジション数・ロット:
  同一Symbol・MagicNumberの注文がある間は新規発注しない。ロットはFixedLotsの固定値。
  最小・最大ロット、ロットステップに適合しない設定は初期化時に拒否する。
- 決済後休止:
  SLを含む最終決済バーの次のバーから、完了した平日のシグナル時間足バーをCooldownDays本数える。
  決済と同じ足には再エントリーしない。0本なら次のシグナル時間足バーから再開する。
  時刻・曜日はブローカーのサーバー時刻を使い、土日のバーは休止本数に含めない。
- テスター出力:
  日ごとの有効証拠金と残高をCSVへ記録する。スワップ・手数料はMT4口座計算に従う。
  保有コストの再現性はテスターの銘柄設定・データに依存する。
*/

#property strict
#property description "USDJPY/M30 決済需要日限定。JST09:50買い→09:55売り→10:00決済。ATR20×2 SL。FXTF時刻。"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
extern string TradeSymbol = "USDJPY";
extern int SignalTimeframe = PERIOD_M30; // 選定版はM30固定
extern int StrategyMode = 5;           // 選定版は5（仲値前後）固定。旧入力名を保持
extern int BreakoutTiming = 0;         // Mode0のみ: 0=確定足、1=H1バー内の現在Bid
extern int TokyoEntryMinute = 590;     // JST09:50固定
extern int TokyoExitMinute = 600;      // JST10:00固定
extern int SettlementDaysOnly = 1;     // 1=5の倍数日+月末、休日の前倒しなし（固定）
extern int PostFixDirection = 0;       // Mode4/Exit600のみ: 0=従来SELL、1=09:50比で方向反転
extern int EntryBars = 24;             // 旧入力互換用。選定版の売買信号には使用しない
extern int ExitBars = 6;               // 旧入力互換用。選定版は時刻決済
extern double StopATR = 2.0;           // 選定版はATR20shift2の2倍に固定
extern double TrailATR = 0;            // Mode0のみ: 0=従来チャネル、正値=確定終値ATR追随退出
extern double BreakoutBufferATR = 0.05; // ブレイク幅: ATRの0.05倍
extern int ATRPeriod = 20;             // ATR期間: 14/20/28/40
extern double DeviationATR = 1.0;      // Mode6の終値とSMAの最小乖離幅
extern int TrendMAPeriod = 0;          // 方向フィルターのEMA期間。0なら無効、2以上で有効
extern double MinSignalRangeATR = 0;   // シグナル足の最小高安幅/事前ATR。0なら無効
extern double MinPathEfficiency = 0;   // Mode1の事前終値変化/TR合計の下限。0なら無効
extern double RSIEntryLevel = 10;      // Mode2のRSI(2)買い下限。売り上限は100-この値
extern int EntryStartHour = 0;         // Mode1の新規発注開始時（0..23、終了は24時固定）
extern int CooldownDays = 1;           // 決済後休止: 完了した平日のシグナル時間足バー数（名前は互換性のため維持）
extern double FixedLots = 0.1;
extern double MaxSpreadPips = 2.0;
extern int Slippage = 20;              // point単位
extern int MagicNumber = 20261008;     // 他EA・同時装着するEAと重複させない
extern string EquityFileName = "";       // 空なら実行時刻を含む一意なCSV名を生成

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
datetime exitCheckedBar = 0;
string statePrefix = "";
int lastTokyoEntryDate = 0;
int lastTokyoSellDate = 0;
int lastLondonEntryDate = 0;
datetime lastRoundQuoteTime = 0;
long lastRoundBidPoints = 0;
long lastRoundAskPoints = 0;
long lastRoundSpreadPoints = 0;
datetime postFixInitTime = 0;
int postFixAnchorDate = 0;
long postFixAnchorQuoteSum = 0;
int postFixSignalDate = 0;
int postFixSignalSide = -1;
datetime breakoutCacheBar = 0;
double breakoutCacheUpper = 0;
double breakoutCacheLower = 0;
double breakoutCacheATR = 0;
datetime breakoutAttemptBar = 0;
datetime roundAttemptBar = 0;
int asianRangeDate = 0;
double asianRangeUpper = 0;
double asianRangeLower = 0;
int asianAttemptDate = 0;
string tokyoHolidays = ",20170101,20170102,20170109,20170211,20170320,20170429,20170503,20170504,20170505,20170717,20170811,20170918,20170923,20171009,20171103,20171123,20171223,20180101,20180108,20180211,20180212,20180321,20180429,20180430,20180503,20180504,20180505,20180716,20180811,20180917,20180923,20180924,20181008,20181103,20181123,20181223,20181224,20190101,20190114,20190211,20190321,20190429,20190430,20190501,20190502,20190503,20190504,20190505,20190506,20190715,20190811,20190812,20190916,20190923,20191014,20191022,20191103,20191104,20191123,20200101,20200113,20200211,20200223,20200224,20200320,20200429,20200503,20200504,20200505,20200506,20200723,20200724,20200810,20200921,20200922,20201103,20201123,20210101,20210111,20210211,20210223,20210320,20210429,20210503,20210504,20210505,20210722,20210723,20210808,20210809,20210920,20210923,20211103,20211123,20220101,20220110,20220211,20220223,20220321,20220429,20220503,20220504,20220505,20220718,20220811,20220919,20220923,20221010,20221103,20221123,20230101,20230102,20230109,20230211,20230223,20230321,20230429,20230503,20230504,20230505,20230717,20230811,20230918,20230923,20231009,20231103,20231123,20240101,20240108,20240211,20240212,20240223,20240320,20240429,20240503,20240504,20240505,20240506,20240715,20240811,20240812,20240916,20240922,20240923,20241014,20241103,20241104,20241123,20250101,20250113,20250211,20250223,20250224,20250320,20250429,20250503,20250504,20250505,20250506,20250721,20250811,20250915,20250923,20251013,20251103,20251123,20251124,20260101,20260112,20260211,20260223,20260320,20260429,20260503,20260504,20260505,20260506,20260720,20260811,20260921,20260922,20260923,20261012,20261103,20261123,20270101,20270111,20270211,20270223,20270321,20270322,20270429,20270503,20270504,20270505,20270719,20270811,20270920,20270923,20271011,20271103,20271123,";
string londonHolidays = ",20170102,20170414,20170417,20170501,20170529,20170828,20171225,20171226,20180101,20180330,20180402,20180507,20180528,20180827,20181225,20181226,20190101,20190419,20190422,20190506,20190527,20190826,20191225,20191226,20200101,20200410,20200413,20200508,20200525,20200831,20201225,20201228,20210101,20210402,20210405,20210503,20210531,20210830,20211227,20211228,20220103,20220415,20220418,20220502,20220602,20220603,20220829,20220919,20221226,20221227,20230102,20230407,20230410,20230501,20230508,20230529,20230828,20231225,20231226,20240101,20240329,20240401,20240506,20240527,20240826,20241225,20241226,20250101,20250418,20250421,20250505,20250526,20250825,20251225,20251226,20260101,20260403,20260406,20260504,20260525,20260831,20261225,20261228,20270101,20270326,20270329,20270503,20270531,20270830,20271227,20271228,";

//+------------------------------------------------------------------+
//| EA初期化                                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // 旧setを読み込んで別戦略を誤稼働させない。ロット・Magic・執行上限は設定可能。
   if(TradeSymbol != "USDJPY" || SignalTimeframe != PERIOD_M30 || StrategyMode != 5 ||
      TokyoEntryMinute != 590 || TokyoExitMinute != 600 || SettlementDaysOnly != 1 ||
      ATRPeriod != 20 || MathAbs(StopATR - 2.0) > 1e-9 || CooldownDays != 1 ||
      BreakoutTiming != 0 || TrailATR != 0 || PostFixDirection != 0 ||
      TrendMAPeriod != 0 || MinSignalRangeATR != 0 || MinPathEfficiency != 0 || EntryStartHour != 0)
   {
      Print("STR03 selected profile requires USDJPY/M30, Mode5, JST590/600, Settlement1, ATR20/Stop2 and no extra filters.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   postFixInitTime = TimeCurrent();
   postFixAnchorDate = 0;
   postFixAnchorQuoteSum = 0;
   postFixSignalDate = 0;
   postFixSignalSide = -1;
   breakoutCacheBar = 0;
   breakoutCacheUpper = 0;
   breakoutCacheLower = 0;
   breakoutCacheATR = 0;
   breakoutAttemptBar = 0;
   roundAttemptBar = 0;
   asianRangeDate = 0;
   asianRangeUpper = 0;
   asianRangeLower = 0;
   asianAttemptDate = 0;
   if(StrategyMode == 13)
   {
      lastRoundQuoteTime = 0;
      lastRoundBidPoints = 0;
      lastRoundAskPoints = 0;
      lastRoundSpreadPoints = 0;
   }

   if((SignalTimeframe != PERIOD_M30 && SignalTimeframe != PERIOD_H1 &&
       SignalTimeframe != PERIOD_H4) || Period() != SignalTimeframe ||
      StringLen(TradeSymbol) != 6 ||
      StringSubstr(Symbol(), 0, 6) != TradeSymbol)
      return(INIT_PARAMETERS_INCORRECT);

   // 感度分析の対象範囲外も許容するが、チャネル間の制約と入力値の有効性を検証する。
   if((StrategyMode < 0 || StrategyMode > 14) ||
      ((StrategyMode < 3 || StrategyMode == 6 || StrategyMode == 11 || StrategyMode == 12 || StrategyMode == 13 || StrategyMode == 14) && EntryBars < 2) ||
      (StrategyMode == 0 && TrailATR == 0 && (ExitBars < 1 || ExitBars > EntryBars / 2)) ||
      BreakoutTiming < 0 || BreakoutTiming > 1 ||
      (BreakoutTiming == 1 &&
       (StrategyMode != 0 || TrailATR != 0 || TradeSymbol != "USDJPY" ||
        SignalTimeframe != PERIOD_H1 || EntryBars != 24 || ExitBars != 6 || ATRPeriod != 20 ||
        MathAbs(BreakoutBufferATR - 0.05) > 1e-9 || CooldownDays != 1 ||
        TrendMAPeriod != 0 || MinSignalRangeATR != 0 || MinPathEfficiency != 0 ||
        EntryStartHour != 0)) ||
      ATRPeriod < 1 || TrendMAPeriod < 0 || TrendMAPeriod == 1 ||
      StopATR <= 0 || TrailATR < 0 || (StrategyMode != 0 && TrailATR != 0) ||
      BreakoutBufferATR < 0 || MinSignalRangeATR < 0 || CooldownDays < 0 ||
      MinPathEfficiency < 0 || MinPathEfficiency > 1 ||
      (StrategyMode != 1 && MinPathEfficiency != 0) ||
      EntryStartHour < 0 || EntryStartHour > 23 || (StrategyMode != 1 && EntryStartHour != 0) ||
      (StrategyMode == 1 && (TrendMAPeriod != 0 || MinSignalRangeATR != 0)) ||
      (StrategyMode == 2 && (TrendMAPeriod < 2 || MinSignalRangeATR != 0 ||
                            RSIEntryLevel <= 0 || RSIEntryLevel >= 50)) ||
      (StrategyMode >= 3 && StrategyMode <= 5 &&
       (TradeSymbol != "USDJPY" || SignalTimeframe != PERIOD_M30 || ATRPeriod != 20 ||
        TrendMAPeriod != 0 || MinSignalRangeATR != 0 ||
        MinPathEfficiency != 0 || EntryStartHour != 0)) ||
      (StrategyMode == 6 && (DeviationATR <= 0 || TrendMAPeriod != 0 ||
                            MinSignalRangeATR != 0 || MinPathEfficiency != 0 ||
                            EntryStartHour != 0)) ||
      ((StrategyMode >= 7 && StrategyMode <= 10) &&
       (TradeSymbol != "EURUSD" || SignalTimeframe != PERIOD_H1 || ATRPeriod != 20 ||
        TrendMAPeriod != 0 || MinSignalRangeATR != 0 || MinPathEfficiency != 0 ||
        EntryStartHour != 0 || SettlementDaysOnly != 0)) ||
      ((StrategyMode == 11 || StrategyMode == 12) &&
       (TradeSymbol != "USDJPY" || SignalTimeframe != PERIOD_M30 || ATRPeriod != 20 ||
        EntryBars != 2 || TrendMAPeriod != 0 || MinSignalRangeATR != 0 ||
        MinPathEfficiency != 0 || EntryStartHour != 0 || SettlementDaysOnly != 0)) ||
      (StrategyMode == 13 &&
       (TradeSymbol != "USDJPY" || SignalTimeframe != PERIOD_M30 || ATRPeriod != 20 ||
        EntryBars != 2 || ExitBars != 1 || CooldownDays != 1 ||
        TrendMAPeriod != 0 || MinSignalRangeATR != 0 || MinPathEfficiency != 0 ||
        EntryStartHour != 0 || BreakoutTiming != 0 || TrailATR != 0 ||
        PostFixDirection != 0 || SettlementDaysOnly != 0 ||
        MathAbs(MaxSpreadPips - 2.0) > 1e-9)) ||
      (StrategyMode == 14 &&
       (TradeSymbol != "EURUSD" || SignalTimeframe != PERIOD_H1 || ATRPeriod != 20 ||
        EntryBars != 2 || ExitBars != 1 || CooldownDays != 1 || BreakoutBufferATR != 0 ||
        TrendMAPeriod != 0 || MinSignalRangeATR != 0 || MinPathEfficiency != 0 ||
        EntryStartHour != 0 || BreakoutTiming != 0 || TrailATR != 0 ||
        PostFixDirection != 0 || SettlementDaysOnly != 0)) ||
      (StrategyMode == 3 && TokyoEntryMinute != 450 && TokyoEntryMinute != 480 && TokyoEntryMinute != 510) ||
      (StrategyMode == 5 &&
       !((TokyoEntryMinute == 480 && (TokyoExitMinute == 600 || TokyoExitMinute == 690 || TokyoExitMinute == 720 || TokyoExitMinute == 750)) ||
         (TokyoEntryMinute == 590 && TokyoExitMinute == 600))) ||
      (StrategyMode == 4 &&
       TokyoExitMinute != 600 && TokyoExitMinute != 690 && TokyoExitMinute != 720 && TokyoExitMinute != 750) ||
      PostFixDirection < 0 || PostFixDirection > 1 ||
      (PostFixDirection == 1 && (StrategyMode != 4 || TokyoExitMinute != 600)) ||
      SettlementDaysOnly < 0 || SettlementDaysOnly > 2 ||
      (SettlementDaysOnly > 0 &&
       (StrategyMode != 5 || TokyoEntryMinute != 590 || TokyoExitMinute != 600)) ||
      FixedLots <= 0 || MaxSpreadPips <= 0 || Slippage < 0 || MagicNumber <= 0)
      return(INIT_PARAMETERS_INCORRECT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0 || FixedLots < MarketInfo(Symbol(), MODE_MINLOT) ||
      FixedLots > MarketInfo(Symbol(), MODE_MAXLOT) ||
      MathAbs(FixedLots / step - MathRound(FixedLots / step)) > 1e-7)
      return(INIT_PARAMETERS_INCORRECT);

   // 運用中に装着・再初期化した場合は新規発注だけを途中参加させない。
   // 既存ポジションの決済・SL補正状態は端末Global Variableから復元する。
   if(!IsTesting())
   {
      lastBar = iTime(Symbol(), SignalTimeframe, 0);
      statePrefix = "STR03." + IntegerToString(AccountNumber()) + "." + Symbol() + "." +
                    IntegerToString(MagicNumber);
      if(StringLen(statePrefix) + 18 > 63)
      {
         Print("Persistent state key is too long for Symbol=", Symbol());
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
      if(GlobalVariableCheck(statePrefix + ".london"))
         lastLondonEntryDate = (int)GlobalVariableGet(statePrefix + ".london");
      if(BreakoutTiming == 1 && GlobalVariableCheck(statePrefix + ".breakbar"))
         breakoutAttemptBar = (datetime)GlobalVariableGet(statePrefix + ".breakbar");
      if(StrategyMode == 13 && GlobalVariableCheck(statePrefix + ".roundbar"))
         roundAttemptBar = (datetime)GlobalVariableGet(statePrefix + ".roundbar");
      if(StrategyMode == 14 && GlobalVariableCheck(statePrefix + ".asiaday"))
         asianAttemptDate = (int)GlobalVariableGet(statePrefix + ".asiaday");
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            Print("Init OrderSelect failed error=", GetLastError());
            continue;
         }
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber ||
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
         string outputBase = StringFormat("STR03_Donchian_%d_%d_%s_%d_%04d%02d%02d_%02d%02d%02d_equity",
                                          SignalTimeframe, AccountNumber(), Symbol(), MagicNumber,
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
      Print("Equity output=", outputName);
   }
   Print("SPEC currency=", AccountCurrency(), " capital=", AccountBalance(),
         " tick_size=", SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE),
         " min_lot=", MarketInfo(Symbol(), MODE_MINLOT),
         " lot_step=", step, " spread=", MarketInfo(Symbol(), MODE_SPREAD),
         " swap_type=", MarketInfo(Symbol(), MODE_SWAPTYPE),
         " swap_long=", MarketInfo(Symbol(), MODE_SWAPLONG),
         " swap_short=", MarketInfo(Symbol(), MODE_SWAPSHORT));
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
}

//+------------------------------------------------------------------+
//| ティック処理                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   int roundTickSide = -1;
   long roundTickLevel = 0;
   int breakoutTickSide = -1;
   int asianSide = -1;
   // サーバー日付が変わったら、直前の日の最後の観測値を記録する。
   if(equityFile != INVALID_HANDLE && lastTick > 0 &&
      (long)now / 86400 != (long)lastTick / 86400)
      FileWrite(equityFile, TimeToString(lastTick, TIME_DATE | TIME_SECONDS),
                DoubleToString(lastEquity, 2), DoubleToString(lastBalance, 2));
   lastTick = now;
   lastEquity = AccountEquity();
   lastBalance = AccountBalance();

   // 発注不能な間はシグナル足を消費せず、最初の発注可能なティックを待つ。
   // テスターでは銘柄の売買許可が0を返す場合があるため、実運用時だけ確認する。
   if(!IsTradeAllowed() || (!IsTesting() && MarketInfo(Symbol(), MODE_TRADEALLOWED) == 0))
   {
      if(StrategyMode == 12 || StrategyMode == 13) lastRoundQuoteTime = 0;
      return;
   }
   RefreshRates();
   if(Bid <= 0 || Ask <= 0 || Ask < Bid)
   {
      if(StrategyMode == 12 || StrategyMode == 13) lastRoundQuoteTime = 0;
      return;
   }
   double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0)
   {
      if(StrategyMode == 12 || StrategyMode == 13) lastRoundQuoteTime = 0;
      return;
   }

   // Mode12は管理系returnより前に毎ティックを観測し、過去の横断を持ち越さない。
   if(StrategyMode == 12)
   {
      long currentBidPoints = (long)MathRound(Bid / Point);
      long currentAskPoints = (long)MathRound(Ask / Point);
      long currentSpreadPoints = currentAskPoints - currentBidPoints;
      double roundPointsPerPip = (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
      long roundMaxSpreadPoints = (long)MathFloor(MaxSpreadPips * roundPointsPerPip + 1e-9);
      long roundStep = (long)MathRound(0.50 / Point);
      int currentDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int currentMinute = TimeHour(now) * 60 + TimeMinute(now);
      int currentWeekday = TimeDayOfWeek(now);
      int previousDate = TimeYear(lastRoundQuoteTime) * 10000 +
                         TimeMonth(lastRoundQuoteTime) * 100 + TimeDay(lastRoundQuoteTime);
      int previousMinute = TimeHour(lastRoundQuoteTime) * 60 + TimeMinute(lastRoundQuoteTime);
      bool currentWindow = (currentWeekday >= 1 && currentWeekday <= 5 &&
                            currentMinute >= 16 * 60 + 30 && currentMinute <= 22 * 60);
      bool previousWindow = (lastRoundQuoteTime > 0 && previousDate == currentDate &&
                             previousMinute >= 16 * 60 + 30 && previousMinute <= 22 * 60);
      if(currentBidPoints > 0 && currentAskPoints > 0 && roundStep > 0 &&
         currentWindow && previousWindow && now >= lastRoundQuoteTime &&
         now - lastRoundQuoteTime <= 60 &&
         currentSpreadPoints <= roundMaxSpreadPoints &&
         lastRoundSpreadPoints <= roundMaxSpreadPoints)
      {
         long buyCount = 0;
         long sellCount = 0;
         if(currentAskPoints > lastRoundAskPoints)
            buyCount = (currentAskPoints - 1) / roundStep -
                       (lastRoundAskPoints + roundStep - 1) / roundStep + 1;
         if(currentBidPoints < lastRoundBidPoints)
            sellCount = lastRoundBidPoints / roundStep - currentBidPoints / roundStep;
         bool buySignal = (buyCount == 1 && currentAskPoints % roundStep != 0);
         bool sellSignal = (sellCount == 1 && currentBidPoints % roundStep != 0);
         if(buySignal != sellSignal) roundTickSide = (buySignal ? OP_BUY : OP_SELL);
      }
      lastRoundQuoteTime = now;
      lastRoundBidPoints = currentBidPoints;
      lastRoundAskPoints = currentAskPoints;
      lastRoundSpreadPoints = currentSpreadPoints;
   }
   else if(StrategyMode == 13)
   {
      long currentBidPoints = (long)MathRound(Bid / Point);
      long currentAskPoints = (long)MathRound(Ask / Point);
      long currentSpreadPoints = currentAskPoints - currentBidPoints;
      double roundPointsPerPip = (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
      long roundMaxSpreadPoints = (long)MathFloor(MaxSpreadPips * roundPointsPerPip + 1e-9);
      long roundStep = (long)MathRound(1.00 / Point);
      int currentDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int currentMinute = TimeHour(now) * 60 + TimeMinute(now);
      int currentWeekday = TimeDayOfWeek(now);
      int previousDate = TimeYear(lastRoundQuoteTime) * 10000 +
                         TimeMonth(lastRoundQuoteTime) * 100 + TimeDay(lastRoundQuoteTime);
      int previousMinute = TimeHour(lastRoundQuoteTime) * 60 + TimeMinute(lastRoundQuoteTime);
      bool currentWindow = (currentWeekday >= 1 && currentWeekday <= 5 &&
                            currentMinute >= 16 * 60 && currentMinute < 22 * 60 + 30);
      bool previousWindow = (lastRoundQuoteTime > 0 && previousDate == currentDate &&
                             previousMinute >= 16 * 60 && previousMinute < 22 * 60 + 30);
      if(currentBidPoints > 0 && currentAskPoints > 0 && roundStep > 0 &&
         currentWindow && previousWindow && now >= lastRoundQuoteTime &&
         now - lastRoundQuoteTime <= 60 &&
         currentSpreadPoints <= roundMaxSpreadPoints &&
         lastRoundSpreadPoints <= roundMaxSpreadPoints)
      {
         long sellCount = 0;
         long buyCount = 0;
         if(currentBidPoints > lastRoundBidPoints)
            sellCount = currentBidPoints / roundStep - lastRoundBidPoints / roundStep;
         if(currentAskPoints < lastRoundAskPoints)
            buyCount = (lastRoundAskPoints - 1) / roundStep -
                       (currentAskPoints + roundStep - 1) / roundStep + 1;
         bool sellSignal = (sellCount == 1);
         bool buySignal = (buyCount == 1);
         if(sellCount <= 1 && buyCount <= 1 && sellSignal != buySignal)
         {
            roundTickSide = (sellSignal ? OP_SELL : OP_BUY);
            roundTickLevel = (sellSignal ?
               (lastRoundBidPoints / roundStep + 1) * roundStep :
               (lastRoundAskPoints - 1) / roundStep * roundStep);
         }
      }
      lastRoundQuoteTime = now;
      lastRoundBidPoints = currentBidPoints;
      lastRoundAskPoints = currentAskPoints;
      lastRoundSpreadPoints = currentSpreadPoints;
   }

   int tokyoDate = 0;
   int tokyoMinute = -1;
   bool dstTransitionSunday = false;
   datetime tokyoNow = 0;
   int londonDate = 0;
   int londonMinute = -1;
   datetime londonNow = 0;
   int asianRangeBars = 0;
   if(StrategyMode >= 3 && StrategyMode <= 5)
   {
      int serverYear = TimeYear(now);
      datetime marchFirst = StringToTime(IntegerToString(serverYear) + ".03.01 00:00");
      datetime novemberFirst = StringToTime(IntegerToString(serverYear) + ".11.01 00:00");
      int marchSunday = 8 + (7 - TimeDayOfWeek(marchFirst)) % 7;
      int novemberSunday = 1 + (7 - TimeDayOfWeek(novemberFirst)) % 7;
      int serverDate = serverYear * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int marchDate = serverYear * 10000 + 300 + marchSunday;
      int novemberDate = serverYear * 10000 + 1100 + novemberSunday;
      bool summerTime = (serverDate >= marchDate && serverDate < novemberDate);
      dstTransitionSunday = (serverDate == marchDate || serverDate == novemberDate);
      tokyoNow = now + (summerTime ? 6 : 7) * 3600;
      tokyoDate = TimeYear(tokyoNow) * 10000 + TimeMonth(tokyoNow) * 100 + TimeDay(tokyoNow);
      tokyoMinute = TimeHour(tokyoNow) * 60 + TimeMinute(tokyoNow);
   }
   if(StrategyMode == 4 && PostFixDirection == 1)
   {
      if(postFixAnchorDate != tokyoDate)
      {
         postFixAnchorDate = 0;
         postFixAnchorQuoteSum = 0;
      }
      if(postFixSignalDate != tokyoDate) postFixSignalSide = -1;
      if(tokyoMinute == 9 * 60 + 50 && postFixAnchorDate != tokyoDate &&
         postFixInitTime < now - TimeSeconds(now))
      {
         postFixAnchorDate = tokyoDate;
         postFixAnchorQuoteSum = (long)MathRound(Bid / Point) +
                                 (long)MathRound(Ask / Point);
      }
      if(tokyoMinute == 9 * 60 + 55 && postFixSignalDate != tokyoDate)
      {
         postFixSignalDate = tokyoDate;
         postFixSignalSide = -1;
         if(postFixAnchorDate == tokyoDate && postFixAnchorQuoteSum > 0)
         {
            long postFixQuoteSum = (long)MathRound(Bid / Point) +
                                   (long)MathRound(Ask / Point);
            if(postFixQuoteSum > postFixAnchorQuoteSum) postFixSignalSide = OP_SELL;
            if(postFixQuoteSum < postFixAnchorQuoteSum) postFixSignalSide = OP_BUY;
         }
      }
   }
   if((StrategyMode >= 7 && StrategyMode <= 10) || StrategyMode == 14)
   {
      int londonServerYear = TimeYear(now);
      datetime usMarchFirst = StringToTime(IntegerToString(londonServerYear) + ".03.01 00:00");
      datetime usNovemberFirst = StringToTime(IntegerToString(londonServerYear) + ".11.01 00:00");
      int usMarchSunday = 8 + (7 - TimeDayOfWeek(usMarchFirst)) % 7;
      int usNovemberSunday = 1 + (7 - TimeDayOfWeek(usNovemberFirst)) % 7;
      int londonServerDate = londonServerYear * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int usMarchDate = londonServerYear * 10000 + 300 + usMarchSunday;
      int usNovemberDate = londonServerYear * 10000 + 1100 + usNovemberSunday;
      bool usSummerTime = (londonServerDate >= usMarchDate && londonServerDate < usNovemberDate);
      datetime ukMarchLast = StringToTime(IntegerToString(londonServerYear) + ".03.31 00:00");
      datetime ukOctoberLast = StringToTime(IntegerToString(londonServerYear) + ".10.31 00:00");
      int ukMarchSunday = 31 - TimeDayOfWeek(ukMarchLast);
      int ukOctoberSunday = 31 - TimeDayOfWeek(ukOctoberLast);
      int ukMarchDate = londonServerYear * 10000 + 300 + ukMarchSunday;
      int ukOctoberDate = londonServerYear * 10000 + 1000 + ukOctoberSunday;
      bool ukSummerTime = (londonServerDate >= ukMarchDate && londonServerDate < ukOctoberDate);
      londonNow = now + ((ukSummerTime ? 1 : 0) - (usSummerTime ? 3 : 2)) * 3600;
      londonDate = TimeYear(londonNow) * 10000 + TimeMonth(londonNow) * 100 + TimeDay(londonNow);
      londonMinute = TimeHour(londonNow) * 60 + TimeMinute(londonNow);
      if(StrategyMode == 14)
         asianRangeBars = 7 + (usSummerTime ? 3 : 2) - (ukSummerTime ? 1 : 0);
   }

   // 成立済みの決済意思は、SL補正やシグナル用価格データより先に執行する。
   bool exitAttempted = false;
   if(exitTicket >= 0)
   {
      int pendingExit = exitTicket;
      if(!OrderSelect(pendingExit, SELECT_BY_TICKET))
         Print("Exit OrderSelect failed ticket=", pendingExit, " error=", GetLastError());
      else if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
              (OrderType() == OP_BUY || OrderType() == OP_SELL))
      {
         string pendingPrefix = statePrefix + "." + IntegerToString(pendingExit);
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
            exitAttempted = true;
            int pendingSide = OrderType();
            double pendingPrice = (pendingSide == OP_BUY ? Bid : Ask);
            double pendingFreeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
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
               else Print("Exit failed ticket=", pendingExit, " error=", GetLastError());
            }
         }
      }
   }

   // スリッページがあれば、約定価格を基準に初期SLを補正する。既存SLは外さない。
   if(stopTicket >= 0)
   {
      if(!OrderSelect(stopTicket, SELECT_BY_TICKET))
         Print("SL OrderSelect failed error=", GetLastError());
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
         else if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
                 (OrderType() == OP_BUY || OrderType() == OP_SELL))
         {
            double target = OrderOpenPrice() + (OrderType() == OP_BUY ? -1.0 : 1.0) * stopDistance;
            stopTarget = NormalizeDouble((OrderType() == OP_BUY ? MathFloor(target / tick) : MathCeil(target / tick)) * tick,
                                         Digits);
            if(MathAbs(OrderStopLoss() - stopTarget) < tick / 2)
            {
               stopTicket = -1;
               if(!IsTesting())
               {
                  GlobalVariableDel(stopPrefix + ".stop");
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
                     if(!IsTesting())
                     {
                        GlobalVariableDel(stopPrefix + ".stop");
                        GlobalVariablesFlush();
                     }
                  }
                  else Print("SL correction failed ticket=", pendingStop, " error=", GetLastError());
               }
            }
         }
      }
   }

   datetime bar = iTime(Symbol(), SignalTimeframe, 0);
   bool newBar = (bar > 0 && bar != lastBar);

   // 同一銘柄・Magicの注文を照合し、停止中を含む未処理確定足を古い順に判定する。
   bool occupied = false;
   bool orderScanOk = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         Print("OrderSelect failed error=", GetLastError());
         orderScanOk = false;
         continue;
      }
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
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

      if(StrategyMode == 11 || StrategyMode == 12 || StrategyMode == 13)
      {
         int currentServerDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
         datetime roundOpenTime = OrderOpenTime();
         int openServerDate = TimeYear(roundOpenTime) * 10000 +
                              TimeMonth(roundOpenTime) * 100 + TimeDay(roundOpenTime);
         int roundHoldSeconds = (StrategyMode == 13 ? 1800 : 3600);
         if(now >= roundOpenTime + roundHoldSeconds || currentServerDate > openServerDate ||
            TimeHour(now) * 60 + TimeMinute(now) >= 23 * 60)
         {
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print("Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      else if(StrategyMode == 14)
      {
         int currentServerDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
         datetime asianOpenTime = OrderOpenTime();
         int openServerDate = TimeYear(asianOpenTime) * 10000 +
                              TimeMonth(asianOpenTime) * 100 + TimeDay(asianOpenTime);
         if(currentServerDate > openServerDate ||
            TimeHour(now) * 60 + TimeMinute(now) >= 15 * 60)
         {
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print("Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      else if(StrategyMode >= 7 && StrategyMode <= 10)
      {
         int currentServerDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
         datetime londonOpenTime = OrderOpenTime();
         int openServerDate = TimeYear(londonOpenTime) * 10000 +
                              TimeMonth(londonOpenTime) * 100 + TimeDay(londonOpenTime);
         int londonCloseMinute = (StrategyMode == 7 ? 23 * 60 + 45 :
                                  (StrategyMode == 9 ? 15 * 60 + 15 : 15 * 60));
         if(currentServerDate > openServerDate ||
            TimeHour(now) * 60 + TimeMinute(now) >= londonCloseMinute)
         {
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print("Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      else if(StrategyMode >= 3 && StrategyMode <= 5)
      {
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
         int openTokyoDate = TimeYear(openTokyoTime) * 10000 +
                             TimeMonth(openTokyoTime) * 100 + TimeDay(openTokyoTime);
         int tokyoCloseMinute = (StrategyMode == 3 ||
                                 (StrategyMode == 5 && side == OP_BUY) ?
                                 9 * 60 + 55 : TokyoExitMinute);
         if(tokyoDate > openTokyoDate || tokyoMinute >= tokyoCloseMinute)
         {
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print("Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      else if(StrategyMode == 1 || StrategyMode == 2 || StrategyMode == 6)
      {
         int openShift = iBarShift(Symbol(), SignalTimeframe, OrderOpenTime(), false);
         if(openShift >= EntryBars)
         {
            exitTicket = activeTicket;
            if(!IsTesting())
            {
               if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                  Print("Exit state save failed ticket=", activeTicket,
                        " error=", GetLastError());
               GlobalVariablesFlush();
            }
         }
      }
      else
      {
         datetime checkedBar = exitCheckedBar;
         if(!IsTesting() && GlobalVariableCheck(activePrefix + ".eval"))
            checkedBar = (datetime)GlobalVariableGet(activePrefix + ".eval");
         int availableBars = iBars(Symbol(), SignalTimeframe);
         datetime processedBar = 0;
         if(TrailATR > 0)
         {
            int openShift = iBarShift(Symbol(), SignalTimeframe, OrderOpenTime(), false);
            if(checkedBar == 0 && openShift >= 0)
               checkedBar = iTime(Symbol(), SignalTimeframe, openShift + 1);
            int checkedShift = iBarShift(Symbol(), SignalTimeframe, checkedBar, false);
            if(openShift >= 1 && checkedBar > 0 && checkedShift > 1 &&
               availableBars > openShift + 2 + ATRPeriod)
            {
               int atrShift = openShift + 2;
               bool atrDataValid = true;
               for(int trailAtrBar = atrShift;
                   trailAtrBar < atrShift + ATRPeriod; trailAtrBar++)
               {
                  double atrHigh = iHigh(Symbol(), SignalTimeframe, trailAtrBar);
                  double atrLow = iLow(Symbol(), SignalTimeframe, trailAtrBar);
                  double atrClose = iClose(Symbol(), SignalTimeframe, trailAtrBar + 1);
                  if(atrHigh <= 0 || atrLow <= 0 || atrHigh < atrLow || atrClose <= 0)
                  {
                     atrDataValid = false;
                     break;
                  }
               }
               double entryATR = iATR(Symbol(), SignalTimeframe, ATRPeriod, atrShift);
               double atrPreviousClose = iClose(Symbol(), SignalTimeframe,
                                                atrShift + ATRPeriod);
               if(atrDataValid && entryATR > 0 && atrPreviousClose > 0)
               {
                  double trailDistance = entryATR * TrailATR;
                  int firstTrailShift = MathMin(checkedShift - 1, openShift);
                  for(int e = firstTrailShift; e >= 1; e--)
                  {
                     datetime trailBarTime = iTime(Symbol(), SignalTimeframe, e);
                     double exitClose = iClose(Symbol(), SignalTimeframe, e);
                     int trailCount = openShift - e + 1;
                     bool trailPricesValid = true;
                     for(int trailPriceBar = e; trailPriceBar <= openShift; trailPriceBar++)
                     {
                        double trailHigh = iHigh(Symbol(), SignalTimeframe, trailPriceBar);
                        double trailLow = iLow(Symbol(), SignalTimeframe, trailPriceBar);
                        if(trailHigh <= 0 || trailLow <= 0 || trailHigh < trailLow)
                        {
                           trailPricesValid = false;
                           break;
                        }
                     }
                     if(!trailPricesValid) break;
                     int extremeShift = (side == OP_BUY ?
                        iHighest(Symbol(), SignalTimeframe, MODE_HIGH, trailCount, e) :
                        iLowest(Symbol(), SignalTimeframe, MODE_LOW, trailCount, e));
                     if(trailBarTime <= 0 || exitClose <= 0 || trailCount < 1 || extremeShift < 0 ||
                        trailDistance <= 0) break;
                     double trailExtreme = (side == OP_BUY ?
                        iHigh(Symbol(), SignalTimeframe, extremeShift) :
                        iLow(Symbol(), SignalTimeframe, extremeShift));
                     if(trailExtreme <= 0) break;
                     processedBar = trailBarTime;
                     if((side == OP_BUY && exitClose < trailExtreme - trailDistance) ||
                        (side == OP_SELL && exitClose > trailExtreme + trailDistance))
                     {
                        exitTicket = activeTicket;
                        if(!IsTesting())
                        {
                           if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                              Print("Exit state save failed ticket=", activeTicket,
                                    " error=", GetLastError());
                           GlobalVariablesFlush();
                        }
                        break;
                     }
                  }
               }
            }
         }
         else
         {
            if(checkedBar == 0) checkedBar = OrderOpenTime();
            int checkedShift = iBarShift(Symbol(), SignalTimeframe, checkedBar, false);
            if(checkedShift == 0 && OrderOpenTime() >= bar)
               processedBar = iTime(Symbol(), SignalTimeframe, 1);
            else if(checkedShift > 0 && availableBars >= ExitBars + 2)
            {
               int firstExitShift = MathMin(checkedShift - 1, availableBars - ExitBars - 1);
               for(int e = firstExitShift; e >= 1; e--)
               {
                  double exitClose = iClose(Symbol(), SignalTimeframe, e);
                  int exitLowShift = iLowest(Symbol(), SignalTimeframe, MODE_LOW, ExitBars, e + 1);
                  int exitHighShift = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, ExitBars, e + 1);
                  if(exitClose <= 0 || exitLowShift < 0 || exitHighShift < 0) break;
                  processedBar = iTime(Symbol(), SignalTimeframe, e);
                  if((side == OP_BUY && exitClose < iLow(Symbol(), SignalTimeframe, exitLowShift)) ||
                     (side == OP_SELL && exitClose > iHigh(Symbol(), SignalTimeframe, exitHighShift)))
                  {
                     exitTicket = activeTicket;
                     if(!IsTesting())
                     {
                        if(GlobalVariableSet(activePrefix + ".exit", 1) == 0)
                           Print("Exit state save failed ticket=", activeTicket,
                                 " error=", GetLastError());
                        GlobalVariablesFlush();
                     }
                     break;
                  }
               }
            }
         }
         if(processedBar > 0)
         {
            exitCheckedBar = processedBar;
            if(!IsTesting())
            {
               GlobalVariableSet(activePrefix + ".eval", processedBar);
               GlobalVariablesFlush();
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
      else Print("Exit failed ticket=", activeTicket, " error=", GetLastError());
   }
   if(!orderScanOk) return;
   if(occupied)
   {
      if(newBar) lastBar = bar;
      return;
   }

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
              OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
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
      if(!heldResolved)
      {
         Print("Last held ticket unresolved; entry suspended ticket=", heldTicket,
               " error=", GetLastError());
         return;
      }
   }

   if(StrategyMode == 14)
   {
      int asianServerDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int asianServerMinute = TimeHour(now) * 60 + TimeMinute(now);
      int asianWeekday = TimeDayOfWeek(londonNow);
      long asianBidPoints = (long)MathRound(Bid / Point);
      long asianAskPoints = (long)MathRound(Ask / Point);
      double asianPointsPerPip = (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
      long asianMaxSpreadPoints = (long)MathFloor(MaxSpreadPips * asianPointsPerPip + 1e-9);
      if(asianAttemptDate == asianServerDate || asianRangeBars < 9 || asianRangeBars > 10 ||
         londonDate != asianServerDate || asianWeekday == 0 || asianWeekday == 6 ||
         londonMinute < 7 * 60 || asianServerMinute >= 15 * 60 ||
         asianAskPoints - asianBidPoints > asianMaxSpreadPoints)
         return;
      if(asianRangeDate != asianServerDate)
      {
         asianRangeDate = asianServerDate;
         asianRangeUpper = 0;
         asianRangeLower = 0;
         datetime asianMidnight = now - TimeHour(now) * 3600 -
                                  TimeMinute(now) * 60 - TimeSeconds(now);
         bool asianRangeValid = true;
         for(int asianHour = 0; asianHour < asianRangeBars; asianHour++)
         {
            datetime plannedBar = asianMidnight + asianHour * 3600;
            int plannedShift = iBarShift(Symbol(), SignalTimeframe, plannedBar, true);
            if(plannedShift < 1 || iTime(Symbol(), SignalTimeframe, plannedShift) != plannedBar ||
               plannedBar + 3600 > bar)
            {
               asianRangeValid = false;
               break;
            }
            double plannedHigh = iHigh(Symbol(), SignalTimeframe, plannedShift);
            double plannedLow = iLow(Symbol(), SignalTimeframe, plannedShift);
            if(plannedHigh <= 0 || plannedLow <= 0 || plannedHigh < plannedLow)
            {
               asianRangeValid = false;
               break;
            }
            if(asianHour == 0 || plannedHigh > asianRangeUpper) asianRangeUpper = plannedHigh;
            if(asianHour == 0 || plannedLow < asianRangeLower) asianRangeLower = plannedLow;
         }
         if(!asianRangeValid)
         {
            asianRangeUpper = 0;
            asianRangeLower = 0;
         }
      }
      if(asianRangeUpper <= 0 || asianRangeLower <= 0 || asianRangeLower >= asianRangeUpper)
         return;
      if(Bid > asianRangeUpper) asianSide = OP_BUY;
      if(Bid < asianRangeLower) asianSide = OP_SELL;
      if(asianSide < 0) return;
   }

   if(StrategyMode == 13 && (roundAttemptBar == bar || roundTickSide < 0)) return;

   // Mode0のバー内判定は、管理完了後に現在足専用の確定足閾値を用意する。
   if(BreakoutTiming == 1)
   {
      if(bar <= 0 || breakoutAttemptBar == bar) return;
      if(breakoutCacheBar != bar)
      {
         int requiredBreakoutBars = (EntryBars > ATRPeriod + 1 ? EntryBars : ATRPeriod + 1);
         if(iBars(Symbol(), SignalTimeframe) <= requiredBreakoutBars) return;
         bool breakoutDataValid = true;
         for(int breakoutDataBar = 1; breakoutDataBar <= requiredBreakoutBars; breakoutDataBar++)
         {
            double breakoutHigh = iHigh(Symbol(), SignalTimeframe, breakoutDataBar);
            double breakoutLow = iLow(Symbol(), SignalTimeframe, breakoutDataBar);
            if(breakoutHigh <= 0 || breakoutLow <= 0 || breakoutHigh < breakoutLow)
            {
               breakoutDataValid = false;
               break;
            }
         }
         int breakoutUpperShift = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, EntryBars, 1);
         int breakoutLowerShift = iLowest(Symbol(), SignalTimeframe, MODE_LOW, EntryBars, 1);
         double breakoutATR = iATR(Symbol(), SignalTimeframe, ATRPeriod, 1);
         double breakoutATRPreviousClose = iClose(Symbol(), SignalTimeframe, ATRPeriod + 1);
         if(!breakoutDataValid || breakoutUpperShift < 0 || breakoutLowerShift < 0 ||
            breakoutATR <= 0 || breakoutATRPreviousClose <= 0)
            return;
         double breakoutUpper = iHigh(Symbol(), SignalTimeframe, breakoutUpperShift);
         double breakoutLower = iLow(Symbol(), SignalTimeframe, breakoutLowerShift);
         if(breakoutUpper <= 0 || breakoutLower <= 0 || breakoutLower >= breakoutUpper ||
            iTime(Symbol(), SignalTimeframe, 0) != bar)
            return;
         breakoutCacheUpper = breakoutUpper;
         breakoutCacheLower = breakoutLower;
         breakoutCacheATR = breakoutATR;
         breakoutCacheBar = bar;
      }
      if(Bid > breakoutCacheUpper + BreakoutBufferATR * breakoutCacheATR)
         breakoutTickSide = OP_BUY;
      if(Bid < breakoutCacheLower - BreakoutBufferATR * breakoutCacheATR)
         breakoutTickSide = OP_SELL;
      if(breakoutTickSide < 0) return;
   }

   // Mode4/5の09:55売りとMode5の09:50買いはM30境界を待たず判定する。
   bool tokyoSellWindow = ((StrategyMode == 4 || StrategyMode == 5) &&
                           tokyoMinute == 9 * 60 + 55);
   bool tokyoShortBuyWindow = (StrategyMode == 5 && TokyoEntryMinute == 590 &&
                               tokyoMinute == TokyoEntryMinute);
   bool londonEntryWindow =
      (StrategyMode == 7 && londonMinute == 16 * 60 + 5) ||
      (StrategyMode == 8 && TimeHour(now) * 60 + TimeMinute(now) == 14 * 60 + 45) ||
      (StrategyMode == 9 && TimeHour(now) * 60 + TimeMinute(now) == 15 * 60) ||
      (StrategyMode == 10 && londonMinute == 7 * 60);
   if(BreakoutTiming == 0 && !newBar && !tokyoSellWindow && !tokyoShortBuyWindow &&
      !londonEntryWindow && roundTickSide < 0 && asianSide < 0) return;
   // SL・手動決済も含め、履歴の並び順に依存せず最終決済時刻を取得する。
   for(int h = OrdersHistoryTotal() - 1; h >= 0; h--)
   {
      if(!OrderSelect(h, SELECT_BY_POS, MODE_HISTORY))
      {
         Print("History OrderSelect failed error=", GetLastError());
         return;
      }
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) && OrderCloseTime() > lastClose)
         lastClose = OrderCloseTime();
   }
   if(!IsTesting() && lastClose > 0)
   {
      GlobalVariableSet(statePrefix + ".close", lastClose);
      GlobalVariablesFlush();
   }
   lastBar = bar;
   exitTicket = -1;

   // Mode5後半は、同日09:55に完了した前半決済の休止と同バー制限を適用しない。
   if(lastClose > 0 && !(StrategyMode == 5 && tokyoSellWindow))
   {
      int closeShift = iBarShift(Symbol(), SignalTimeframe, lastClose, false);
      if(closeShift <= 0)
      {
         if(BreakoutTiming == 1) breakoutAttemptBar = bar;
         return;
      }
      int days = 0;
      for(int d = closeShift - 1; d >= 1 && days < CooldownDays; d--)
      {
         int weekday = TimeDayOfWeek(iTime(Symbol(), SignalTimeframe, d));
         if(weekday >= 1 && weekday <= 5) days++;
      }
      if(days < CooldownDays)
      {
         if(BreakoutTiming == 1) breakoutAttemptBar = bar;
         return;
      }
   }

   if(StrategyMode == 12)
   {
      int roundMinute = TimeHour(now) * 60 + TimeMinute(now);
      int roundWeekday = TimeDayOfWeek(now);
      if(roundWeekday == 0 || roundWeekday == 6 ||
         roundMinute < 16 * 60 + 30 || roundMinute > 22 * 60)
         return;
   }
   else if(StrategyMode == 11)
   {
      int roundMinute = TimeHour(bar) * 60 + TimeMinute(bar);
      int roundWeekday = TimeDayOfWeek(bar);
      if(now >= bar + 60 || roundWeekday == 0 || roundWeekday == 6 ||
         roundMinute < 16 * 60 + 30 || roundMinute > 22 * 60)
         return;
   }
   else if(StrategyMode >= 7 && StrategyMode <= 10)
   {
      int londonYear = TimeYear(londonNow);
      int londonMonth = TimeMonth(londonNow);
      int londonDay = TimeDay(londonNow);
      int londonWeekday = TimeDayOfWeek(londonNow);
      if(londonYear < 2017 || londonYear > 2027 ||
         londonWeekday == 0 || londonWeekday == 6 ||
         (StrategyMode != 10 && londonMonth == 12 &&
          (londonDay == 24 || londonDay == 31)) ||
         (StrategyMode != 10 &&
          StringFind(londonHolidays, "," + IntegerToString(londonDate) + ",") >= 0) ||
         !londonEntryWindow)
         return;
      if(lastLondonEntryDate != londonDate)
      {
         for(int londonHistory = OrdersHistoryTotal() - 1; londonHistory >= 0; londonHistory--)
         {
            if(!OrderSelect(londonHistory, SELECT_BY_POS, MODE_HISTORY))
            {
               Print("London history OrderSelect failed error=", GetLastError());
               return;
            }
            if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber ||
               (OrderType() != OP_BUY && OrderType() != OP_SELL)) continue;
            datetime londonHistoryOpen = OrderOpenTime();
            int historyServerDate = TimeYear(londonHistoryOpen) * 10000 +
                                    TimeMonth(londonHistoryOpen) * 100 + TimeDay(londonHistoryOpen);
            if(historyServerDate == londonDate)
            {
               lastLondonEntryDate = londonDate;
               break;
            }
         }
      }
      if(lastLondonEntryDate == londonDate) return;
   }
   else if(StrategyMode >= 3 && StrategyMode <= 5)
   {
      int tokyoYear = TimeYear(tokyoNow);
      int tokyoMonth = TimeMonth(tokyoNow);
      int tokyoDay = TimeDay(tokyoNow);
      int tokyoWeekday = TimeDayOfWeek(tokyoNow);
      bool tokyoEntryWindow =
         (StrategyMode == 3 && tokyoMinute == TokyoEntryMinute) ||
         (StrategyMode == 4 && tokyoMinute == 9 * 60 + 55) ||
         (StrategyMode == 5 && (tokyoMinute == TokyoEntryMinute || tokyoSellWindow));
      if(tokyoYear < 2017 || tokyoYear > 2027 || dstTransitionSunday ||
         tokyoWeekday == 0 || tokyoWeekday == 6 ||
         (tokyoMonth == 12 && tokyoDay == 31) ||
         (tokyoMonth == 1 && tokyoDay <= 3) ||
         StringFind(tokyoHolidays, "," + IntegerToString(tokyoDate) + ",") >= 0 ||
         !tokyoEntryWindow)
         return;
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
               return;
         }
      }
      if(SettlementDaysOnly == 2 && tokyoDay % 5 != 0)
      {
         bool rolledSettlement = false;
         // 次の営業日までの休業日に決済日があれば、今日に前倒しする。
         for(datetime rollDay = tokyoNow + 86400; ; rollDay += 86400)
         {
            int rollWeekday = TimeDayOfWeek(rollDay);
            int rollDate = TimeYear(rollDay) * 10000 + TimeMonth(rollDay) * 100 + TimeDay(rollDay);
            bool rollBankDay = rollWeekday != 0 && rollWeekday != 6 &&
               !(TimeMonth(rollDay) == 12 && TimeDay(rollDay) == 31) &&
               !(TimeMonth(rollDay) == 1 && TimeDay(rollDay) <= 3) &&
               StringFind(tokyoHolidays, "," + IntegerToString(rollDate) + ",") < 0;
            if(rollBankDay)
            {
               // 次の営業日が翌月なら、今日は従来どおり月末最終営業日。
               if(TimeMonth(rollDay) != tokyoMonth) rolledSettlement = true;
               break;
            }
            if(TimeDay(rollDay) % 5 == 0) rolledSettlement = true;
         }
         if(!rolledSettlement) return;
      }
      bool tokyoSellLeg = (StrategyMode == 4 || (StrategyMode == 5 && tokyoSellWindow));
      int lastTokyoLegDate = (StrategyMode == 5 && tokyoSellLeg ?
                              lastTokyoSellDate : lastTokyoEntryDate);
      if(lastTokyoLegDate != tokyoDate)
      {
         for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
         {
            if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
            {
               Print("Tokyo history OrderSelect failed error=", GetLastError());
               return;
            }
            if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
            if(StrategyMode == 5)
            {
               if(OrderType() != (tokyoSellLeg ? OP_SELL : OP_BUY)) continue;
            }
            else if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
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
               if(StrategyMode == 5 && tokyoSellLeg)
                  lastTokyoSellDate = tokyoDate;
               else
                  lastTokyoEntryDate = tokyoDate;
               break;
            }
         }
      }
      if((StrategyMode == 5 && tokyoSellLeg ? lastTokyoSellDate : lastTokyoEntryDate) == tokyoDate)
         return;
   }
   else
   {
      // 時間帯は発注を試みる現在バーの開始時刻で判定し、時間外は新規発注だけを見送る。
      if(TimeHour(bar) < EntryStartHour) return;
   }
   // M30境界外の時刻入口は指定分内で再判定し、他は当該バーを見送る。
   RefreshRates();
   long bidPoints = (long)MathRound(Bid / Point);
   long askPoints = (long)MathRound(Ask / Point);
   long spreadPoints = askPoints - bidPoints;
   double pointsPerPip = (Digits == 3 || Digits == 5 ? 10.0 : 1.0);
   // 端数pointは許容せず、入力上限を整数pointへ切り捨てる。
   long maxSpreadPoints = (long)MathFloor(MaxSpreadPips * pointsPerPip + 1e-9);
   if(spreadPoints > maxSpreadPoints) return;
   if(iBars(Symbol(), SignalTimeframe) <
      ((StrategyMode >= 3 && StrategyMode <= 5) ||
       (StrategyMode >= 7 && StrategyMode <= 14) ?
       ATRPeriod : MathMax(MathMax(EntryBars, ATRPeriod), TrendMAPeriod)) + 3)
      return;
   double atr = (BreakoutTiming == 1 ? breakoutCacheATR :
                 iATR(Symbol(), SignalTimeframe, ATRPeriod,
                      (StrategyMode == 14 ? 1 : 2)));
   if(atr <= 0) return;
   double close1 = 0;
   double upper = 0;
   double lower = 0;
   double deviationMean = 0;
   int side = -1;
   if(BreakoutTiming == 1)
   {
      upper = breakoutCacheUpper;
      lower = breakoutCacheLower;
      side = breakoutTickSide;
   }
   else if(StrategyMode >= 3 && StrategyMode <= 5)
   {
      side = (StrategyMode == 3 || (StrategyMode == 5 && !tokyoSellWindow) ?
              OP_BUY : OP_SELL);
      if(StrategyMode == 4 && PostFixDirection == 1)
         side = (postFixSignalDate == tokyoDate ? postFixSignalSide : -1);
   }
   else if(StrategyMode >= 7 && StrategyMode <= 10)
      side = (StrategyMode == 8 || StrategyMode == 10 ? OP_SELL : OP_BUY);
   else if(StrategyMode == 11)
   {
      if(iTime(Symbol(), SignalTimeframe, 1) != bar - 1800 ||
         iTime(Symbol(), SignalTimeframe, 2) != bar - 3600)
         return;
      double roundClose1 = iClose(Symbol(), SignalTimeframe, 1);
      double roundClose2 = iClose(Symbol(), SignalTimeframe, 2);
      long roundStep = (long)MathRound(0.50 / Point);
      long roundC1 = (long)MathRound(roundClose1 / Point);
      long roundC2 = (long)MathRound(roundClose2 / Point);
      if(roundClose1 <= 0 || roundClose2 <= 0 || roundStep <= 0 ||
         roundC1 <= 0 || roundC2 <= 0)
         return;
      if(roundC1 % roundStep == 0) return;
      long roundCount = 0;
      if(roundC1 > roundC2)
      {
         roundCount = (roundC1 - 1) / roundStep -
                      (roundC2 + roundStep - 1) / roundStep + 1;
         if(roundCount == 1) side = OP_BUY;
      }
      else if(roundC1 < roundC2)
      {
         roundCount = roundC2 / roundStep - roundC1 / roundStep;
         if(roundCount == 1) side = OP_SELL;
      }
   }
   else if(StrategyMode == 12 || StrategyMode == 13)
      side = roundTickSide;
   else if(StrategyMode == 14)
      side = asianSide;
   else if(StrategyMode == 6)
   {
      close1 = iClose(Symbol(), SignalTimeframe, 1);
      deviationMean = iMA(Symbol(), SignalTimeframe, EntryBars, 0, MODE_SMA, PRICE_CLOSE, 2);
      if(close1 <= 0 || deviationMean <= 0) return;
      if(close1 <= deviationMean - DeviationATR * atr) side = OP_BUY;
      if(close1 >= deviationMean + DeviationATR * atr) side = OP_SELL;
   }
   else
   {
      close1 = iClose(Symbol(), SignalTimeframe, 1);
      if(close1 <= 0) return;
      int upperShift = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, EntryBars, 2);
      int lowerShift = iLowest(Symbol(), SignalTimeframe, MODE_LOW, EntryBars, 2);
      if(upperShift < 0 || lowerShift < 0) return;
      upper = iHigh(Symbol(), SignalTimeframe, upperShift);
      lower = iLow(Symbol(), SignalTimeframe, lowerShift);
      if(StrategyMode == 1 && (upper <= 0 || lower <= 0 || lower >= upper)) return;
      if(StrategyMode == 0)
      {
         if(close1 > upper + BreakoutBufferATR * atr) side = OP_BUY;
         if(close1 < lower - BreakoutBufferATR * atr) side = OP_SELL;
      }
      else if(StrategyMode == 1 && close1 > lower && close1 < upper)
      {
         bool brokeUpper = iHigh(Symbol(), SignalTimeframe, 1) > upper + BreakoutBufferATR * atr;
         bool brokeLower = iLow(Symbol(), SignalTimeframe, 1) < lower - BreakoutBufferATR * atr;
         if(brokeUpper && !brokeLower) side = OP_SELL;
         if(brokeLower && !brokeUpper) side = OP_BUY;
      }
      else if(StrategyMode == 2)
      {
         double rsi = iRSI(Symbol(), SignalTimeframe, 2, PRICE_CLOSE, 1);
         if(rsi < 0 || rsi > 100) return;
         if(rsi <= RSIEntryLevel) side = OP_BUY;
         if(rsi >= 100.0 - RSIEntryLevel) side = OP_SELL;
      }
   }
   if(side < 0) return;
   if(StrategyMode == 1 && MinPathEfficiency > 0)
   {
      double pathRange = 0;
      for(int p = 2; p <= EntryBars + 1; p++)
      {
         double pathHigh = iHigh(Symbol(), SignalTimeframe, p);
         double pathLow = iLow(Symbol(), SignalTimeframe, p);
         double previousClose = iClose(Symbol(), SignalTimeframe, p + 1);
         if(pathHigh <= 0 || pathLow <= 0 || pathHigh < pathLow || previousClose <= 0) return;
         pathRange += MathMax(pathHigh - pathLow,
                              MathMax(MathAbs(pathHigh - previousClose), MathAbs(pathLow - previousClose)));
      }
      double pathClose = iClose(Symbol(), SignalTimeframe, 2);
      double pathStart = iClose(Symbol(), SignalTimeframe, EntryBars + 2);
      if(pathClose <= 0 || pathStart <= 0 || pathRange <= 0 ||
         MathAbs(pathClose - pathStart) / pathRange < MinPathEfficiency) return;
   }
   if(MinSignalRangeATR > 0 &&
      iHigh(Symbol(), SignalTimeframe, 1) - iLow(Symbol(), SignalTimeframe, 1) < MinSignalRangeATR * atr)
      return;
   if(TrendMAPeriod > 0)
   {
      double trendMA = iMA(Symbol(), SignalTimeframe, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
      if(trendMA <= 0 || (side == OP_BUY && close1 <= trendMA) ||
         (side == OP_SELL && close1 >= trendMA)) return;
   }

   // 固定ロット・ATR幅のSLで発注する。ストップ制約を満たせない場合は見送る。
   if(BreakoutTiming == 1)
   {
      RefreshRates();
      if(iTime(Symbol(), SignalTimeframe, 0) != bar || Bid <= 0 || Ask <= 0 || Ask < Bid)
         return;
      long breakoutBidPoints = (long)MathRound(Bid / Point);
      long breakoutAskPoints = (long)MathRound(Ask / Point);
      long breakoutSpreadPoints = breakoutAskPoints - breakoutBidPoints;
      if(breakoutSpreadPoints > maxSpreadPoints) return;
      if((side == OP_BUY &&
          Bid <= breakoutCacheUpper + BreakoutBufferATR * breakoutCacheATR) ||
         (side == OP_SELL &&
          Bid >= breakoutCacheLower - BreakoutBufferATR * breakoutCacheATR))
         return;
   }
   if(StrategyMode == 13)
   {
      RefreshRates();
      datetime roundNow = TimeCurrent();
      int roundDate = TimeYear(roundNow) * 10000 + TimeMonth(roundNow) * 100 + TimeDay(roundNow);
      int signalRoundDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int roundMinute = TimeHour(roundNow) * 60 + TimeMinute(roundNow);
      int roundWeekday = TimeDayOfWeek(roundNow);
      long roundBidPoints = (long)MathRound(Bid / Point);
      long roundAskPoints = (long)MathRound(Ask / Point);
      long roundSpreadPoints = roundAskPoints - roundBidPoints;
      long roundStep = (long)MathRound(1.00 / Point);
      if(iTime(Symbol(), SignalTimeframe, 0) != bar || roundDate != signalRoundDate ||
         roundWeekday == 0 || roundWeekday == 6 || roundMinute < 16 * 60 ||
         roundMinute >= 22 * 60 + 30 || Bid <= 0 || Ask <= 0 || Ask < Bid ||
         roundSpreadPoints > maxSpreadPoints || roundStep <= 0 || roundTickLevel <= 0)
         return;
      if((side == OP_SELL &&
          (roundBidPoints < roundTickLevel || roundBidPoints >= roundTickLevel + roundStep)) ||
         (side == OP_BUY &&
          (roundAskPoints > roundTickLevel || roundAskPoints <= roundTickLevel - roundStep)))
         return;
   }
   if(StrategyMode == 14)
   {
      RefreshRates();
      datetime asianNow = TimeCurrent();
      datetime currentLondon = asianNow + (londonNow - now);
      int asianDate = TimeYear(asianNow) * 10000 + TimeMonth(asianNow) * 100 + TimeDay(asianNow);
      int signalAsianDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int currentLondonDate = TimeYear(currentLondon) * 10000 +
                              TimeMonth(currentLondon) * 100 + TimeDay(currentLondon);
      int asianMinute = TimeHour(asianNow) * 60 + TimeMinute(asianNow);
      int currentLondonMinute = TimeHour(currentLondon) * 60 + TimeMinute(currentLondon);
      int currentLondonWeekday = TimeDayOfWeek(currentLondon);
      long asianBidPoints = (long)MathRound(Bid / Point);
      long asianAskPoints = (long)MathRound(Ask / Point);
      if(iTime(Symbol(), SignalTimeframe, 0) != bar || asianDate != signalAsianDate ||
         asianRangeDate != asianDate || currentLondonDate != asianDate ||
         currentLondonWeekday == 0 || currentLondonWeekday == 6 ||
         currentLondonMinute < 7 * 60 || asianMinute >= 15 * 60 ||
         Bid <= 0 || Ask <= 0 || Ask < Bid || asianAskPoints - asianBidPoints > maxSpreadPoints)
         return;
      if((side == OP_BUY && Bid <= asianRangeUpper) ||
         (side == OP_SELL && Bid >= asianRangeLower))
         return;
   }
   double entry = (side == OP_BUY ? Ask : Bid);
   double stop = entry + (side == OP_BUY ? -1.0 : 1.0) * StopATR * atr;
   stop = NormalizeDouble((side == OP_BUY ? MathFloor(stop / tick) : MathCeil(stop / tick)) * tick,
                          Digits);
   double minDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point + tick;
   if(stop <= 0 || (side == OP_BUY && Bid - stop < minDistance) ||
      (side == OP_SELL && stop - Ask < minDistance)) return;
   double takeProfit = 0;
   if(StrategyMode == 1 || StrategyMode == 2 || StrategyMode == 6)
   {
      double targetPrice = (StrategyMode == 1 ? (upper + lower) / 2.0 :
                            (StrategyMode == 6 ? deviationMean :
                             iMA(Symbol(), SignalTimeframe, EntryBars, 0, MODE_SMA, PRICE_CLOSE, 2)));
      if(targetPrice <= 0) return;
      takeProfit = NormalizeDouble(MathRound(targetPrice / tick) * tick, Digits);
      if((side == OP_BUY && (takeProfit <= Ask || takeProfit - Ask < minDistance)) ||
         (side == OP_SELL && (takeProfit >= Bid || Bid - takeProfit < minDistance))) return;
   }
   ResetLastError();
   double freeAfter = AccountFreeMarginCheck(Symbol(), side, FixedLots);
   if(GetLastError() != 0 || freeAfter <= 0)
   {
      Print("Entry skipped: insufficient margin for FixedLots=", FixedLots);
      return;
   }
   string orderComment = (StrategyMode == 0 ? "STR03 Donchian " :
                          (StrategyMode == 1 ? "STR03 FailedBreak " :
                           (StrategyMode == 2 ? "STR03 TrendPullback " :
                            (StrategyMode == 3 ? "STR03 TokyoFix " :
                             (StrategyMode == 4 ? "STR03 PostFix " :
                              (side == OP_BUY ? "STR03 TokyoRoundBuy " :
                                                "STR03 TokyoRoundSell ")))))) +
                         IntegerToString(SignalTimeframe);
   if(StrategyMode == 6)
      orderComment = "STR03 ATRRevert " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 7)
      orderComment = "STR03 LondonFix " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 8)
      orderComment = "STR03 PreNY08 " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 9)
      orderComment = "STR03 PostNY08 " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 10)
      orderComment = "STR03 London0700 " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 11)
      orderComment = "STR03 RoundCascade " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 12)
      orderComment = "STR03 TickCascade " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 13)
      orderComment = "STR03 RoundReversal " + IntegerToString(SignalTimeframe);
   if(StrategyMode == 14)
      orderComment = "STR03 AsianRange " + IntegerToString(SignalTimeframe);
   // 処理中に指定分を過ぎた場合も、遅刻発注は行わない。
   if((StrategyMode == 4 || StrategyMode == 5 ||
       (StrategyMode >= 7 && StrategyMode <= 10)) &&
      TimeCurrent() >= now - TimeSeconds(now) + 60) return;
   if(StrategyMode == 11 && TimeCurrent() >= bar + 60) return;
   if(StrategyMode == 12)
   {
      datetime sendNow = TimeCurrent();
      int sendDate = TimeYear(sendNow) * 10000 + TimeMonth(sendNow) * 100 + TimeDay(sendNow);
      int signalDate = TimeYear(now) * 10000 + TimeMonth(now) * 100 + TimeDay(now);
      int sendMinute = TimeHour(sendNow) * 60 + TimeMinute(sendNow);
      if(sendDate != signalDate || sendMinute < 16 * 60 + 30 || sendMinute > 22 * 60)
         return;
   }
   if(BreakoutTiming == 1)
   {
      if(iTime(Symbol(), SignalTimeframe, 0) != bar) return;
      breakoutAttemptBar = bar;
      if(!IsTesting())
      {
         ResetLastError();
         if(GlobalVariableSet(statePrefix + ".breakbar", breakoutAttemptBar) == 0)
         {
            Print("Breakout attempt state save failed error=", GetLastError());
            return;
         }
         GlobalVariablesFlush();
      }
   }
   if(StrategyMode == 13)
   {
      if(iTime(Symbol(), SignalTimeframe, 0) != bar) return;
      roundAttemptBar = bar;
      if(!IsTesting())
      {
         ResetLastError();
         if(GlobalVariableSet(statePrefix + ".roundbar", roundAttemptBar) == 0)
         {
            Print("Round attempt state save failed error=", GetLastError());
            return;
         }
         GlobalVariablesFlush();
      }
   }
   if(StrategyMode == 14)
   {
      if(iTime(Symbol(), SignalTimeframe, 0) != bar) return;
      asianAttemptDate = asianRangeDate;
      if(!IsTesting())
      {
         ResetLastError();
         if(GlobalVariableSet(statePrefix + ".asiaday", asianAttemptDate) == 0)
         {
            Print("Asian attempt state save failed error=", GetLastError());
            return;
         }
         GlobalVariablesFlush();
      }
   }
   int ticket = OrderSend(Symbol(), side, FixedLots, entry, Slippage, stop, takeProfit,
                          orderComment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      int error = GetLastError();
      Print("Entry failed error=", error);
      // 休場・売買禁止・価格変更・配信停止・再クオート・取引処理中は後続ティックを待つ。
      if(BreakoutTiming == 0 && StrategyMode != 13 && StrategyMode != 14 &&
         (error == 132 || error == 133 || error == 135 || error == 136 ||
          error == 138 || error == 146)) lastBar = 0;
      return;
   }
   stopTicket = ticket;
   stopDistance = StopATR * atr;
   heldTicket = ticket;
   if(StrategyMode == 5 && side == OP_SELL)
      lastTokyoSellDate = tokyoDate;
   else if(StrategyMode >= 3 && StrategyMode <= 5)
      lastTokyoEntryDate = tokyoDate;
   else if(StrategyMode >= 7 && StrategyMode <= 10)
      lastLondonEntryDate = londonDate;
   exitCheckedBar = iTime(Symbol(), SignalTimeframe, 1);
   if(!IsTesting())
   {
      string sentPrefix = statePrefix + "." + IntegerToString(ticket);
      GlobalVariableSet(statePrefix + ".held", ticket);
      if(StrategyMode == 5 && side == OP_SELL)
         GlobalVariableSet(statePrefix + ".tokyosell", lastTokyoSellDate);
      else if(StrategyMode >= 3 && StrategyMode <= 5)
         GlobalVariableSet(statePrefix + ".tokyo", lastTokyoEntryDate);
      else if(StrategyMode >= 7 && StrategyMode <= 10)
         GlobalVariableSet(statePrefix + ".london", lastLondonEntryDate);
      if(GlobalVariableSet(sentPrefix + ".stop", stopDistance) == 0)
         Print("SL state save failed ticket=", ticket, " error=", GetLastError());
      GlobalVariableSet(sentPrefix + ".eval", exitCheckedBar);
      GlobalVariablesFlush();
   }
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("Fill OrderSelect failed ticket=", ticket, " error=", GetLastError());
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
         else Print("SL correction failed ticket=", ticket, " error=", GetLastError());
      }
   }
}
