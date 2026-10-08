//+------------------------------------------------------------------+
//|                                             STR12_USDJPY_M15.mq4 |
//|                         ロンドン始値レンジ突破EA
//+------------------------------------------------------------------+

/*
売買ロジック
- En:
  USDJPYのM15確定足を使用し、ロンドン平日のRangeStartLondonからRangeBars本の高安を固定する（初期値08:00～08:45の4本、祝日判定なし）。
  レンジ終端からEntryWindowBars本の間に開始した確定足が高値超または安値未満で終えた最初の場面で、次新バーに買い/売り。先行突破がある場合は後続バーから発注しない。
  1ロンドン日につき発注試行は最大1回。失敗を含め再試行せず、発注前に日次予約を永続化する。
  ロンドン夏時間は3月最終日曜01:00UTCから10月最終日曜01:00UTCの直前までUTC+1。TradeStartTimeより前の新規注文は抑止する。
- Ex:
  HoldBars本M15経過（初期値32本）、ロンドン日付変更、または金曜FridayExitUTC以降（初期値UTC20:00）に決済する。
  決済要求をチケット別に保持し、失敗後は5秒以上空けて再試行する。
- SL/TP:
  発注時点の確定ATRTimeframe足のATR(ATRPeriod)×StopATRを発注価格から離して同時発注する（初期値H1・14期間・1.5倍）。
  TP・追尾は設定しない。
- ポジション数・ロット:
  同一Symbol/Magicは最大1注文。決済バーは再入場しない。
  min(balance,equity)のEntryRiskPercent%をSL損失額とする（初期値0.25%）。ロットステップ切下げ、最小ロット未満は見送る。
  発注後の余剰証拠金を資金の30%以上残す。
*/

#property strict
#property description "ロンドン始値レンジ突破。M15確定足・H1 ATR・日次1回。"

#define MAGIC 20261004
#define COMMENT "STR12_USDJPY_M15"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
const string TradeSymbol = "USDJPY"; // 取引通貨（USDJPY固定、ブローカーの接尾辞は許容）
const ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15; // シグナル時間足（M15固定）
sinput ENUM_TIMEFRAMES ATRTimeframe = PERIOD_H1; // SL算出用ATRの時間足（初期値H1）
sinput int RangeStartLondon = 480; // レンジ形成開始時刻（ロンドン時刻の分）
sinput int FridayExitUTC = 1200; // 金曜の全決済開始時刻（UTCの分）
sinput double EntryRiskPercent = 0.25; // 1注文の初期SLリスク率（%）
sinput double MaxSpreadPips = 2.0; // 成行発注時の最大スプレッド（pips）
sinput int Slippage = 20; // 成行発注・決済の許容スリッページ（points）
sinput int BrokerWinterUTCOffset = 2; // 冬時間のサーバー時刻とUTCの差（時間）
sinput int BrokerSummerUTCOffset = 3; // 夏時間のサーバー時刻とUTCの差（時間）
sinput bool UseUSDST = true; // 米国の夏時間日程でサーバー時差を切り替える
sinput datetime TradeStartTime = 0; // 新規注文を許可する開始サーバー時刻（0は制限なし）
input int RangeBars = 4; // レンジ形成に使うM15足数
input int HoldBars = 32; // 約定足から数える最大保有M15足数
input int EntryWindowBars = 16; // レンジ形成後の突破受付足数（M15）
input double StopATR = 1.5; // 初期SL幅のATR倍率
input int ATRPeriod = 14; // 確定足ATRの計算期間

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
string gLogIdentity = "", gExitPrefix = "", gTradeDayKey = "";
datetime gLastBar = 0;
datetime gLastTradeBar = 0, gLastExitBar = 0;
long gLastTradeDay = -1;
bool gEntryReady = false, gStateHealthy = true;
int gExitTickets[];
datetime gExitRetryTimes[];

