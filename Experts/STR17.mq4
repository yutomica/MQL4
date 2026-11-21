//+------------------------------------------------------------------+
//|                                                        STR17.mq4 |
//|                         圧縮レンジ・仮想OCO成行EA
//+------------------------------------------------------------------+

/*
売買ロジック（対象通貨ペア：TradeSymbol、判定時間足：SignalTimeframe）
- En:
  新しいSignalTimeframeの足の最初の価格更新で、直近の確定足QuietBars本の平均値幅が、その前のReferenceBars本の平均値幅×CompressionRatio未満なら、値動きが小さくなったと判断し、その足の間だけ新規注文を待つ。
  値幅にはTR（高値－安値、高値と前足終値の差の絶対値、安値と前足終値の差の絶対値の最大値）を使う。
  直近の確定足RangeBars本の最高値・最安値を基準とし、Bidが最高値以上になれば買い、最安値以下になれば売る。
  最初に到達した方向へ成行注文する（買いはAsk、売りはBid）。価格が飛び越えた場合も対象。
  新規注文は月～金のUTC午前0時からの経過分がEntryStartUTC以上EntryEndUTC未満、かつTradeStartTime（サーバー時刻）以降に限る。
  1日の新規発注回数に上限を設けない。最初の到達でその足の機会を使い切り、見送り・発注失敗でも同じ足では入り直さない。
  注文の順番待ちだけは同じSignalTimeframeの足・取引時間内で継続し、発注時の価格と資金でSL・TP・ロットを計算する。
  発注結果が不明な場合は日付や足の更新では解除せず、新規発注を停止する。実運用では停止印を保存し、注文結果の確認・停止印の解除・EA再初期化まで停止を継続する。既存建玉の決済は継続する。
  スプレッドがMaxSpreadPips（pips）を超える場合など、発注条件を満たさなければ見送る。
  足の開始時に保有中、同じ足で決済済み、または価格データ不足なら、その足では待機しない。
  再起動時は建玉・注文履歴から保有と同じ足での決済を確認し、次のSignalTimeframeの足から判定する（テストは先頭足から）。
- Ex:
  エントリーした足から数えてHoldBars本後のSignalTimeframeの足に入ったら決済する。
  金曜のUTC午前0時からFridayExitUTC分以降または土日も決済対象とする。日付が変わっただけでは決済しない。
  決済に失敗した場合は要求を保持し、5秒以上空けて再試行する。
- SL/TP:
  新規注文を待ち始める時点で、直近の確定足ATRPeriod本のTRの単純平均をATRとして固定する。
  発注価格から不利な方向へATR×StopATR離れた位置に損切り（SL）を設定する。
  利確（TP）はTakeProfitATRが0なら設けず、正の場合だけ発注価格から有利な方向へATR×TakeProfitATR離れた位置に設定する。
  SL・TPは発注価格から遠ざかる方向に取引可能な価格単位へ丸める。トレーリング・部分決済は行わない。
- ポジション数・ロット:
  同じ通貨ペア・MAGICでは最大1注文。日次の回数制限は設けない。
  決済したSignalTimeframeの足では再エントリーしない。
  残高と有効証拠金の小さい方を資金とし、SLまでの計算上の損失が資金のEntryRiskPercent%以下になるロット数とする。
  ロット数は取引単位で切り下げ、業者の上限を適用する。最小ロット未満なら見送る。
  発注後の余剰証拠金が資金の30%未満になる場合も見送る。テスト時は日次の有効証拠金をCSVに記録する。
*/

#property strict
#property description "H1圧縮レンジ・仮想OCO成行・固定TR平均ATR。"

#include <Original/TradeControl.mqh>
#include <Original/Mail.mqh>

