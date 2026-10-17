//+------------------------------------------------------------------+
//|                                                        STR06_USDJPY_H1.mq4 |
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

#define MAGIC 20261004
#define COMMENT "STR06_USDJPY_H1"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
// 固定設定：最適化対象外。運用上の手動設定は可能。
sinput string TradeSymbol = "USDJPY"; // 取引通貨（USDJPY固定、ブローカーの接尾辞は許容）
sinput ENUM_TIMEFRAMES SignalTimeframe = PERIOD_H1; // シグナル時間足（H1固定）
sinput int ATRPeriod = 14; // 確定足ATRの計算期間
sinput int EntryStartUTC = 60; // 新規注文開始時刻（UTCの分、含む）
sinput int EntryEndUTC = 1200; // 新規注文終了時刻（UTCの分、含まない）
sinput int ExitMinuteUTC = -1; // 日次決済時刻（UTCの分、-1は日次決済なし）
sinput double EntryRiskPercent = 0.25; // 1注文の初期SLリスク率（%）
sinput double MaxSpreadPips = 2.0; // 予約発注時の最大スプレッド（pips）
sinput int Slippage = 20; // 成行決済の許容スリッページ（points）
sinput int BrokerWinterUTCOffset = 2; // 冬時間のサーバー時刻とUTCの差（時間）
sinput int BrokerSummerUTCOffset = 3; // 夏時間のサーバー時刻とUTCの差（時間）
sinput bool UseUSDST = true; // 米国の夏時間日程でサーバー時差を切り替える

// 最適化対象：突破期間・初期損切り幅・追尾幅・保有期限。
input int ChannelBars = 16; // 確定足の高値・安値チャネル期間
input double StopATR = 1.0; // 初期損切り幅のATR倍率
input double TrailATR = 2.0; // 終値極値からの追尾幅のATR倍率
input int HoldBars = 24; // 約定足から数えた最大保有バー数

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
string gLogIdentity = "", gExitPrefix = "", gTradeBarKey = "", gTrailPrefix = "";
datetime gLastBar = 0;
datetime gLastTradeBar = 0, gLastExitBar = 0, gEntryOpportunityBar = 0, gTrailRetryTime = 0;
int gTrailTicket = 0, gEntryWaitTicket = 0;
double gTrailStop = 0;
bool gEntryReady = false, gStateHealthy = true;
int gExitTickets[];
datetime gExitRetryTimes[];
// テスター内だけで日次の有効証拠金・残高を記録する。
int gEquityFile = INVALID_HANDLE;
datetime gEquityLastTick = 0;
double gEquityLastValue = 0, gEquityLastBalance = 0;

