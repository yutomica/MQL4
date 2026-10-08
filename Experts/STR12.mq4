//+------------------------------------------------------------------+
//|                                                        STR12.mq4 |
//|                         ロンドン始値レンジ突破EA
//+------------------------------------------------------------------+

/*
売買ロジック
- En:
  USDJPYのM15確定足を使用し、各ロンドン営業日08:00から08:45までの4本の高安を固定する。
  レンジを構成する全足のサーバー時刻が完全一致し、確定していることを確認する。
  09:00以上13:00未満に開始した確定足が高値超または安値未満で終えた最初の場面で、次新バーに買い/売り。
  初期値の最初の発注バーは09:15、最終は13:00。先行突破がある場合は後続バーから発注しない。
  1ロンドン日につき発注試行は最大1回。失敗を含め再試行せず、発注前に日次予約を永続化する。
  ロンドン夏時間は3月最終日曜01:00UTCから10月最終日曜01:00UTCの直前までUTC+1。
  TradeStartTimeより前の新規注文は抑止する。
- Ex:
  HoldBars32本M15経過、ロンドン日付変更、または金曜UTC20:00以降に決済する。
  決済要求をチケット別に保持し、失敗後は5秒以上空けて再試行する。
- SL/TP:
  発注時点の確定H1足ATR14のStopATR1.5倍を発注価格から離して同時発注する。TP・追尾は設定しない。
- ポジション数・ロット:
  同一Symbol/Magicは最大1注文。決済バーは再入場しない。
  min(balance,equity)の0.25%をSL損失額とする。ロットステップ切下げ、最小ロット未満は見送る。
  発注後の余剰証拠金を資金の30%以上残す。テスト時は日次equity CSVを出力する。
*/

#property strict
#property description "ロンドン始値レンジ突破。M15確定足・H1 ATR・日次1回。"

#define MAGIC 2026100412
#define COMMENT "STR12"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
input string TradeSymbol = "USDJPY";
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15;
input int ATRPeriod = 14;
input ENUM_TIMEFRAMES ATRTimeframe = PERIOD_H1;
input int RangeStartLondon = 480;
input int RangeBars = 4;
input int EntryWindowBars = 16;
input double StopATR = 1.5;
input int FridayExitUTC = 1200;
input int HoldBars = 32;
input double EntryRiskPercent = 0.25;
input double MaxSpreadPips = 2.0;
input int Slippage = 20; // point
input int BrokerWinterUTCOffset = 2;
input int BrokerSummerUTCOffset = 3;
input bool UseUSDST = true;
input string EquityFileName = "";
input datetime TradeStartTime = 0; // サーバー時刻。履歴準備中の新規注文を抑止する。

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
string gLogIdentity = "", gExitPrefix = "", gTradeDayKey = "";
datetime gLastBar = 0, gLastTick = 0;
double gLastEquity = 0, gLastBalance = 0, gPeakEquity = 0;
double gMaxDDMoney = 0, gMaxDDPercent = 0;
int gEquityFile = INVALID_HANDLE;
datetime gLastTradeBar = 0, gLastExitBar = 0;
long gLastTradeDay = -1;
bool gEntryReady = false, gStateHealthy = true;
int gExitTickets[];
datetime gExitRetryTimes[];