#define MAGIC 2026101717
#define COMMENT "STR17"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
sinput string TradeSymbol = "USDJPY";
sinput double EntryRiskPercent = 0.25;
sinput double MaxSpreadPips = 2.0;
sinput int Slippage = 20; // point
sinput int FridayExitUTC = 1200;
sinput int BrokerWinterUTCOffset = 2;
sinput int BrokerSummerUTCOffset = 3;
sinput bool UseUSDST = true;
sinput string EquityFileName = "";
sinput datetime TradeStartTime = 0; // サーバー時刻。履歴準備中の新規注文を抑止する。
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_H1;
input int ATRPeriod = 14;
input int ReferenceBars = 60;
input int QuietBars = 3;
input double CompressionRatio = 0.9;
input int RangeBars = 10;
input double StopATR = 3.0;
input int HoldBars = 18;
input int EntryStartUTC = 60;
input int EntryEndUTC = 1200;
input double TakeProfitATR = 0.0; // 0は固定利確なし

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
string gLogIdentity = "", gExitPrefix = "", gEntryPendingKey = "";
datetime gLastBar = 0, gLastTick = 0;
double gLastEquity = 0, gLastBalance = 0, gPeakEquity = 0;
double gMaxDDMoney = 0, gMaxDDPercent = 0;
int gEquityFile = INVALID_HANDLE;
datetime gLastExitBar = 0;
datetime gArmedBar = 0;
double gArmedATR = 0, gArmedUpper = 0, gArmedLower = 0;
bool gEntryReady = false, gStateHealthy = true, gEntryUncertain = false;
int gExitTickets[];
uint gExitRetryTimes[];
bool gExitRetried[];
bool gReleasePending=false, gRestorePending=true;
int gInstanceHandle=INVALID_HANDLE;
int gEntrySide=-1;
datetime gEntryBar=0;
long gEntryDay=-1;
double gEntryStop=0, gEntryTarget=0, gEntryLots=0, gEntryATR=0;