//+------------------------------------------------------------------+
//| 初期化：入力確認と売買状態の復元                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   // USDJPY・H1専用。売買に使う入力値の範囲だけを確認する
   gLogIdentity="ea="+COMMENT+" ";
   if(TradeSymbol!="USDJPY" || SignalTimeframe!=PERIOD_H1 || Period()!=PERIOD_H1 || StringSubstr(Symbol(),0,6)!=TradeSymbol ||
      ATRPeriod<1 || ChannelBars<1 ||
      StopATR<=0 || TrailATR<=0 ||
      HoldBars<1 || EntryRiskPercent<=0 || EntryRiskPercent>0.5 || MaxSpreadPips<=0 || Slippage<0 ||
      EntryStartUTC<0 || EntryEndUTC>1440 || EntryStartUTC>=EntryEndUTC || ExitMinuteUTC < -1 || ExitMinuteUTC>=1440 ||
      BrokerWinterUTCOffset < -12 || BrokerWinterUTCOffset>14 ||
      BrokerSummerUTCOffset < -12 || BrokerSummerUTCOffset>14)
      return(INIT_PARAMETERS_INCORRECT);
   // 再起動しても注文・決済要求を引き継ぐ。原本STR06と同じMagic・短い保存キーを使用する
   string scope=AccountServer()+"|"+Symbol();
   uint scopeHash=2166136261;
   for(int k=0;k<StringLen(scope);k++) scopeHash=(scopeHash^(uint)StringGetCharacter(scope,k))*16777619;
   gExitPrefix="STR06.X."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+".";
   gTrailPrefix=gExitPrefix;
   StringReplace(gTrailPrefix,".X.",".T.");
   gTradeBarKey="STR06.B."+IntegerToString(AccountNumber())+"."+IntegerToString(MAGIC)+"."+IntegerToString((int)scopeHash)+"."+IntegerToString((int)SignalTimeframe);
   if(!IsTesting() && GlobalVariableCheck(gTradeBarKey)) gLastTradeBar=(datetime)GlobalVariableGet(gTradeBarKey);
   // 現在注文と履歴から当該バーの発注・決済を復元し、再入場を防ぐ
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
   if(IsTesting())
   {
      gEquityLastTick=0;gEquityLastValue=0;gEquityLastBalance=0;
      string equityName=COMMENT+"_equity_"+IntegerToString((long)TimeLocal())+"_"+
                        IntegerToString((long)GetTickCount())+".csv";
      ResetLastError();
      gEquityFile=FileOpen(equityName,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(gEquityFile==INVALID_HANDLE)
      {
         Print(gLogIdentity,"event=EQUITY_FILE_OPEN_FAILED error=",GetLastError());
         return(INIT_FAILED);
      }
      ResetLastError();
      if(FileWrite(gEquityFile,"time","equity","balance")==0)
      {
         Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());
         FileClose(gEquityFile);gEquityFile=INVALID_HANDLE;
         return(INIT_FAILED);
      }
   }
   gEntryReady=IsTesting();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| テスターの日次出力を完了する                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(IsTesting() && gEquityFile!=INVALID_HANDLE)
   {
      if(gEquityLastTick>0)
      {
         ResetLastError();
         if(FileWrite(gEquityFile,TimeToString(gEquityLastTick,TIME_DATE|TIME_SECONDS),
                      DoubleToString(AccountEquity(),2),DoubleToString(AccountBalance(),2))==0)
            Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());
      }
      FileClose(gEquityFile);gEquityFile=INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| ティック処理：注文管理・新バーのシグナル判定                     |
