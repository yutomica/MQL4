//+------------------------------------------------------------------+
//|                                                        STR06.mq4 |
//|                         価格チャネルブレイクEA
//+------------------------------------------------------------------+

/*
売買ロジック
- En:
  Close1>EMA120ならshift1からChannelBars本の最高Bid高値+現在spreadに買い逆指値、
  Close1<EMA120なら同最安値に売り逆指値を置く。UTC指定時間内の新バーで試行し、期限は1足。
- Ex:
  新バーに、約定足から直前確定足までの最高/最低終値とTrailATR×ATRでSLを有利な方向へ追尾する。
  ギャップで追尾SLを越えた時は成行決済を要求する。週末・日次期限には未約定注文も取り消す。
  HoldBars経過、金曜UTC20:00以降、またはExitMinuteUTC指定時の日次期限でも決済する。
  決済要求と追尾SL候補はチケット別に保持し、失敗後は5秒以上空けて再試行する。
- SL/TP:
  SLはATR(ATRPeriod)のStopATR倍を予約価格から離して同時発注し、固定TPは置かない。
- ポジション数・ロット:
  同一Symbol/Magicは最大1注文。発注試行はSignalTimeframeの各バーで最大1回、決済バーは再入場しない。
  残高と有効証拠金の小さい方に対するSL損失率で計算し、ロットステップ単位で切り下げる。
*/

#property strict
#property description "価格チャネル逆指値・EMA120フィルター・ATR追尾。"