//+------------------------------------------------------------------+
int OnInit()
{
   gLastBar=0;gLastTick=0;gLastExitBar=0;
   gArmedBar=0;gEntrySide=-1;gEntryBar=0;gEntryDay=-1;gStateHealthy=true;gRestorePending=true;gReleasePending=false;
   gMaxDDMoney=0;gMaxDDPercent=0;
   ArrayResize(gExitTickets,0);ArrayResize(gExitRetryTimes,0);ArrayResize(gExitRetried,0);
   gLogIdentity="ea="+COMMENT+" symbol="+Symbol()+
      " tf="+StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()),7)+
      " magic="+IntegerToString(MAGIC)+" chart="+IntegerToString(ChartID())+
      " session="+IntegerToString((long)TimeLocal())+"-"+IntegerToString((long)GetTickCount())+" ";
   Print(gLogIdentity,"event=INIT_BEGIN compiled=",__DATETIME__);
   bool allowedTF=(SignalTimeframe==PERIOD_H1 || SignalTimeframe==PERIOD_M30 || SignalTimeframe==PERIOD_M15);
   bool allowedSymbol=(TradeSymbol=="USDJPY" || TradeSymbol=="EURJPY" || TradeSymbol=="GBPJPY" || TradeSymbol=="EURUSD" || TradeSymbol=="AUDJPY");
   if(!allowedTF || !allowedSymbol || (!IsTesting() && Period()!=SignalTimeframe) || StringSubstr(Symbol(),0,6)!=TradeSymbol ||
      ATRPeriod<1 || QuietBars<1 || ReferenceBars<1 || RangeBars<1 || CompressionRatio<=0 || StopATR<=0 || TakeProfitATR<0 ||
      !MathIsValidNumber(CompressionRatio) || !MathIsValidNumber(StopATR) || !MathIsValidNumber(TakeProfitATR) ||
      !MathIsValidNumber(EntryRiskPercent) || !MathIsValidNumber(MaxSpreadPips) ||
      HoldBars<1 || EntryRiskPercent<=0 || EntryRiskPercent>0.5 || MaxSpreadPips<=0 || Slippage<0 ||
      EntryStartUTC<0 || EntryEndUTC>1440 || EntryStartUTC>=EntryEndUTC || FridayExitUTC<0 || FridayExitUTC>=1440 ||
      BrokerWinterUTCOffset < -12 || BrokerWinterUTCOffset>14 || BrokerSummerUTCOffset < -12 || BrokerSummerUTCOffset>14)
      return(INIT_PARAMETERS_INCORRECT);
   if(!TC_Init(2000)) return(INIT_FAILED);
   if(!IsTesting())
   {
      ResetLastError();
      gInstanceHandle=FileOpen("EA.instance."+MailScope(MAGIC)+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(gInstanceHandle==INVALID_HANDLE)
      {Print(gLogIdentity,"event=INSTANCE_LOCK_FAILED error=",GetLastError());return(INIT_FAILED);}
   }
   string scope=AccountServer()+"|"+Symbol();
   uint scopeHash=2166136261;
   for(int k=0;k<StringLen(scope);k++) scopeHash=(scopeHash^(uint)StringGetCharacter(scope,k))*16777619;
   gExitPrefix=COMMENT+".X."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+".";
   gEntryPendingKey=gExitPrefix+"ENTRY_PENDING";
   gEntryUncertain=(!IsTesting() && GlobalVariableCheck(gEntryPendingKey));
   if(gEntryUncertain) Print(gLogIdentity,"event=ENTRY_UNCERTAIN_BLOCKED key=",gEntryPendingKey," action=verify_order_result_before_clearing_marker");
   // 建玉・履歴はTickで再読する。復元障害でも既存建玉の出口を停止しない。
   gEntryReady=IsTesting();
   gPeakEquity=AccountEquity();
   if(IsTesting())
   {
      string name=(StringLen(EquityFileName)>0 ? EquityFileName : COMMENT+"_equity.csv");
      gEquityFile=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(gEquityFile==INVALID_HANDLE) {Print(gLogIdentity,"event=EQUITY_FILE_OPEN_FAILED error=",GetLastError());return(INIT_FAILED);}
      if(FileWrite(gEquityFile,"time","equity","balance")==0)
      {Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());return(INIT_FAILED);}
   }
   Print(gLogIdentity,"event=INIT_OK timezone=US_DST winter_utc_offset=",BrokerWinterUTCOffset,
         " summer_utc_offset=",BrokerSummerUTCOffset," driver_tf=",Period()," signal_tf=",SignalTimeframe," trade_start=",TimeToString(TradeStartTime,TIME_DATE|TIME_MINUTES),
         " trade_start_epoch=",(long)TradeStartTime,
         " swap_type=",MarketInfo(Symbol(),MODE_SWAPTYPE)," swap_long=",MarketInfo(Symbol(),MODE_SWAPLONG),
         " swap_short=",MarketInfo(Symbol(),MODE_SWAPSHORT));
   MailReconcile(COMMENT,MAGIC);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gReleasePending) gReleasePending=!TC_End(true);
   if(gEquityFile!=INVALID_HANDLE)
   {
      if(gLastTick>0 && FileWrite(gEquityFile,TimeToString(gLastTick,TIME_DATE|TIME_SECONDS),
         DoubleToString(AccountEquity(),2),DoubleToString(AccountBalance(),2))==0)
         Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());
      FileClose(gEquityFile);gEquityFile=INVALID_HANDLE;
   }
   if(gInstanceHandle!=INVALID_HANDLE) {FileClose(gInstanceHandle);gInstanceHandle=INVALID_HANDLE;}
   Print(gLogIdentity,"event=DEINIT reason=",reason," currency=",AccountCurrency(),
         " tick_size=",DoubleToString(SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE),Digits),
         " tick_value=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8)," max_dd_money=",DoubleToString(gMaxDDMoney,2),
         " max_dd_percent=",DoubleToString(gMaxDDPercent,4));
}