//+------------------------------------------------------------------+
void OnTick()
{
   // サーバー時刻をUTCへ換算し、金曜20時以降と週末の全決済条件を判定する
   datetime now=TimeCurrent();
   if(IsTesting() && gEquityFile!=INVALID_HANDLE)
   {
      // サーバー日付の変化時に、前日の最終ティックで保存した値を書き出す。
      if(gEquityLastTick>0 && (long)now/86400!=(long)gEquityLastTick/86400)
      {
         ResetLastError();
         if(FileWrite(gEquityFile,TimeToString(gEquityLastTick,TIME_DATE|TIME_SECONDS),
                      DoubleToString(gEquityLastValue,2),DoubleToString(gEquityLastBalance,2))==0)
            Print(gLogIdentity,"event=EQUITY_FILE_WRITE_FAILED error=",GetLastError());
      }
      gEquityLastTick=now;
      gEquityLastValue=AccountEquity();
      gEquityLastBalance=AccountBalance();
   }
   int y=TimeYear(now-BrokerWinterUTCOffset*3600);
   datetime mar=StrToTime(IntegerToString(y)+".03.01 09:00"),nov=StrToTime(IntegerToString(y)+".11.01 09:00");
   datetime ds=mar+(7-TimeDayOfWeek(mar))%7*86400+7*86400,de=nov+(7-TimeDayOfWeek(nov))%7*86400;
   int utcOffset=BrokerWinterUTCOffset;
   if(UseUSDST && now>=ds && now<de) utcOffset=BrokerSummerUTCOffset;
   datetime nowUTC=now-utcOffset*3600;
   long utcDay=(long)nowUTC/86400;
   int utcMinute=TimeHour(nowUTC)*60+TimeMinute(nowUTC);
   bool weekendFlat=(TimeDayOfWeek(nowUTC)==5 && utcMinute>=1200) || TimeDayOfWeek(nowUTC)==6 || TimeDayOfWeek(nowUTC)==0;

   // 初回の実運用では次の新バーを待ち、指標計算に必要な確定足がそろってから判定する
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
   // 同一銘柄・Magicの注文だけを管理する。予約注文も占有数に含める
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
      // 日次期限・保有期限・予約注文の有効期限を判定する
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
      // 未完了の決済要求と追尾SLを復元し、通信失敗後も要求を保持する
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
         // 約定足から直前確定足までの終値極値とATRで、SLを有利な方向へだけ更新する
         if(newBar && held>0 && held<iBars(Symbol(),SignalTimeframe))
         {
            double trailATR=iATR(Symbol(),SignalTimeframe,ATRPeriod,1);
            int extremeShift=(side==OP_BUY ? iHighest(Symbol(),SignalTimeframe,MODE_CLOSE,held,1) :
                                           iLowest(Symbol(),SignalTimeframe,MODE_CLOSE,held,1));
            double extreme=(extremeShift>=0 ? iClose(Symbol(),SignalTimeframe,extremeShift) : 0);
            if(trailATR>0 && extreme>0 && Bid>0 && Ask>=Bid)
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
         // 追尾水準を既に通過していれば成行決済。未通過なら距離制限を確認してSLを変更する
         if(gTrailStop>0 && Bid>0 && Ask>=Bid)
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
      // 決済要求をチケット別に保持し、失敗時は5秒以上空けて再試行する
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
      // 注文の再選択後に約定状態・凍結距離を確認し、予約取消または成行決済する
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
         continue; // 凍結距離を外れるまで決済要求を保持する
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

   // 占有注文、同一バーの再発注、時間外、状態保存の失敗がある場合は新規注文を行わない
   if(occupied>0 || closedThisTick || (!newBar && gEntryOpportunityBar!=bar) || !seriesReady || !gStateHealthy ||
      weekendFlat || utcMinute<EntryStartUTC || utcMinute>=EntryEndUTC ||
      (ExitMinuteUTC>=0 && utcMinute>=ExitMinuteUTC) || gLastTradeBar>=bar || gLastExitBar>=bar) return;
   // 新バーで期限切れ注文の取消を待った場合は、完了後に同じバーの発注判定を再開する
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
   RefreshRates();
   double pip=Point*(Digits==3 || Digits==5 ? 10.0 : 1.0);
   if(Bid<=0 || Ask<=Bid || Ask-Bid>MaxSpreadPips*pip) return;

   // 直前確定足のEMA120で方向を決め、確定済みチャネルの外側へ逆指値を置く
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
   // 銘柄の価格刻み・ロット刻み・損失換算値を取得する
   double tick=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=Point;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(tick<=0 || tv<=0 || step<=0 || minLot<=0 || maxLot<minLot) return;
   // 買いはBid高値に現在spreadを加算。既に突破済み、または最小距離未満なら見送る
   double entry=(side==OP_BUY ? upper+Ask-Bid : lower);
   entry=NormalizeDouble((side==OP_BUY ? MathCeil(entry/tick) : MathFloor(entry/tick))*tick,Digits);
   double minDist=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point+tick;
   if((side==OP_BUY && (entry-Ask<minDist)) ||
      (side==OP_SELL && (Bid-entry<minDist))) return;
   // 初期SLをATR倍率で設定し、予約期限を現在のH1バー終端にそろえる
   double stop=entry+(side==OP_BUY ? -StopATR : StopATR)*atr;
   stop=NormalizeDouble((side==OP_BUY ? MathFloor(stop/tick) : MathCeil(stop/tick))*tick,Digits);
   if(stop<=0 || MathAbs(entry-stop)<minDist) return;
   datetime expiration=bar+PeriodSeconds(SignalTimeframe);
   if(expiration<=now) return;
   // 残高と有効証拠金の小さい方を基準に、初期SL損失額からロットを切り下げる
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
   // タイムアウトで約定結果が不明な場合も二重発注しないよう、送信前に当該バーを消費する
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
   // SLを同時指定して逆指値を送信する（固定TPなし、予約期限の拒否はログへ記録）
   int orderType=(side==OP_BUY ? OP_BUYSTOP : OP_SELLSTOP);
   int newTicket=OrderSend(Symbol(),orderType,lots,entry,Slippage,stop,0,COMMENT,MAGIC,expiration,clrNONE);
   if(newTicket <= 0){Print(gLogIdentity,"event=ENTRY_FAILED error=",GetLastError()," message=no further entry attempt on this signal bar");return;}
}