//+------------------------------------------------------------------+
//| 初期化：入力確認と売買状態の復元                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   // USDJPY・M15専用。シグナル条件、時刻、リスク設定の有効範囲を確認する
   gLogIdentity="ea="+COMMENT+" ";
   if(TradeSymbol!="USDJPY" || SignalTimeframe!=PERIOD_M15 || Period()!=PERIOD_M15 || StringSubstr(Symbol(),0,6)!=TradeSymbol ||
      ATRPeriod<1 || (ATRTimeframe!=PERIOD_M15 && ATRTimeframe!=PERIOD_M30 && ATRTimeframe!=PERIOD_H1 && ATRTimeframe!=PERIOD_H4) ||
      RangeStartLondon<0 || RangeStartLondon>=1440 || RangeStartLondon%15!=0 || RangeBars<1 || RangeBars>96 ||
      EntryWindowBars<1 || EntryWindowBars>96 || RangeStartLondon+(RangeBars+EntryWindowBars)*15>1440 || StopATR<=0 ||
      HoldBars<1 || EntryRiskPercent<=0 || EntryRiskPercent>0.5 || MaxSpreadPips<=0 || Slippage<0 ||
      FridayExitUTC<0 || FridayExitUTC>=1440 ||
      BrokerWinterUTCOffset < -12 || BrokerWinterUTCOffset>14 ||
      BrokerSummerUTCOffset < -12 || BrokerSummerUTCOffset>14)
      return(INIT_PARAMETERS_INCORRECT);
   // 原本と同じMagic・短い保存キーを使い、再起動後も日次制限と決済要求を引き継ぐ
   string scope=AccountServer()+"|"+Symbol();
   uint scopeHash=2166136261;
   for(int k=0;k<StringLen(scope);k++) scopeHash=(scopeHash^(uint)StringGetCharacter(scope,k))*16777619;
   gExitPrefix="STR12.X."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+".";
   gTradeDayKey="STR12.D."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+"."+IntegerToString((int)SignalTimeframe);
   if(!IsTesting() && GlobalVariableCheck(gTradeDayKey)) gLastTradeDay=(long)GlobalVariableGet(gTradeDayKey);
   // 注文と履歴から最終発注バー・ロンドン日付・決済バーを復元する
   for(int pool=0;pool<2;pool++)
   {
      int total=(pool==0 ? OrdersTotal() : OrdersHistoryTotal());
      for(int i=0;i<total;i++)
      {
         if(!OrderSelect(i, SELECT_BY_POS, pool == 0 ? MODE_TRADES : MODE_HISTORY))
         {
            Print(gLogIdentity, "event=INIT_HISTORY_SELECT_FAILED error=", GetLastError());
            return(INIT_FAILED);
         }
         if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         int openedShift=iBarShift(Symbol(),SignalTimeframe,OrderOpenTime(),false);
         datetime openedBar=(openedShift>=0 ? iTime(Symbol(),SignalTimeframe,openedShift) : 0);
         if(openedBar>gLastTradeBar) gLastTradeBar=openedBar;
         // 約定日時も当時の時差でロンドン日付に変換する
         datetime opened=OrderOpenTime();
         int oy=TimeYear(opened-BrokerWinterUTCOffset*3600);
         datetime omar=StrToTime(IntegerToString(oy)+".03.01 09:00"),onov=StrToTime(IntegerToString(oy)+".11.01 09:00");
         datetime ods=omar+(7-TimeDayOfWeek(omar))%7*86400+7*86400,ode=onov+(7-TimeDayOfWeek(onov))%7*86400;
         int openOffset=BrokerWinterUTCOffset;
         if(UseUSDST && opened>=ods && opened<ode) openOffset=BrokerSummerUTCOffset;
         datetime openedUTC=opened-openOffset*3600;
         int ly=TimeYear(openedUTC);
         datetime lmar=StrToTime(IntegerToString(ly)+".03.31 01:00"),loct=StrToTime(IntegerToString(ly)+".10.31 01:00");
         datetime lds=lmar-TimeDayOfWeek(lmar)*86400,lde=loct-TimeDayOfWeek(loct)*86400;
         long openedDay=(long)(openedUTC+(openedUTC>=lds && openedUTC<lde ? 3600 : 0))/86400;
         if(openedDay>gLastTradeDay) gLastTradeDay=openedDay;
         datetime currentBar=iTime(Symbol(),SignalTimeframe,0);
         if(currentBar>0 && OrderCloseTime()>=currentBar) gLastExitBar=currentBar;
      }
   }
   gEntryReady=IsTesting();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| ティック処理：決済管理と新バーの初回突破判定                     |