//+------------------------------------------------------------------+
void OnTick()
{
   MailReconcile(COMMENT,MAGIC);
   datetime now=TimeCurrent();
   int y=TimeYear(now-BrokerWinterUTCOffset*3600);
   datetime mar=StrToTime(IntegerToString(y)+".03.01 09:00"),nov=StrToTime(IntegerToString(y)+".11.01 09:00");
   datetime ds=mar+(7-TimeDayOfWeek(mar))%7*86400+7*86400,de=nov+(7-TimeDayOfWeek(nov))%7*86400;
   int utcOffset=BrokerWinterUTCOffset;
   if(UseUSDST && now>=ds && now<de) utcOffset=BrokerSummerUTCOffset;
   datetime nowUTC=now-utcOffset*3600;
   int utcMinute=TimeHour(nowUTC)*60+TimeMinute(nowUTC);
   bool weekendFlat=(TimeDayOfWeek(nowUTC)==5 && utcMinute>=FridayExitUTC) || TimeDayOfWeek(nowUTC)==6 || TimeDayOfWeek(nowUTC)==0;

   long utcDay=(long)nowUTC/86400;

   double eq=AccountEquity();
   if(gPeakEquity<=0 || eq>gPeakEquity) gPeakEquity=eq;
   double dd=gPeakEquity-eq,ddp=(gPeakEquity>0 ? dd/gPeakEquity*100.0 : 0);
   if(dd>gMaxDDMoney) gMaxDDMoney=dd;
   if(ddp>gMaxDDPercent) gMaxDDPercent=ddp;
   if(gEquityFile!=INVALID_HANDLE && gLastTick>0 && (long)now/86400!=(long)gLastTick/86400 &&
      FileWrite(gEquityFile,TimeToString(gLastTick,TIME_DATE|TIME_SECONDS),DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2))==0)
      Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());
   gLastTick=now;gLastEquity=eq;gLastBalance=AccountBalance();

   if(gReleasePending) gReleasePending=!TC_End(true);
   if(gReleasePending) return; // 注文を再送せず、完了記録の解放だけを再試行する。
   datetime bar=(datetime)((long)now/PeriodSeconds(SignalTimeframe)*PeriodSeconds(SignalTimeframe));
   if(!gEntryReady){gLastBar=bar;gEntryReady=true;}
   int requiredTRBars=(int)MathMax(MathMax(QuietBars+ReferenceBars,ATRPeriod),RangeBars);
   int requiredBars=requiredTRBars+2;
   bool seriesReady=(iTime(Symbol(),SignalTimeframe,0)==bar && iBars(Symbol(),SignalTimeframe)>=requiredBars && bar>0 &&
                     iTime(Symbol(),SignalTimeframe,requiredBars-1)>0);
   // 新H1初tickを消費し、その時点で系列不足なら途中から有効化しない。
   bool newBar=(bar>0 && bar!=gLastBar);
   if(newBar){gLastBar=bar;gArmedBar=0;gEntrySide=-1;}
   if(gEntrySide>=0 && (gEntryBar!=bar || now>=gEntryBar+PeriodSeconds(SignalTimeframe) || utcDay!=gEntryDay ||
      weekendFlat || utcMinute<EntryStartUTC || utcMinute>=EntryEndUTC)) gEntrySide=-1;
   // 復元・新規判定より先に既存建玉の決済を処理する。
   bool occupied=false,closedThisTick=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {Print(gLogIdentity,"event=ORDER_SELECT_FAILED error=",GetLastError());gStateHealthy=false;gRestorePending=true;occupied=true;continue;}
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC) continue;
      occupied=true;gEntrySide=-1;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      int ticket=OrderTicket(),side=OrderType();
      int held=iBarShift(Symbol(),SignalTimeframe,OrderOpenTime(),false);
      bool mustExit=(held>=HoldBars || weekendFlat);
      string key=gExitPrefix+IntegerToString(ticket);
      int pending=-1;
      for(int j=0;j<ArraySize(gExitTickets);j++) if(gExitTickets[j]==ticket) pending=j;
      bool saved=(!IsTesting() && GlobalVariableCheck(key));
      if(!mustExit && pending<0 && !saved) continue;
      if(pending<0)
      {
         int size=ArraySize(gExitTickets);
         bool retryResized=(ArrayResize(gExitRetryTimes,size+1)==size+1);
         bool ticketResized=(ArrayResize(gExitTickets,size+1)==size+1);
         bool flagResized=(ArrayResize(gExitRetried,size+1)==size+1);
         if(!retryResized || !ticketResized || !flagResized)
         {ArrayResize(gExitTickets,size);ArrayResize(gExitRetryTimes,size);ArrayResize(gExitRetried,size);gStateHealthy=false;gRestorePending=true;Print(gLogIdentity,"event=EXIT_REQUEST_RETAIN_FAILED ticket=",ticket);continue;}
         pending=size;gExitTickets[pending]=ticket;gExitRetryTimes[pending]=0;gExitRetried[pending]=false;
      }
      if(!IsTesting() && !saved)
      {
         ResetLastError();
         if(GlobalVariableSet(key,1.0)==0){gStateHealthy=false;gRestorePending=true;Print(gLogIdentity,"event=EXIT_STATE_SAVE_FAILED ticket=",ticket," error=",GetLastError());}
         else GlobalVariablesFlush();
      }
      uint retryClock=(IsTesting() ? (uint)now : GetTickCount());
      if(gExitRetried[pending] && (uint)(retryClock-gExitRetryTimes[pending])<(uint)(IsTesting() ? 5 : 5000)) continue;
      if(gReleasePending || !IsTradeAllowed() || (!IsTesting() && !IsConnected()) || !TC_Begin()) continue;
      ResetLastError();
      RefreshRates(); // false also means the quotes are already current.
      ResetLastError();
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){int error=GetLastError();TC_End(false);Print(gLogIdentity,"event=EXIT_SELECT_FAILED ticket=",ticket," error=",error);gStateHealthy=false;gRestorePending=true;continue;}
      if(OrderCloseTime()!=0 || OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || OrderType()!=side) {TC_End(false);continue;}
      double exitPrice = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      if(exitPrice<=0 || !MathIsValidNumber(exitPrice) || freeze<0) {TC_End(false);continue;}
      if(freeze > 0 &&
         ((OrderStopLoss() > 0 && (side == OP_BUY ? exitPrice - OrderStopLoss() : OrderStopLoss() - exitPrice) <= freeze) ||
          (OrderTakeProfit() > 0 && (side == OP_BUY ? OrderTakeProfit() - exitPrice : exitPrice - OrderTakeProfit()) <= freeze)))
         {TC_End(false);continue;} // 凍結制約の解消まで決済要求を保持する。
      ResetLastError();
      bool closed=OrderClose(ticket,OrderLots(),side==OP_BUY ? Bid : Ask,Slippage,clrNONE);
      int error=GetLastError();
      gReleasePending=!TC_End(true);
      gExitRetryTimes[pending]=(IsTesting() ? (uint)TimeCurrent() : GetTickCount());gExitRetried[pending]=true;
      if(!closed)
         Print(gLogIdentity,"event=EXIT_FAILED ticket=",ticket," error=",error," retry_after_seconds=5");
      else
      {
         closedThisTick=true;gLastExitBar=bar;
         Print(gLogIdentity,"event=EXIT_OK ticket=",ticket," side=",side==OP_BUY ? "BUY" : "SELL",
               " held_bars=",held," weekend_flat=",weekendFlat);
         int last=ArraySize(gExitTickets)-1;
         gExitTickets[pending]=gExitTickets[last];gExitRetryTimes[pending]=gExitRetryTimes[last];gExitRetried[pending]=gExitRetried[last];
         ArrayResize(gExitTickets,last);ArrayResize(gExitRetryTimes,last);ArrayResize(gExitRetried,last);
         if(!IsTesting() && GlobalVariableCheck(key))
         {if(!GlobalVariableDel(key)) Print(gLogIdentity,"event=EXIT_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
      }
   }

   if(gReleasePending) return;
   // 新しいSignalTimeframeの足で建玉・履歴を整合し、一時的な読取り障害から復帰する。
   if(newBar || gRestorePending)
   {
      bool recovered=true;
      for(int pool=0;pool<2;pool++)
      {
         int total=(pool==0 ? OrdersTotal() : OrdersHistoryTotal());
         for(int j=0;j<total;j++)
         {
            if(!OrderSelect(j,SELECT_BY_POS,pool==0 ? MODE_TRADES : MODE_HISTORY)) {recovered=false;continue;}
            if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
            if(OrderCloseTime()>=bar) gLastExitBar=bar;
         }
      }
      gStateHealthy=recovered;gRestorePending=false;
      if(!recovered) {gArmedBar=0;gEntrySide=-1;Print(gLogIdentity,"event=STATE_RESTORE_FAILED retry=next_H1");}
   }

   if(gArmedBar>0 && (gArmedBar!=bar || occupied || closedThisTick || gLastExitBar>=bar ||
      weekendFlat || utcMinute<EntryStartUTC || utcMinute>=EntryEndUTC || now<TradeStartTime))
      gArmedBar=0;
   if(newBar && seriesReady && !occupied && !closedThisTick && gStateHealthy && !gEntryUncertain &&
      now>=TradeStartTime && !weekendFlat && utcMinute>=EntryStartUTC && utcMinute<EntryEndUTC &&
      gLastExitBar<bar)
   {
      double quietTR=0.0,referenceTR=0.0,atrTR=0.0,upper=0.0,lower=0.0;
      bool valid=true;
      for(int shift=1;shift<=requiredTRBars;shift++)
      {
         datetime stamp=iTime(Symbol(),SignalTimeframe,shift);
         datetime previousStamp=iTime(Symbol(),SignalTimeframe,shift+1);
         double hi=iHigh(Symbol(),SignalTimeframe,shift),lo=iLow(Symbol(),SignalTimeframe,shift);
         double previousClose=iClose(Symbol(),SignalTimeframe,shift+1);
         if(stamp<=0 || stamp+PeriodSeconds(SignalTimeframe)>now || previousStamp<=0 || previousStamp>=stamp ||
            hi<=0 || lo<=0 || hi<lo || previousClose<=0 ||
            !MathIsValidNumber(hi) || !MathIsValidNumber(lo) || !MathIsValidNumber(previousClose))
         {valid=false;break;}
         double tr=MathMax(hi-lo,MathMax(MathAbs(hi-previousClose),MathAbs(lo-previousClose)));
         if(!MathIsValidNumber(tr)){valid=false;break;}
         if(shift<=QuietBars) quietTR+=tr;
         else if(shift<=QuietBars+ReferenceBars) referenceTR+=tr;
         if(shift<=ATRPeriod) atrTR+=tr;
         if(shift<=RangeBars)
         {
            if(shift==1){upper=hi;lower=lo;}
            else{upper=MathMax(upper,hi);lower=MathMin(lower,lo);}
         }
      }
      if(valid && atrTR>0 && referenceTR>0 && upper>lower &&
         quietTR/QuietBars<CompressionRatio*referenceTR/ReferenceBars)
      {
         gArmedBar=bar;gArmedATR=atrTR/ATRPeriod;gArmedUpper=upper;gArmedLower=lower;
         Print(gLogIdentity,"event=ARMED bar=",TimeToString(gArmedBar,TIME_DATE|TIME_MINUTES),
               " upper=",DoubleToString(gArmedUpper,Digits)," lower=",DoubleToString(gArmedLower,Digits),
               " atr=",DoubleToString(gArmedATR,Digits));
      }
   }
   if(occupied || closedThisTick || !gStateHealthy || gEntryUncertain) return;
   if(gEntrySide<0)
   {
      if(gArmedBar<=0) return;
      RefreshRates();
      if(Bid<=0 || !MathIsValidNumber(Bid)) return;
      int side=-1;
      if(Bid>=gArmedUpper) side=OP_BUY;
      else if(Bid<=gArmedLower) side=OP_SELL;
      if(side<0) return;
      datetime signalBar=gArmedBar;
      double signalATR=gArmedATR;
      // 最初の境界到達でこの足の機会を消費する。次の足では再判定できる。
      gArmedBar=0;
      Print(gLogIdentity,"event=TRIGGER side=",side==OP_BUY ? "BUY" : "SELL",
            " bar=",TimeToString(signalBar,TIME_DATE|TIME_MINUTES)," utc_day=",utcDay);
      if(!IsTesting() && (!IsConnected() || !IsExpertEnabled() || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=trade_unavailable utc_day=",utcDay);return;}
      double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
      if(Ask<=Bid || !MathIsValidNumber(Ask) || Ask-Bid>MaxSpreadPips*pip+Point*1e-6)
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=spread utc_day=",utcDay);return;}
      double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
      if(tick<=0) tick=Point;
      double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
      double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
      if(tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot ||
         !MathIsValidNumber(tick) || !MathIsValidNumber(tv) || !MathIsValidNumber(step) ||
         !MathIsValidNumber(minLot) || !MathIsValidNumber(maxLot))
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=symbol_properties utc_day=",utcDay);return;}
      double entry=(side==OP_BUY ? Ask : Bid);
      double stop=entry+(side==OP_BUY ? -StopATR : StopATR)*signalATR;
      double target=0;
      if(TakeProfitATR>0) target=entry+(side==OP_BUY ? TakeProfitATR : -TakeProfitATR)*signalATR;
      stop=NormalizeDouble((side==OP_BUY ? MathFloor(stop/tick) : MathCeil(stop/tick))*tick,Digits);
      if(TakeProfitATR>0) target=NormalizeDouble((side==OP_BUY ? MathCeil(target/tick) : MathFloor(target/tick))*tick,Digits);
      double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
      if(stop<=0 || (TakeProfitATR>0 && target<=0) ||
         (side==OP_BUY && (Bid-stop<minDist || (TakeProfitATR>0 && target-Bid<minDist))) ||
         (side==OP_SELL && (stop-Ask<minDist || (TakeProfitATR>0 && Ask-target<minDist))))
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=stop_distance utc_day=",utcDay);return;}
      double capital=MathMin(AccountBalance(),AccountEquity()),risk=MathAbs(entry-stop)/tick*tv;
      if(capital<=0 || risk<=0)
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=capital utc_day=",utcDay);return;}
      double lots=MathMin(capital*EntryRiskPercent/100.0/risk,maxLot);
      lots=NormalizeDouble(MathFloor((lots+1e-10)/step)*step,8);
      if(lots<minLot || !MathIsValidNumber(lots))
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=min_lot utc_day=",utcDay);return;}
      ResetLastError();
      double freeAfter=AccountFreeMarginCheck(Symbol(),side,lots);
      int marginError=GetLastError();
      if(marginError!=0 || freeAfter<0.3*capital)
      {Print(gLogIdentity,"event=ENTRY_SKIPPED reason=margin error=",marginError," utc_day=",utcDay);return;}
      gEntrySide=side;gEntryBar=signalBar;gEntryDay=utcDay;
      gEntryStop=stop;gEntryTarget=target;gEntryLots=lots;gEntryATR=signalATR;
   }
   // 未送信の待機だけは同じSignalTimeframeの足・UTC日内で保持する。
   if(!TC_Begin()) return;
   bool invalid=false;
   for(int pool=0;pool<2;pool++)
   {
      int total=(pool==0 ? OrdersTotal() : OrdersHistoryTotal());
      for(int j=0;j<total;j++)
      {
         if(!OrderSelect(j,SELECT_BY_POS,pool==0 ? MODE_TRADES : MODE_HISTORY))
         {invalid=true;gStateHealthy=false;gRestorePending=false;break;}
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC && (pool==0 || OrderCloseTime()>=gEntryBar))
         {invalid=true;break;}
      }
      if(invalid) break;
   }
   RefreshRates();
   datetime sendNow=TimeCurrent(),sendUTC=sendNow-utcOffset*3600;
   int sendMinute=TimeHour(sendUTC)*60+TimeMinute(sendUTC);
   double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
   double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=Point;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double entry=(gEntrySide==OP_BUY ? Ask : Bid);
   double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
   double capital=MathMin(AccountBalance(),AccountEquity());
   invalid=(invalid || !IsTradeAllowed() || (!IsTesting() && !IsConnected()) || sendNow<TradeStartTime ||
      sendNow>=gEntryBar+PeriodSeconds(SignalTimeframe) || iTime(Symbol(),SignalTimeframe,0)!=gEntryBar || (long)sendUTC/86400!=gEntryDay ||
      TimeDayOfWeek(sendUTC)==0 || TimeDayOfWeek(sendUTC)==6 ||
      sendMinute<EntryStartUTC || sendMinute>=EntryEndUTC || (TimeDayOfWeek(sendUTC)==5 && sendMinute>=FridayExitUTC) ||
      Point<=0 || Bid<=0 || Ask<=Bid || !MathIsValidNumber(Bid) || !MathIsValidNumber(Ask) || Ask-Bid>MaxSpreadPips*pip+Point*1e-6 ||
      tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot ||
      !MathIsValidNumber(tick) || !MathIsValidNumber(tv) || !MathIsValidNumber(step) ||
      !MathIsValidNumber(minLot) || !MathIsValidNumber(maxLot) || !MathIsValidNumber(capital) ||
      capital<=0 || !MathIsValidNumber(minDist) || minDist<tick ||
      !MathIsValidNumber(gEntryATR) || gEntryATR<=0);
   if(!invalid)
   {
      // 初回の方向・ATRを維持し、TC取得後に実際の送信気配と現在資本で一度だけ再計算する。
      gEntryStop=entry+(gEntrySide==OP_BUY ? -StopATR : StopATR)*gEntryATR;
      gEntryTarget=0;
      if(TakeProfitATR>0) gEntryTarget=entry+(gEntrySide==OP_BUY ? TakeProfitATR : -TakeProfitATR)*gEntryATR;
      gEntryStop=NormalizeDouble((gEntrySide==OP_BUY ? MathFloor(gEntryStop/tick) : MathCeil(gEntryStop/tick))*tick,Digits);
      if(TakeProfitATR>0) gEntryTarget=NormalizeDouble((gEntrySide==OP_BUY ? MathCeil(gEntryTarget/tick) : MathFloor(gEntryTarget/tick))*tick,Digits);
      double distance=(gEntrySide==OP_BUY ? entry-gEntryStop : gEntryStop-entry);
      invalid=(!MathIsValidNumber(gEntryStop) || gEntryStop<=0 || !MathIsValidNumber(distance) || distance<=0 ||
         distance>StopATR*gEntryATR+tick+1e-9 || (gEntrySide==OP_BUY ? Bid-gEntryStop : gEntryStop-Ask)<minDist ||
         (TakeProfitATR>0 && (!MathIsValidNumber(gEntryTarget) || gEntryTarget<=0 ||
         (gEntrySide==OP_BUY ? gEntryTarget-Bid : Ask-gEntryTarget)<minDist)));
      if(!invalid)
      {
         double risk=distance/tick*tv;
         gEntryLots=MathMin(capital*EntryRiskPercent/100.0/risk,maxLot);
         gEntryLots=NormalizeDouble(MathFloor((gEntryLots+1e-10)/step)*step,8);
         invalid=(!MathIsValidNumber(gEntryLots) || gEntryLots<minLot || gEntryLots>maxLot ||
            MathAbs(gEntryLots/step-MathRound(gEntryLots/step))>1e-7 ||
            MathAbs(gEntryStop/tick-MathRound(gEntryStop/tick))>1e-6 ||
            risk*gEntryLots>capital*EntryRiskPercent/100.0+1e-8);
         if(!invalid)
         {
            ResetLastError();
            double freeAfter=AccountFreeMarginCheck(Symbol(),gEntrySide,gEntryLots);
            int marginError=GetLastError();
            if(marginError!=0 || freeAfter<0.3*capital) invalid=true;
         }
      }
   }
   if(invalid)
   {
      TC_End(false);gEntrySide=-1;
      Print(gLogIdentity,"event=ENTRY_SKIPPED reason=final_validation utc_day=",gEntryDay);
      return;
   }
   // 発注結果が未確定のまま終了しても、新しい注文を重ねない。
   if(!IsTesting())
   {
      ResetLastError();
      if(GlobalVariableSet(gEntryPendingKey,(double)sendNow)==0)
      {TC_End(false);gEntrySide=-1;Print(gLogIdentity,"event=ENTRY_PENDING_SAVE_FAILED error=",GetLastError());return;}
      GlobalVariablesFlush();
   }
   ResetLastError();
   int newTicket=OrderSend(Symbol(),gEntrySide,gEntryLots,entry,Slippage,gEntryStop,gEntryTarget,COMMENT,MAGIC,0,clrNONE);
   int error=GetLastError();
   gReleasePending=!TC_End(true);
   gEntrySide=-1; // API実行後は失敗・結果不明を含め、同じ候補を再送しない。
   gEntryUncertain=(newTicket<=0 && (error==0 || error==1 || error==2 || error==6 || error==128));
   if(!IsTesting() && !gEntryUncertain)
   {
      if(!GlobalVariableDel(gEntryPendingKey)) gEntryUncertain=true;
      GlobalVariablesFlush();
   }
   if(gEntryUncertain) Print(gLogIdentity,"event=ENTRY_UNCERTAIN_BLOCKED error=",error," key=",gEntryPendingKey,
      " action=verify_order_result_before_clearing_marker_and_reinitializing");
   if(newTicket<=0)
   {Print(gLogIdentity,"event=ENTRY_FAILED error=",error," message=no further entry attempt on this signal bar");return;}
   Print(gLogIdentity,"event=ENTRY_OK ticket=",newTicket," lots=",DoubleToString(gEntryLots,8),
         " armed_bar=",TimeToString(gEntryBar,TIME_DATE|TIME_MINUTES)," armed_bar_epoch=",(long)gEntryBar,
         " armed_upper=",DoubleToString(gArmedUpper,Digits)," armed_lower=",DoubleToString(gArmedLower,Digits),
         " armed_atr=",DoubleToString(gEntryATR,Digits)," risk_percent=",DoubleToString(EntryRiskPercent,4));
}