#define MAGIC 2026100406
#define COMMENT "STR06"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
input string TradeSymbol = "USDJPY";
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_H1;
input int ATRPeriod = 14;
input int ChannelBars = 16;
input double StopATR = 3.0;
input double TrailATR = 2.0;
input int EntryStartUTC = 60;
input int EntryEndUTC = 1200;
input int ExitMinuteUTC = -1; // -1 permits overnight positions.
input int HoldBars = 24;
input double EntryRiskPercent = 0.25;
input double MaxSpreadPips = 2.0;
input int Slippage = 20; // point
input int BrokerWinterUTCOffset = 2;
input int BrokerSummerUTCOffset = 3;
input bool UseUSDST = true;
input string EquityFileName = "";

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
string gLogIdentity = "", gExitPrefix = "", gTradeBarKey = "", gTrailPrefix = "";
datetime gLastBar = 0, gLastTick = 0;
double gLastEquity = 0, gLastBalance = 0, gPeakEquity = 0;
double gMaxDDMoney = 0, gMaxDDPercent = 0;
int gEquityFile = INVALID_HANDLE;
datetime gLastTradeBar = 0, gLastExitBar = 0, gEntryOpportunityBar = 0, gTrailRetryTime = 0;
int gTrailTicket = 0, gEntryWaitTicket = 0;
double gTrailStop = 0;
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
   bool allowedTF=(SignalTimeframe==PERIOD_M15 || SignalTimeframe==PERIOD_M30 || SignalTimeframe==PERIOD_H1 || SignalTimeframe==PERIOD_H4);
   bool allowedSymbol=(TradeSymbol=="USDJPY" || TradeSymbol=="EURJPY" || TradeSymbol=="GBPJPY" || TradeSymbol=="EURUSD" || TradeSymbol=="AUDJPY");
   if(!allowedTF || !allowedSymbol || (!IsTesting() && Period()!=SignalTimeframe) || StringSubstr(Symbol(),0,6)!=TradeSymbol ||
      ATRPeriod<1 || ChannelBars<1 ||
      StopATR<=0 || TrailATR<=0 ||
      HoldBars<1 || EntryRiskPercent<=0 || EntryRiskPercent>0.5 || MaxSpreadPips<=0 || Slippage<0 ||
      EntryStartUTC<0 || EntryEndUTC>1440 || EntryStartUTC>=EntryEndUTC || ExitMinuteUTC < -1 || ExitMinuteUTC>=1440 ||
      BrokerWinterUTCOffset < -12 || BrokerWinterUTCOffset>14 ||
      BrokerSummerUTCOffset < -12 || BrokerSummerUTCOffset>14)
      return(INIT_PARAMETERS_INCORRECT);
   string scope=AccountServer()+"|"+Symbol();
   uint scopeHash=2166136261;
   for(int k=0;k<StringLen(scope);k++) scopeHash=(scopeHash^(uint)StringGetCharacter(scope,k))*16777619;
   gExitPrefix=COMMENT+".X."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+".";
   gTrailPrefix=gExitPrefix;
   StringReplace(gTrailPrefix,".X.",".T.");
   gTradeBarKey=COMMENT+".B."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+"."+IntegerToString((int)SignalTimeframe);
   if(!IsTesting() && GlobalVariableCheck(gTradeBarKey)) gLastTradeBar=(datetime)GlobalVariableGet(gTradeBarKey);
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
         if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC ||
            (OrderType()!=OP_BUY && OrderType()!=OP_SELL && OrderType()!=OP_BUYSTOP && OrderType()!=OP_SELLSTOP)) continue;
         int openedShift=iBarShift(Symbol(),SignalTimeframe,OrderOpenTime(),false);
         datetime openedBar=(openedShift>=0 ? iTime(Symbol(),SignalTimeframe,openedShift) : 0);
         if(openedBar>gLastTradeBar) gLastTradeBar=openedBar;
         datetime currentBar=iTime(Symbol(),SignalTimeframe,0);
         if(currentBar>0 && (OrderType()==OP_BUY || OrderType()==OP_SELL) && OrderCloseTime()>=currentBar) gLastExitBar=currentBar;
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
         " summer_utc_offset=",BrokerSummerUTCOffset," driver_tf=",Period()," signal_tf=",SignalTimeframe);
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
   long utcDay=(long)nowUTC/86400;
   int utcMinute=TimeHour(nowUTC)*60+TimeMinute(nowUTC);
   bool weekendFlat=(TimeDayOfWeek(nowUTC)==5 && utcMinute>=1200) || TimeDayOfWeek(nowUTC)==6 || TimeDayOfWeek(nowUTC)==0;

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
   int requiredBars=(int)MathMax(MathMax(ChannelBars+1,120),ATRPeriod)+5;
   bool seriesReady=(iBars(Symbol(),SignalTimeframe)>=requiredBars && bar>0 && bar<=now &&
                     iTime(Symbol(),SignalTimeframe,requiredBars-1)>0 && iTime(Symbol(),SignalTimeframe,1)>0 &&
                     iTime(Symbol(),SignalTimeframe,1)+PeriodSeconds(SignalTimeframe)<=now);
   bool newBar=(seriesReady && bar!=gLastBar);
   if(newBar){gLastBar=bar;gEntryOpportunityBar=0;gEntryWaitTicket=0;}
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
   int occupied=0;
   bool closedThisTick=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){Print(gLogIdentity,"event=ORDER_SELECT_FAILED error=",GetLastError());return;}
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC) continue;
      occupied++;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL && OrderType()!=OP_BUYSTOP && OrderType()!=OP_SELLSTOP) continue;
      int ticket=OrderTicket(),side=OrderType();
      int held=iBarShift(Symbol(),SignalTimeframe,OrderOpenTime(),false);
      bool isPending=(side==OP_BUYSTOP || side==OP_SELLSTOP);
      if(newBar && isPending && OrderExpiration()>0 && now>=OrderExpiration())
      {gEntryOpportunityBar=bar;gEntryWaitTicket=ticket;}
      bool timeExit=false;
      if(ExitMinuteUTC>=0)
      {
         datetime opened=OrderOpenTime();
         int oy=TimeYear(opened-BrokerWinterUTCOffset*3600);
         datetime omar=StrToTime(IntegerToString(oy)+".03.01 09:00"),onov=StrToTime(IntegerToString(oy)+".11.01 09:00");
         datetime ods=omar+(7-TimeDayOfWeek(omar))%7*86400+7*86400,ode=onov+(7-TimeDayOfWeek(onov))%7*86400;
         int openOffset=BrokerWinterUTCOffset;
         if(UseUSDST && opened>=ods && opened<ode) openOffset=BrokerSummerUTCOffset;
         timeExit=(utcMinute>=ExitMinuteUTC || (long)(opened-openOffset*3600)/86400<utcDay);
      }
      bool mustExit=(weekendFlat || timeExit || (!isPending && held>=HoldBars) ||
         (isPending && OrderExpiration()>0 && now>=OrderExpiration()));
      string key=gExitPrefix+IntegerToString(ticket);
      int pending=-1;
      for(int j=0;j<ArraySize(gExitTickets);j++) if(gExitTickets[j]==ticket) pending=j;
      bool saved=(!IsTesting() && GlobalVariableCheck(key));
      string trailKey=gTrailPrefix+IntegerToString(ticket);
      if(!isPending && !mustExit && pending<0 && !saved)
      {
         if(gTrailTicket!=ticket)
         {
            gTrailTicket=ticket;gTrailStop=0;gTrailRetryTime=0;
            if(!IsTesting() && GlobalVariableCheck(trailKey)) gTrailStop=GlobalVariableGet(trailKey);
         }
         double priceTick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
         if(priceTick<=0) priceTick=Point;
         RefreshRates();
         if(newBar && held>0 && held<iBars(Symbol(),SignalTimeframe))
         {
            double trailATR=iATR(Symbol(),SignalTimeframe,ATRPeriod,1);
            int extremeShift=(side==OP_BUY ? iHighest(Symbol(),SignalTimeframe,MODE_CLOSE,held,1) :
                                           iLowest(Symbol(),SignalTimeframe,MODE_CLOSE,held,1));
            double extreme=(extremeShift>=0 ? iClose(Symbol(),SignalTimeframe,extremeShift) : 0);
            if(trailATR>0 && extreme>0 && priceTick>0 && Bid>0 && Ask>=Bid)
            {
               double nextStop=extreme+(side==OP_BUY ? -TrailATR*trailATR : TrailATR*trailATR+Ask-Bid);
               nextStop=NormalizeDouble((side==OP_BUY ? MathFloor(nextStop/priceTick) : MathCeil(nextStop/priceTick))*priceTick,Digits);
               bool improves=(nextStop>0 && (OrderStopLoss()<=0 || (side==OP_BUY ? nextStop>OrderStopLoss() : nextStop<OrderStopLoss())));
               if(improves && (gTrailStop<=0 || (side==OP_BUY ? nextStop>gTrailStop : nextStop<gTrailStop)))
               {
                  gTrailStop=nextStop;
                  if(!IsTesting())
                  {
                     ResetLastError();
                     if(GlobalVariableSet(trailKey,gTrailStop)==0)
                     {gStateHealthy=false;Print(gLogIdentity,"event=TRAIL_STATE_SAVE_FAILED ticket=",ticket," error=",GetLastError());}
                     else GlobalVariablesFlush();
                  }
               }
            }
         }
         if(gTrailStop>0 && OrderStopLoss()>0 && (side==OP_BUY ? gTrailStop<=OrderStopLoss() : gTrailStop>=OrderStopLoss()))
         {
            gTrailStop=0;
            if(!IsTesting() && GlobalVariableCheck(trailKey))
            {if(!GlobalVariableDel(trailKey)) Print(gLogIdentity,"event=TRAIL_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
         }
         if(gTrailStop>0 && Bid>0 && Ask>=Bid && priceTick>0)
         {
            if(side==OP_BUY ? gTrailStop>=Bid : gTrailStop<=Ask) mustExit=true;
            else if(now>=gTrailRetryTime)
            {
               gTrailRetryTime=now+5;
               double stopGap=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
               double freezeGap=MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point;
               double gap=(side==OP_BUY ? Bid-gTrailStop : gTrailStop-Ask);
               if(gap>=stopGap+priceTick && gap>freezeGap+priceTick && IsTradeAllowed() && (IsTesting() || IsConnected()))
               {
                  ResetLastError();
                  if(!OrderModify(ticket,OrderOpenPrice(),gTrailStop,OrderTakeProfit(),0,clrNONE))
                     Print(gLogIdentity,"event=TRAIL_MODIFY_FAILED ticket=",ticket," error=",GetLastError()," retry_after_seconds=5");
                  else
                  {
                     gTrailStop=0;
                     if(!IsTesting() && GlobalVariableCheck(trailKey))
                     {if(!GlobalVariableDel(trailKey)) Print(gLogIdentity,"event=TRAIL_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
                  }
               }
            }
         }
      }
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
      double exitPrice=(side==OP_BUY || side==OP_SELLSTOP ? Bid : Ask);
      double freeze=MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point;
      if(exitPrice<=0) continue;
      if(isPending)
      {
         double pendingDistance=(side==OP_BUYSTOP ? OrderOpenPrice()-Ask : Bid-OrderOpenPrice());
         if(freeze>0 && pendingDistance<=freeze) continue;
      }
      else if(freeze>0 &&
         ((OrderStopLoss()>0 && (side==OP_BUY ? exitPrice-OrderStopLoss() : OrderStopLoss()-exitPrice)<=freeze) ||
          (OrderTakeProfit()>0 && (side==OP_BUY ? OrderTakeProfit()-exitPrice : exitPrice-OrderTakeProfit())<=freeze)))
         continue; // Keep the request active until the freeze restriction clears.
      gExitRetryTimes[pending]=now+5;
      ResetLastError();
      bool exitOK=(isPending ? OrderDelete(ticket,clrNONE) : OrderClose(ticket,OrderLots(),exitPrice,Slippage,clrNONE));
      if(!exitOK)
         Print(gLogIdentity,"event=",isPending ? "PENDING_DELETE_FAILED" : "EXIT_FAILED"," ticket=",ticket," error=",GetLastError()," retry_after_seconds=5");
      else
      {
         occupied--;
         if(!isPending)
         {
            closedThisTick=true;gLastExitBar=bar;gTrailTicket=0;gTrailStop=0;
            if(!IsTesting() && GlobalVariableCheck(trailKey))
            {if(!GlobalVariableDel(trailKey)) Print(gLogIdentity,"event=TRAIL_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
         }
         int last=ArraySize(gExitTickets)-1;
         gExitTickets[pending]=gExitTickets[last];gExitRetryTimes[pending]=gExitRetryTimes[last];
         ArrayResize(gExitTickets,last);ArrayResize(gExitRetryTimes,last);
         if(!IsTesting() && GlobalVariableCheck(key))
         {if(!GlobalVariableDel(key)) Print(gLogIdentity,"event=EXIT_STATE_CLEANUP_FAILED ticket=",ticket," error=",GetLastError());GlobalVariablesFlush();}
      }
   }

   if(occupied>0 || closedThisTick || (!newBar && gEntryOpportunityBar!=bar) || !seriesReady || !gStateHealthy || iBars(Symbol(),SignalTimeframe)<requiredBars ||
      weekendFlat || utcMinute<EntryStartUTC || utcMinute>=EntryEndUTC ||
      (ExitMinuteUTC>=0 && utcMinute>=ExitMinuteUTC) || gLastTradeBar>=bar || gLastExitBar>=bar) return;
   if(gEntryOpportunityBar==bar && gEntryWaitTicket>0)
   {
      ResetLastError();
      if(!OrderSelect(gEntryWaitTicket,SELECT_BY_TICKET))
      {Print(gLogIdentity,"event=ENTRY_WAIT_SELECT_FAILED ticket=",gEntryWaitTicket," error=",GetLastError());return;}
      if(OrderCloseTime()==0) return;
      if((OrderType()==OP_BUY || OrderType()==OP_SELL) && OrderCloseTime()>=bar)
      {gLastExitBar=bar;gEntryOpportunityBar=0;return;}
   }
   if(!IsTradeAllowed() || (!IsTesting() && !IsConnected())) return;
   ResetLastError();
   RefreshRates(); // false also means the quotes are already current.
   double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
   if(Bid<=0 || Ask<=Bid || Ask-Bid>MaxSpreadPips*pip) return;

   double atr=iATR(Symbol(),SignalTimeframe,ATRPeriod,1);
   if(atr<=0) return;
   double c1=iClose(Symbol(),SignalTimeframe,1);
   double ema1=iMA(Symbol(),SignalTimeframe,120,0,MODE_EMA,PRICE_CLOSE,1);
   int highShift=iHighest(Symbol(),SignalTimeframe,MODE_HIGH,ChannelBars,1);
   int lowShift=iLowest(Symbol(),SignalTimeframe,MODE_LOW,ChannelBars,1);
   if(highShift<0 || lowShift<0 || c1<=0 || ema1<=0) return;
   double upper=iHigh(Symbol(),SignalTimeframe,highShift),lower=iLow(Symbol(),SignalTimeframe,lowShift);
   if(upper<=0 || lower<=0 || upper<lower) return;
   int side=-1;
   if(c1>ema1) side=OP_BUY;
   if(c1<ema1) side=OP_SELL;
   if(side<0) return;
   double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=Point;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot) return;
   double entry=(side==OP_BUY ? upper+Ask-Bid : lower);
   entry=NormalizeDouble((side==OP_BUY ? MathCeil(entry/tick) : MathFloor(entry/tick))*tick,Digits);
   double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
   if((side==OP_BUY && (Ask>=entry || entry-Ask<minDist)) ||
      (side==OP_SELL && (Bid<=entry || Bid-entry<minDist))) return;
   double stop=entry+(side==OP_BUY ? -StopATR : StopATR)*atr;
   stop=NormalizeDouble((side==OP_BUY ? MathFloor(stop/tick) : MathCeil(stop/tick))*tick,Digits);
   if(stop<=0 || MathAbs(entry-stop)<minDist) return;
   datetime expiration=bar+PeriodSeconds(SignalTimeframe);
   if(expiration<=now) return;
   double capital=MathMin(AccountBalance(),AccountEquity()),risk=MathAbs(entry-stop)/tick*tv;
   if(capital<=0 || risk<=0) return;
   double lots=MathMin(capital*EntryRiskPercent/100.0/risk,maxLot);
   lots=NormalizeDouble(MathFloor((lots+1e-10)/step)*step,8);
   if(lots<minLot) return;
   ResetLastError();
   double freeAfter=AccountFreeMarginCheck(Symbol(),side,lots);
   int marginError=GetLastError();
   if(marginError!=0 || freeAfter<0.3*capital) return;
   // Reserve one signal-bar attempt before OrderSend, including an uncertain timeout.
   gLastTradeBar = bar;gEntryOpportunityBar=0;gEntryWaitTicket=0;
   if(!IsTesting())
   {
      ResetLastError();
      if(GlobalVariableSet(gTradeBarKey, (double)bar) == 0)
      {
         gStateHealthy = false;
         Print(gLogIdentity, "event=TRADE_BAR_SAVE_FAILED error=", GetLastError());
         return;
      }
      GlobalVariablesFlush();
   }
   ResetLastError();
   int orderType=(side==OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   int newTicket=OrderSend(Symbol(),orderType,lots,entry,Slippage,stop,0,COMMENT,MAGIC,expiration,clrNONE);
   if(newTicket <= 0){Print(gLogIdentity,"event=ENTRY_FAILED error=",GetLastError()," message=no further entry attempt on this signal bar");return;}
   Print(gLogIdentity,"event=ENTRY_OK ticket=",newTicket," side=",side==OP_BUY ? "BUYSTOP" : "SELLSTOP"," lots=",DoubleToString(lots,8));
}