//+------------------------------------------------------------------+
int OnInit()
{
   gLogIdentity="ea="+COMMENT+" symbol="+Symbol()+
      " tf="+StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()),7)+
      " magic="+IntegerToString(MAGIC)+" chart="+IntegerToString(ChartID())+
      " session="+IntegerToString((long)TimeLocal())+"-"+IntegerToString((long)GetTickCount())+" ";
   Print(gLogIdentity,"event=INIT_BEGIN compiled=",__DATETIME__);
   bool allowedTF=(SignalTimeframe==PERIOD_M15);
   bool allowedSymbol=(TradeSymbol=="USDJPY" || TradeSymbol=="EURJPY" || TradeSymbol=="GBPJPY" || TradeSymbol=="EURUSD" || TradeSymbol=="AUDJPY");
   if(!allowedTF || !allowedSymbol || (!IsTesting() && Period()!=SignalTimeframe) || StringSubstr(Symbol(),0,6)!=TradeSymbol ||
      ATRPeriod<1 || (ATRTimeframe!=PERIOD_M15 && ATRTimeframe!=PERIOD_M30 && ATRTimeframe!=PERIOD_H1 && ATRTimeframe!=PERIOD_H4) ||
      RangeStartLondon<0 || RangeStartLondon>=1440 || RangeStartLondon%15!=0 || RangeBars<1 || RangeBars>96 ||
      EntryWindowBars<1 || EntryWindowBars>96 || RangeStartLondon+(RangeBars+EntryWindowBars)*15>1440 || StopATR<=0 ||
      HoldBars<1 || EntryRiskPercent<=0 || EntryRiskPercent>0.5 || MaxSpreadPips<=0 || Slippage<0 ||
      FridayExitUTC<0 || FridayExitUTC>=1440 ||
      BrokerWinterUTCOffset < -12 || BrokerWinterUTCOffset>14 ||
      BrokerSummerUTCOffset < -12 || BrokerSummerUTCOffset>14)
      return(INIT_PARAMETERS_INCORRECT);
   string scope=AccountServer()+"|"+Symbol();
   uint scopeHash=2166136261;
   for(int k=0;k<StringLen(scope);k++) scopeHash=(scopeHash^(uint)StringGetCharacter(scope,k))*16777619;
   gExitPrefix=COMMENT+".X."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+".";
   gTradeDayKey=COMMENT+".D."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+"."+IntegerToString((int)SignalTimeframe);
   if(!IsTesting() && GlobalVariableCheck(gTradeDayKey)) gLastTradeDay=(long)GlobalVariableGet(gTradeDayKey);
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
   gPeakEquity=AccountEquity();
   if(IsTesting())
   {
      string name=(StringLen(EquityFileName)>0 ? EquityFileName : COMMENT+"_equity.csv");
      gEquityFile=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(gEquityFile==INVALID_HANDLE) return(INIT_FAILED);
      FileWrite(gEquityFile,"time","equity","balance");
   }
   Print(gLogIdentity,"event=INIT_OK timezone=US_DST winter_utc_offset=",BrokerWinterUTCOffset,
         " summer_utc_offset=",BrokerSummerUTCOffset," driver_tf=",Period()," signal_tf=",SignalTimeframe," trade_start=",TimeToString(TradeStartTime,TIME_DATE|TIME_MINUTES),
         " trade_start_epoch=",(long)TradeStartTime);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gEquityFile!=INVALID_HANDLE)
   {
      if(gLastTick>0) FileWrite(gEquityFile,TimeToString(gLastTick,TIME_DATE|TIME_SECONDS),
         DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
      FileClose(gEquityFile);
   }
   Print(gLogIdentity,"event=DEINIT reason=",reason," currency=",AccountCurrency(),
         " tick_size=",DoubleToString(SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE),Digits),
         " tick_value=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8)," max_dd_money=",DoubleToString(gMaxDDMoney,2),
         " max_dd_percent=",DoubleToString(gMaxDDPercent,4));
}