//+------------------------------------------------------------------+
void OnTick()
{
   // サーバー時刻をUTCへ換算し、金曜の決済期限と週末を判定する
   datetime now=TimeCurrent();
   int y=TimeYear(now-BrokerWinterUTCOffset*3600);
   datetime mar=StrToTime(IntegerToString(y)+".03.01 09:00"),nov=StrToTime(IntegerToString(y)+".11.01 09:00");
   datetime ds=mar+(7-TimeDayOfWeek(mar))%7*86400+7*86400,de=nov+(7-TimeDayOfWeek(nov))%7*86400;
   int utcOffset=BrokerWinterUTCOffset;
   if(UseUSDST && now>=ds && now<de) utcOffset=BrokerSummerUTCOffset;
   datetime nowUTC=now-utcOffset*3600;
   int utcMinute=TimeHour(nowUTC)*60+TimeMinute(nowUTC);
   bool weekendFlat=(TimeDayOfWeek(nowUTC)==5 && utcMinute>=FridayExitUTC) || TimeDayOfWeek(nowUTC)==6 || TimeDayOfWeek(nowUTC)==0;

   // 英国夏時間は3月・10月の最終日曜01:00 UTCで切り替える（米国DSTとは別判定）
   int londonYear=TimeYear(nowUTC);
   datetime londonMar=StrToTime(IntegerToString(londonYear)+".03.31 01:00"),londonOct=StrToTime(IntegerToString(londonYear)+".10.31 01:00");
   datetime londonDSTStart=londonMar-TimeDayOfWeek(londonMar)*86400,londonDSTEnd=londonOct-TimeDayOfWeek(londonOct)*86400;
   int londonOffset=(nowUTC>=londonDSTStart && nowUTC<londonDSTEnd ? 1 : 0);
   datetime nowLondon=nowUTC+londonOffset*3600;
   long londonDay=(long)nowLondon/86400;
   bool londonBusinessDay=(TimeDayOfWeek(nowLondon)>=1 && TimeDayOfWeek(nowLondon)<=5);

   // 実運用の再起動時は次のM15新バーを待ち、直前足の確定と履歴を確認する
   datetime bar=iTime(Symbol(),SignalTimeframe,0);
   if(!gEntryReady && bar>0){gLastBar=bar;gEntryReady=true;}
   int requiredBars=7;
   bool seriesReady=(iBars(Symbol(),SignalTimeframe)>=requiredBars && bar>0 && bar<=now &&
                     iTime(Symbol(),SignalTimeframe,requiredBars-1)>0 && iTime(Symbol(),SignalTimeframe,1)>0 &&
                     iTime(Symbol(),SignalTimeframe,1)+PeriodSeconds(SignalTimeframe)<=now);
   bool newBar=(seriesReady && bar!=gLastBar);
   if(newBar) gLastBar=bar;
   if(newBar)
   {
      for(int h=OrdersHistoryTotal()-1;h>=0;h--)
      {
         if(!OrderSelect(h,SELECT_BY_POS,MODE_HISTORY))
         {Print(gLogIdentity,"event=HISTORY_SELECT_FAILED error=",GetLastError());gStateHealthy=false;return;}
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC &&
            (OrderType()==OP_BUY || OrderType()==OP_SELL) && OrderCloseTime()>=bar)
            gLastExitBar=bar;
      }
   }
   // SLと保有期限・日付変更・週末条件で決済する。同一銘柄・Magicだけを管理する
   bool occupied=false,closedThisTick=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){Print(gLogIdentity,"event=ORDER_SELECT_FAILED error=",GetLastError());return;}
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC) continue;
      occupied=true;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      int ticket=OrderTicket(),side=OrderType();
      int held=iBarShift(Symbol(),SignalTimeframe,OrderOpenTime(),false);
      datetime opened=OrderOpenTime();
      int oy=TimeYear(opened-BrokerWinterUTCOffset*3600);
      datetime omar=StrToTime(IntegerToString(oy)+".03.01 09:00"),onov=StrToTime(IntegerToString(oy)+".11.01 09:00");
      datetime ods=omar+(7-TimeDayOfWeek(omar))%7*86400+7*86400,ode=onov+(7-TimeDayOfWeek(onov))%7*86400;
      int openOffset=BrokerWinterUTCOffset;
      if(UseUSDST && opened>=ods && opened<ode) openOffset=BrokerSummerUTCOffset;
      datetime openedUTC=opened-openOffset*3600;
      int ly=TimeYear(openedUTC);
      datetime lmar=StrToTime(IntegerToString(ly)+".03.31 01:00"),loct=StrToTime(IntegerToString(ly)+".10.31 01:00");
      datetime lds=lmar-TimeDayOfWeek(lmar)*86400,lde=loct-TimeDayOfWeek(loct)*86400;
      long openedDay=(long)(openedUTC+(openedUTC>=lds && openedUTC<lde ? 3600 : 0))/86400;
      bool mustExit=(held>=HoldBars || weekendFlat || openedDay<londonDay);
      string key=gExitPrefix+IntegerToString(ticket);
      int pending=-1;
      for(int j=0;j<ArraySize(gExitTickets);j++) if(gExitTickets[j]==ticket) pending=j;
      bool saved=(!IsTesting() && GlobalVariableCheck(key));
      if(!mustExit && pending<0 && !saved) continue;
      // 決済要求をチケット別に保持し、通信失敗後は5秒以上空けて再試行する
      if(pending<0)
      {
         int size=ArraySize(gExitTickets);
         bool retryResized=(ArrayResize(gExitRetryTimes,size+1)==size+1);
         bool ticketResized=(ArrayResize(gExitTickets,size+1)==size+1);
         if(!retryResized || !ticketResized)
         {ArrayResize(gExitTickets,size);ArrayResize(gExitRetryTimes,size);gStateHealthy=false;Print(gLogIdentity,"event=EXIT_REQUEST_RETAIN_FAILED ticket=",ticket);return;}
         pending=size;gExitTickets[pending]=ticket;gExitRetryTimes[pending]=0;
      }
      if(!IsTesting() && !saved)
      {
         ResetLastError();
         if(GlobalVariableSet(key,1.0)==0){gStateHealthy=false;Print(gLogIdentity,"event=EXIT_STATE_SAVE_FAILED ticket=",ticket," error=",GetLastError());}
         else GlobalVariablesFlush();
      }
      if(now<gExitRetryTimes[pending]) continue;
      if(!IsTradeAllowed() || (!IsTesting() && !IsConnected())) continue;
      RefreshRates();
      ResetLastError();
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){Print(gLogIdentity,"event=EXIT_SELECT_FAILED ticket=",ticket," error=",GetLastError());continue;}
      if(OrderCloseTime()!=0 || OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || OrderType()!=side) continue;
      // 約定状態と凍結距離を再確認してから成行決済する
      double exitPrice = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      if(exitPrice <= 0) continue;
      if(freeze > 0 &&
         ((OrderStopLoss() > 0 && (side == OP_BUY ? exitPrice - OrderStopLoss() : OrderStopLoss() - exitPrice) <= freeze) ||
          (OrderTakeProfit() > 0 && (side == OP_BUY ? OrderTakeProfit() - exitPrice : exitPrice - OrderTakeProfit()) <= freeze)))
         continue; // 凍結距離を外れるまで決済要求を保持する
      gExitRetryTimes[pending] = now + 5;
      ResetLastError();
      if(!OrderClose(ticket,OrderLots(),side==OP_BUY ? Bid : Ask,Slippage,clrNONE))
         Print(gLogIdentity,"event=EXIT_FAILED ticket=",ticket," error=",GetLastError()," retry_after_seconds=5");
      else
      {
         closedThisTick=true;gLastExitBar=bar;
         int last=ArraySize(gExitTickets)-1;
         gExitTickets[pending]=gExitTickets[last];gExitRetryTimes[pending]=gExitRetryTimes[last];
         ArrayResize(gExitTickets,last);ArrayResize(gExitRetryTimes,last);
         if(!IsTesting() && GlobalVariableCheck(key))
         {if(!GlobalVariableDel(key)) Print(gLogIdentity,"event=EXIT_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
      }
   }

   // 既存注文、日次発注済み、時間外、決済済みバーでは新規注文を抑止する
   if(occupied || closedThisTick || !newBar || !gStateHealthy ||
      now<TradeStartTime || weekendFlat || !londonBusinessDay || gLastTradeDay>=londonDay ||
      gLastTradeBar>=bar || gLastExitBar>=bar) return;
   if(!IsTradeAllowed() || (!IsTesting() && !IsConnected())) return;
   RefreshRates();
   double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
   if(Bid<=0 || Ask<=Bid || Ask-Bid>MaxSpreadPips*pip) return;

   // レンジ終端からの受付時間を算出する。最終受付足の次バーでも発注できる
   int signalSeconds=PeriodSeconds(SignalTimeframe);
   datetime rangeStart=(datetime)(londonDay*86400)+RangeStartLondon*60;
   datetime rangeEnd=rangeStart+RangeBars*signalSeconds;
   datetime windowEnd=rangeEnd+EntryWindowBars*signalSeconds;
   datetime signalServer=iTime(Symbol(),SignalTimeframe,1);
   datetime signalLondon=signalServer-utcOffset*3600+londonOffset*3600;
   if(signalLondon<rangeEnd || signalLondon>=windowEnd ||
      (signalLondon-rangeEnd)%signalSeconds!=0 || bar!=signalServer+signalSeconds) return;

   double rangeHigh=0.0,rangeLow=0.0;
   // 各レンジ足のロンドン時刻をUTC経由でサーバー時刻へ変換し、欠損や未確定足を除外する
   datetime brokerDSTStartUTC=ds-BrokerWinterUTCOffset*3600;
   datetime brokerDSTEndUTC=de-BrokerSummerUTCOffset*3600;
   for(int k=0;k<RangeBars;k++)
   {
      datetime expectedUTC=rangeStart+k*signalSeconds-londonOffset*3600;
      int expectedOffset=BrokerWinterUTCOffset;
      if(UseUSDST && expectedUTC>=brokerDSTStartUTC && expectedUTC<brokerDSTEndUTC) expectedOffset=BrokerSummerUTCOffset;
      datetime expectedServer=expectedUTC+expectedOffset*3600;
      int shift=iBarShift(Symbol(),SignalTimeframe,expectedServer,true);
      if(shift<1 || iTime(Symbol(),SignalTimeframe,shift)!=expectedServer || expectedServer+signalSeconds>now) return;
      double hi=iHigh(Symbol(),SignalTimeframe,shift),lo=iLow(Symbol(),SignalTimeframe,shift);
      if(hi<=0 || lo<=0 || hi<lo || !MathIsValidNumber(hi) || !MathIsValidNumber(lo)) return;
      if(k==0){rangeHigh=hi;rangeLow=lo;}
      else{rangeHigh=MathMax(rangeHigh,hi);rangeLow=MathMin(rangeLow,lo);}
   }
   // レンジ外で終えた確定足の方向へ成行で発注する
   double c1=iClose(Symbol(),SignalTimeframe,1);
   if(c1<=0 || !MathIsValidNumber(c1)) return;
   int side=-1;
   if(c1>rangeHigh) side=OP_BUY;
   if(c1<rangeLow) side=OP_SELL;
   if(side<0) return;
   // 先行する終値突破が一度でもあれば、その際に発注できていなくても後追いを禁止する
   for(datetime priorLondon=rangeEnd;priorLondon<signalLondon;priorLondon+=signalSeconds)
   {
      datetime priorUTC=priorLondon-londonOffset*3600;
      int priorOffset=BrokerWinterUTCOffset;
      if(UseUSDST && priorUTC>=brokerDSTStartUTC && priorUTC<brokerDSTEndUTC) priorOffset=BrokerSummerUTCOffset;
      datetime priorServer=priorUTC+priorOffset*3600;
      int priorShift=iBarShift(Symbol(),SignalTimeframe,priorServer,true);
      if(priorShift<2 || iTime(Symbol(),SignalTimeframe,priorShift)!=priorServer) return;
      double priorClose=iClose(Symbol(),SignalTimeframe,priorShift);
      if(priorClose<=0 || !MathIsValidNumber(priorClose) || priorClose>rangeHigh || priorClose<rangeLow) return;
   }
   // M15シグナルとは別に、ATR時間足の履歴と直前足の確定を確認する
   datetime atrCurrent=iTime(Symbol(),ATRTimeframe,0),atrBar=iTime(Symbol(),ATRTimeframe,1);
   if(iBars(Symbol(),ATRTimeframe)<ATRPeriod+5 || atrCurrent<=0 || atrCurrent>now ||
      now>=atrCurrent+PeriodSeconds(ATRTimeframe) || atrBar<=0 || atrBar+PeriodSeconds(ATRTimeframe)>now) return;
   double atr=iATR(Symbol(),ATRTimeframe,ATRPeriod,1);
   if(atr<=0 || !MathIsValidNumber(atr)) return;
   // 銘柄の価格刻み・ロット刻み・損失換算値を確認する
   double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=Point;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot) return;
   // ATR幅のSLを価格刻みにそろえ、Bid/Askからブローカーの最小距離を確保する
   double entry=(side==OP_BUY ? Ask : Bid);
   double stop=entry+(side==OP_BUY ? -StopATR : StopATR)*atr;
   stop=NormalizeDouble((side==OP_BUY ? MathFloor(stop/tick) : MathCeil(stop/tick))*tick,Digits);
   double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
   if(stop<=0 || (side==OP_BUY && Bid-stop<minDist) ||
      (side==OP_SELL && stop-Ask<minDist)) return;
   // 残高と有効証拠金の小さい方からリスク額を求め、ロットを切り下げる
   double capital=MathMin(AccountBalance(),AccountEquity()),risk=MathAbs(entry-stop)/tick*tv;
   if(capital<=0 || risk<=0) return;
   double lots=MathMin(capital*EntryRiskPercent/100.0/risk,maxLot);
   lots=NormalizeDouble(MathFloor((lots+1e-10)/step)*step,8);
   if(lots<minLot) return;
   ResetLastError();
   // 発注後も基準資産の30%以上の余剰証拠金を確保する
   double freeAfter=AccountFreeMarginCheck(Symbol(),side,lots);
   int marginError=GetLastError();
   if(marginError!=0 || freeAfter<0.3*capital) return;
   // 約定結果不明のタイムアウトでも二重発注しないよう、送信前にロンドン日付を消費・保存する
   gLastTradeBar=bar;gLastTradeDay=londonDay;
   if(!IsTesting())
   {
      ResetLastError();
      if(GlobalVariableSet(gTradeDayKey, (double)londonDay) == 0)
      {
         gStateHealthy = false;
         Print(gLogIdentity, "event=TRADE_DAY_SAVE_FAILED error=", GetLastError());
         return;
      }
      GlobalVariablesFlush();
   }
   ResetLastError();
   // SLを同時指定して成行発注する。固定TP・追尾は使わず、失敗時も当日は再発注しない
   int newTicket=OrderSend(Symbol(),side,lots,entry,Slippage,stop,0,COMMENT,MAGIC,0,clrNONE);
   if(newTicket <= 0){Print(gLogIdentity,"event=ENTRY_FAILED error=",GetLastError()," message=no further entry attempt on this London day");return;}
}