//+------------------------------------------------------------------+
double OnTester()
{
   Print(gLogIdentity,"event=TEST_STATS max_dd_money=",DoubleToString(gMaxDDMoney,2),
         " max_dd_percent=",DoubleToString(gMaxDDPercent,4)," currency=",AccountCurrency(),
         " tick_size=",DoubleToString(SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE),Digits),
         " tick_value=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8));
   return(0.0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now=TimeCurrent();
   int y=TimeYear(now-BrokerWinterUTCOffset*3600);
   datetime mar=StrToTime(IntegerToString(y)+".03.01 09:00"),nov=StrToTime(IntegerToString(y)+".11.01 09:00");
   datetime ds=mar+(7-TimeDayOfWeek(mar))%7*86400+7*86400,de=nov+(7-TimeDayOfWeek(nov))%7*86400;
   int utcOffset=BrokerWinterUTCOffset;
   if(UseUSDST && now>=ds && now<de) utcOffset=BrokerSummerUTCOffset;
   datetime nowUTC=now-utcOffset*3600;
   int utcMinute=TimeHour(nowUTC)*60+TimeMinute(nowUTC);
   bool weekendFlat=(TimeDayOfWeek(nowUTC)==5 && utcMinute>=FridayExitUTC) || TimeDayOfWeek(nowUTC)==6 || TimeDayOfWeek(nowUTC)==0;

   int londonYear=TimeYear(nowUTC);
   datetime londonMar=StrToTime(IntegerToString(londonYear)+".03.31 01:00"),londonOct=StrToTime(IntegerToString(londonYear)+".10.31 01:00");
   datetime londonDSTStart=londonMar-TimeDayOfWeek(londonMar)*86400,londonDSTEnd=londonOct-TimeDayOfWeek(londonOct)*86400;
   int londonOffset=(nowUTC>=londonDSTStart && nowUTC<londonDSTEnd ? 1 : 0);
   datetime nowLondon=nowUTC+londonOffset*3600;
   long londonDay=(long)nowLondon/86400;
   bool londonBusinessDay=(TimeDayOfWeek(nowLondon)>=1 && TimeDayOfWeek(nowLondon)<=5);

   double eq=AccountEquity();
   if(gPeakEquity<=0 || eq>gPeakEquity) gPeakEquity=eq;
   double dd=gPeakEquity-eq,ddp=(gPeakEquity>0 ? dd/gPeakEquity*100.0 : 0);
   if(dd>gMaxDDMoney) gMaxDDMoney=dd;
   if(ddp>gMaxDDPercent) gMaxDDPercent=ddp;
   if(gEquityFile!=INVALID_HANDLE && gLastTick>0 && (long)now/86400!=(long)gLastTick/86400)
      FileWrite(gEquityFile,TimeToString(gLastTick,TIME_DATE|TIME_SECONDS),DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
   gLastTick=now;gLastEquity=eq;gLastBalance=AccountBalance();

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
   // SL and time limits provide exits for this strategy.
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
      ResetLastError();
      RefreshRates(); // false also means the quotes are already current.
      ResetLastError();
      if(!OrderSelect(ticket,SELECT_BY_TICKET)){Print(gLogIdentity,"event=EXIT_SELECT_FAILED ticket=",ticket," error=",GetLastError());continue;}
      if(OrderCloseTime()!=0 || OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || OrderType()!=side) continue;
      double exitPrice = (side == OP_BUY ? Bid : Ask);
      double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
      if(exitPrice <= 0) continue;
      if(freeze > 0 &&
         ((OrderStopLoss() > 0 && (side == OP_BUY ? exitPrice - OrderStopLoss() : OrderStopLoss() - exitPrice) <= freeze) ||
          (OrderTakeProfit() > 0 && (side == OP_BUY ? OrderTakeProfit() - exitPrice : exitPrice - OrderTakeProfit()) <= freeze)))
         continue; // The saved exit request remains active until the freeze restriction clears.
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

   if(occupied || closedThisTick || !newBar || !gStateHealthy || iBars(Symbol(),SignalTimeframe)<requiredBars ||
      now<TradeStartTime || weekendFlat || !londonBusinessDay || gLastTradeDay>=londonDay ||
      gLastTradeBar>=bar || gLastExitBar>=bar) return;
   if(!IsTradeAllowed() || (!IsTesting() && !IsConnected())) return;
   ResetLastError();
   RefreshRates(); // false also means the quotes are already current.
   double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
   if(Bid<=0 || Ask<=Bid || Ask-Bid>MaxSpreadPips*pip) return;

   int signalSeconds=PeriodSeconds(SignalTimeframe);
   datetime rangeStart=(datetime)(londonDay*86400)+RangeStartLondon*60;
   datetime rangeEnd=rangeStart+RangeBars*signalSeconds;
   datetime windowEnd=rangeEnd+EntryWindowBars*signalSeconds;
   datetime signalServer=iTime(Symbol(),SignalTimeframe,1);
   datetime signalLondon=signalServer-utcOffset*3600+londonOffset*3600;
   if(signalLondon<rangeEnd || signalLondon>=windowEnd ||
      (signalLondon-rangeEnd)%signalSeconds!=0 || bar!=signalServer+signalSeconds) return;

   double rangeHigh=0.0,rangeLow=0.0;
   // Convert each expected London timestamp to UTC, then to the broker's historical clock.
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
   double c1=iClose(Symbol(),SignalTimeframe,1);
   if(c1<=0 || !MathIsValidNumber(c1)) return;
   int side=-1;
   if(c1>rangeHigh) side=OP_BUY;
   if(c1<rangeLow) side=OP_SELL;
   if(side<0) return;
   // A previous breakout consumes the first scene even if no order was sent on that bar.
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
   datetime atrCurrent=iTime(Symbol(),ATRTimeframe,0),atrBar=iTime(Symbol(),ATRTimeframe,1);
   if(iBars(Symbol(),ATRTimeframe)<ATRPeriod+5 || atrCurrent<=0 || atrCurrent>now ||
      now>=atrCurrent+PeriodSeconds(ATRTimeframe) || atrBar<=0 || atrBar+PeriodSeconds(ATRTimeframe)>now) return;
   double atr=iATR(Symbol(),ATRTimeframe,ATRPeriod,1);
   if(atr<=0 || !MathIsValidNumber(atr)) return;
   double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=Point;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot) return;
   double entry=(side==OP_BUY ? Ask : Bid);
   double stop=entry+(side==OP_BUY ? -StopATR : StopATR)*atr;
   stop=NormalizeDouble((side==OP_BUY ? MathFloor(stop/tick) : MathCeil(stop/tick))*tick,Digits);
   double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
   if(stop<=0 || (side==OP_BUY && Bid-stop<minDist) ||
      (side==OP_SELL && stop-Ask<minDist)) return;
   double capital=MathMin(AccountBalance(),AccountEquity()),risk=MathAbs(entry-stop)/tick*tv;
   if(capital<=0 || risk<=0) return;
   double lots=MathMin(capital*EntryRiskPercent/100.0/risk,maxLot);
   lots=NormalizeDouble(MathFloor((lots+1e-10)/step)*step,8);
   if(lots<minLot) return;
   ResetLastError();
   double freeAfter=AccountFreeMarginCheck(Symbol(),side,lots);
   int marginError=GetLastError();
   if(marginError!=0 || freeAfter<0.3*capital) return;
   // Reserve one London-day attempt before OrderSend, including an uncertain timeout.
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
   int newTicket=OrderSend(Symbol(),side,lots,entry,Slippage,stop,0,COMMENT,MAGIC,0,clrNONE);
   if(newTicket <= 0){Print(gLogIdentity,"event=ENTRY_FAILED error=",GetLastError()," message=no further entry attempt on this London day");return;}
   Print(gLogIdentity,"event=ENTRY_OK ticket=",newTicket," side=",side==OP_BUY ? "BUY" : "SELL"," lots=",DoubleToString(lots,8),
         " london_day=",TimeToString((datetime)(londonDay*86400),TIME_DATE),
         " range_high=",DoubleToString(rangeHigh,Digits)," range_low=",DoubleToString(rangeLow,Digits),
         " signal_close=",DoubleToString(c1,Digits)," risk_percent=",DoubleToString(EntryRiskPercent,4));
}
