//+------------------------------------------------------------------+
//|                                              STR01_USDJPY_H1.mq4 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

/*
売買ロジック
- En:
  新バーごとに確定済み直近En_bars本の最高値へBuy Stop、最安値へSell Stopを同一ロットでOCO発注する。全条件が一致する既存ペアは保持する。
  片側が約定すると反対側を取り消す。
- Ex:
  含み益がATR×HalfATRMultを超えると一度だけ半分を決済する。
  残りはSL、ATR×TrailATRMultの追尾、またはTimeStopBars本経過後の手数料・swap込み含み損決済で終了する。
- TP/SL:
  固定TPは設定しない（TP=0）。初期SLはBuyが確定済み直近SL_bars本の最安値、Sellが最高値。
  エントリーからSLまでの距離はSLLimitPips未満かつブローカーの最小距離以上を必須とする。両候補のいずれかが距離上限以上となる局面では、新規発注を見送る。
- トレーリングストップ:
  ATRPeriod・ATRShiftのH1 ATRを幅として使用し、SLが建値以上（Sellは建値以下）になる含み益へ到達後、価格に追随して有利な方向にだけSLを更新する。
- ポジション数・ロット:
  1回のOCOペアにつき約定対象は原則1建玉で、待機注文は同時に最大2件。
  ロットは残高と有効証拠金の小さい方にEntryRiskPercentを掛け、Buy/Sell双方のSL損失額の厳しい側で算出し、半分決済後も最小ロットを残せる数量へ切り下げる。
  約定後の余剰証拠金にはFreeMarginBufferPercentを確保する。
  MaxOpenPositionsで同時保有数を制限し、同方向・同一価格の重複も禁止する。
*/

#property strict

#include <stderror.mqh>
#include <Original/RiskManagement.mqh>
#include <Original/Mail.mqh>
#include <Original/TradeControl.mqh>

#define MAGIC 20260912
#define COMMENT "STR01_USDJPY_H1"

// MyLib由来の入力を先頭に保持し、既存setの名前・型・順序・既定値を維持する。
extern uint MyOrderWaitingTime = 5;
extern int Slippage = 50;
extern int En_bars = 12;
extern int SL_bars = 7;
extern int ATRPeriod = 3;
extern double SLLimitPips = 50.0;
extern double EntryRiskPercent = 0.3;
extern double FreeMarginBufferPercent = 30.0;
extern int TimeStopBars = 10;
extern int ATRShift = 0;
extern double HalfATRMult = 3.0;
extern double TrailATRMult = 3.0;
extern int MaxOpenPositions = 6; // 0なら従来比較用に保有数を制限しない
extern double MaxSpreadPips = 2.0;


// 注文間隔は参加EAで揃える。2秒はSTR01の従来値を引き継ぐ。
const int TRADE_INTERVAL_MS = 2000;

// OCOの進行を一つの状態で管理する。取消完了まで旧ticketを上書きしない。
enum PairState { PAIR_CANCEL, PAIR_IDLE, PAIR_BUY, PAIR_SELL, PAIR_ACTIVE, PAIR_CHECK, PAIR_DOUBLE };
PairState gPairState=PAIR_CANCEL;
int gBuyStopTicket=-1, gSellStopTicket=-1;
struct Prices { double buy,buySL,sell,sellSL; };
Prices gPairPrice;
double gPairLots=0;
datetime gPairBar=0, gPairStarted=0;
uint gPairStartedTick=0; // 期限は予約時でなく最初のOrderSendから数える。

// 正の送信番号は結果確認待ち、負なら処理済み。再起動後も不明な注文を再送しない。
string gSendKey="";
double gSendNumber=0;
string gLogIdentity="";
int gEntryMailTickets[];
struct HalfRecord { string key; double value; double baseLots; };
HalfRecord gHalfRecords[]; // 正=半分決済済み、負=確認待ちの予定残量、0=未決済。
bool gInitialized=false, gReleasePending=false;
datetime gStartedTime=0, gPreviousBar=0;
uint gStartedTick=0;
double gPipsPoint=0;
int gTimeCursor=-1, gHalfCursor=0, gTrailCursor=-1;
int fileHandle=INVALID_HANDLE;
datetime gEquityTick=0;
double gLastEquity=0, gLastBalance=0;


// 未呼出しの取消保存待ちと、API呼出し後の結果不明を分ける。
bool gSendCancelPending=false, gSendFinished=false;
bool gSendStateReadable=true;
int gSendKnownTicket=-1;
string SendRecordKey() { return("R."+MailScope(MAGIC)+"."+DoubleToString(MathAbs(gSendNumber),0)); }
bool FinishSendRecord()
{
   if(!IsTesting())
   {
      string key=SendRecordKey();
      if(gSendKnownTicket>0 && !gSendCancelPending)
      {
         // phase 3は成功結果の反映・保存待ち。取消しのphase 2とは区別する。
         if(GlobalVariableSet(key+".k",gSendKnownTicket)==0 || GlobalVariableSet(key+".p",3)==0) return(false);
      }
      else if(GlobalVariableSet(key+".p",2)==0) return(false);
      if(GlobalVariableSet(gSendKey,-MathAbs(gSendNumber))==0) return(false);
      GlobalVariablesFlush();
   }
   gSendNumber=-MathAbs(gSendNumber); gSendCancelPending=false; gSendFinished=false;
   return(true);
}
bool PrepareSendRecord(const int type,const double lots)
{
   gSendKnownTicket=-1; gSendCancelPending=true; gSendFinished=false;
   if(IsTesting()) { gSendCancelPending=false; return(true); }
   string key=SendRecordKey();
   bool ok=GlobalVariableSet(key+".p",0)!=0;
   ok=GlobalVariableSet(key+".t",(double)TimeCurrent())!=0 && ok;
   ok=GlobalVariableSet(key+".y",type)!=0 && ok;
   ok=GlobalVariableSet(key+".l",lots)!=0 && ok;
   ok=GlobalVariableSet(key+".k",0)!=0 && ok;
   int count=0;
   for(int pool=0;pool<2;pool++)
   {
      int total=pool==0 ? OrdersTotal() : OrdersHistoryTotal();
      for(int i=0;i<total;i++)
      {
         if(!OrderSelect(i,SELECT_BY_POS,pool==0 ? MODE_TRADES : MODE_HISTORY)) { ok=false; continue; }
         if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC) continue;
         if(pool==1 && OrderOpenTime()<TimeCurrent()) continue;
         if(GlobalVariableSet(key+".b"+IntegerToString(count),OrderTicket())==0 ||
            GlobalVariableSet(key+".u"+IntegerToString(count),(double)OrderOpenTime())==0 ||
            GlobalVariableSet(key+".v"+IntegerToString(count),OrderType())==0) ok=false;
         count++;
      }
   }
   ok=GlobalVariableSet(key+".n",count)!=0 && ok;
   if(ok) ok=GlobalVariableSet(gSendKey,gSendNumber)!=0;
   GlobalVariablesFlush();
   if(!ok) { FinishSendRecord(); return(false); }
   gSendCancelPending=false;
   return(true);
}
bool CommitSendRecord()
{
   if(IsTesting()) return(true);
   if(GlobalVariableSet(SendRecordKey()+".p",1)==0) { gSendCancelPending=true; FinishSendRecord(); return(false); }
   GlobalVariablesFlush(); return(true);
}
int ResolveSendRecord()
{
   if(gSendNumber<=0) return(-1);
   if(gSendCancelPending) { FinishSendRecord(); return(-1); }
   string key=SendRecordKey();
   double phase=1,known=0,when=0,type=-1,lots=0,count=-1;
   bool metadata=false;
   if(!IsTesting() && GlobalVariableCheck(key+".p"))
   {
      if(!GlobalVariableGet(key+".p",phase)) return(-1);
      if(phase==0 || phase==2) { gSendCancelPending=true; FinishSendRecord(); return(-1); }
      if(phase!=1 && phase!=3) return(-1);
      metadata=GlobalVariableGet(key+".t",when) && GlobalVariableGet(key+".y",type) &&
               GlobalVariableGet(key+".l",lots) && GlobalVariableGet(key+".n",count) && GlobalVariableGet(key+".k",known);
      if(!metadata || !MathIsValidNumber(when) || !MathIsValidNumber(type) || !MathIsValidNumber(lots) ||
         !MathIsValidNumber(count) || count<0 || count!=MathFloor(count) || lots<=0) return(-1);
   }
   if(gSendKnownTicket>0) known=gSendKnownTicket;
   if(known>0)
   {
      gSendKnownTicket=(int)known;
      if(!IsTesting() && GlobalVariableSet(key+".k",known)==0) return(-1);
      if(OrderSelect((int)known,SELECT_BY_TICKET) && OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC &&
         (!metadata || OrderType()==(int)type || ((int)type>=OP_BUYLIMIT && OrderType()==((int)type%2))))
      { if(FinishSendRecord()) return((int)known); return(-1); }
   }
   if(gSendFinished) { FinishSendRecord(); return(-1); }
   string tag="R"+DoubleToString(gSendNumber,0)+"|",legacy=COMMENT+"#"+DoubleToString(gSendNumber,0);
   int found=-1,matches=0; bool readable=true;
   for(int pool=0;pool<2;pool++)
   {
      int total=pool==0 ? OrdersTotal() : OrdersHistoryTotal();
      for(int i=0;i<total;i++)
      {
         if(!OrderSelect(i,SELECT_BY_POS,pool==0 ? MODE_TRADES : MODE_HISTORY)) { readable=false; continue; }
         if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC) continue;
         bool match=StringFind(OrderComment(),tag)==0 || StringFind(OrderComment(),legacy)==0;
         if(!match && metadata && when>0 && lots>0 && count>=0 && OrderOpenTime()>=(datetime)when &&
            OrderOpenTime()<=TimeCurrent() && MathAbs(OrderLots()-lots)<1e-8 &&
            (OrderType()==(int)type || ((int)type>=OP_BUYLIMIT && OrderType()==((int)type%2))))
         {
            match=true;
            int ticket=OrderTicket();
            for(int j=0;j<(int)count;j++)
            {
               double prior=0,priorTime=0,priorType=0;
               if(!GlobalVariableGet(key+".b"+IntegerToString(j),prior) ||
                  !GlobalVariableGet(key+".u"+IntegerToString(j),priorTime) ||
                  !GlobalVariableGet(key+".v"+IntegerToString(j),priorType)) { readable=false; match=false; break; }
               if((int)prior==ticket || ((datetime)priorTime==OrderOpenTime() && (int)priorType==OrderType()) ||
                  (OrderType()<=OP_SELL && (int)priorType==OrderType())) match=false; // 既存建玉の部分決済後継を新規約定と誤認しない。
            }
         }
         if(match && OrderTicket()!=found) { found=OrderTicket(); matches++; }
      }
   }
   if(!readable || matches!=1) return(-1);
   gSendKnownTicket=found;
   if(!IsTesting() && GlobalVariableSet(key+".k",found)==0) return(-1);
   if(FinishSendRecord()) return(found);
   return(-1);
}

int gInstanceHandle=INVALID_HANDLE;
bool gTimerEvent=false;
uint gLastQuoteReceived=0;

int OnInit()
{
   gInitialized=false;
   gLogIdentity="ea="+COMMENT+" symbol="+Symbol()+" magic="+IntegerToString(MAGIC)+
                " chart="+IntegerToString(ChartID())+" session="+IntegerToString((long)TimeLocal())+" ";
   if(StringSubstr(Symbol(),0,6)!="USDJPY" || Period()!=PERIOD_H1 ||
      En_bars<1 || SL_bars<1 || ATRPeriod<1 || SLLimitPips<=0 || TimeStopBars<1 ||
      ATRShift<0 || ATRShift>1 || HalfATRMult<=0 || TrailATRMult<=0 || MaxOpenPositions<0 ||
      MaxSpreadPips<=0 || Slippage<0 || EntryRiskPercent<=0 ||
      FreeMarginBufferPercent<0 || FreeMarginBufferPercent>=100){
      Print(gLogIdentity,"event=INIT_PARAMETERS_INVALID");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(!TC_Init(TRADE_INTERVAL_MS)) return(INIT_FAILED);
   if(!IsTesting())
   {
      gInstanceHandle=FileOpen("EA.instance."+MailScope(MAGIC)+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(gInstanceHandle==INVALID_HANDLE) { Print("event=INSTANCE_LOCK_FAILED ea=",COMMENT," error=",GetLastError()); return(INIT_FAILED); }
      if(!EventSetTimer(1)) return(INIT_FAILED);
      MailReconcile(COMMENT,MAGIC,false,true);
   }
   gPipsPoint=Point*((Digits==3 || Digits==5) ? 10.0 : 1.0);
   gStartedTime=TimeCurrent(); gStartedTick=GetTickCount();
   gPreviousBar=0; gPairBar=0; gPairStarted=0; gPairStartedTick=0;
   gBuyStopTicket=-1; gSellStopTicket=-1; gPairState=PAIR_CANCEL;
   gTimeCursor=-1; gHalfCursor=0; gTrailCursor=-1; gReleasePending=false;
   ArrayResize(gHalfRecords,0); ArrayResize(gEntryMailTickets,0);
   gSendKey="S1S_"+AccountServer()+"_"+IntegerToString(AccountNumber())+"_"+Symbol()+"_"+IntegerToString(MAGIC);
   gSendNumber=0;
   if(!IsTesting() && GlobalVariableCheck(gSendKey) && !GlobalVariableGet(gSendKey,gSendNumber))
      gSendStateReadable=false;
   if(gSendNumber>0){
      gPairState=PAIR_CHECK;
      Print(gLogIdentity,"event=SEND_CHECK_REQUIRED id=",DoubleToString(gSendNumber,0));
   }
   fileHandle=INVALID_HANDLE; gEquityTick=0;
   gLastEquity=AccountEquity(); gLastBalance=AccountBalance();
   if(IsTesting()){
      fileHandle=FileOpen("STR01_USDJPY_H1_rev_equity.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(fileHandle==INVALID_HANDLE) return(INIT_FAILED);
      FileWrite(fileHandle,"time","equity","balance");
   }
   // 起動時の待機注文は従来どおり取消対象とする。既存建玉は決済管理を続ける。
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS) || !OwnOrder() || OrderType()<OP_BUYLIMIT) continue;
      if(OrderType()==OP_BUYSTOP && gBuyStopTicket<0) gBuyStopTicket=OrderTicket();
      if(OrderType()==OP_SELLSTOP && gSellStopTicket<0) gSellStopTicket=OrderTicket();
      int size=ArraySize(gEntryMailTickets);
      if(ArrayResize(gEntryMailTickets,size+1)==size+1) gEntryMailTickets[size]=OrderTicket();
   }
   gInitialized=true;
   Print(gLogIdentity,"event=INIT_OK compiled=",__DATETIME__);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // 終了時は待たない。共通枠を取得できた場合だけ1件取り消し、残件を明示する。
   if(gReleasePending) gReleasePending=!TC_End(true);
   bool called=false;
   if(gInitialized && !gReleasePending) CancelAllPendingOrders(called);
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS)){
         Print(gLogIdentity,"event=DEINIT_PENDING_SCAN_FAILED index=",i);
         continue;
      }
      if(OwnOrder() && OrderType()>=OP_BUYLIMIT)
         Print(gLogIdentity,"event=DEINIT_PENDING_REMAINS ticket=",OrderTicket());
   }
   if(fileHandle!=INVALID_HANDLE){
      if(gEquityTick>0) FileWrite(fileHandle,TimeToString(gEquityTick,TIME_DATE|TIME_SECONDS),
                               DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
      FileClose(fileHandle); fileHandle=INVALID_HANDLE;
   }
   Print(gLogIdentity,"event=DEINIT reason=",reason);
   if(gInstanceHandle!=INVALID_HANDLE) { FileClose(gInstanceHandle); gInstanceHandle=INVALID_HANDLE; }
}

bool OwnOrder(){ return(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC); }

// 0=取消済み/なし、1=待機、2=保有中、3=約定後に決済済み。履歴と保有を区別する。
bool TicketState(int ticket,int &state)
{
   state=0;
   if(ticket<=0) return(true);
   if(!OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder()) return(false);
   if(OrderType()<=OP_SELL) state=OrderCloseTime()==0 ? 2 : 3;
   else if(OrderCloseTime()==0) state=1;
   return(true);
}

// 通常時と終了時に共用する取消処理。実APIは最大1回、未取消/読取失敗ならfalse。
bool CancelAllPendingOrders(bool &called)
{
   bool cleared=true, readFailed=false;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS)) { readFailed=true; continue; }
      if(!OwnOrder() || OrderType()<OP_BUYLIMIT) continue;
      cleared=false;
      if(called || gReleasePending || (!IsTesting() && !IsConnected()) || !TC_Begin()) continue;
      int ticket=OrderTicket();
      // 実行権の取得後に再選択する。待機中に約定した注文は取消対象から外す。
      if(!OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder() || OrderCloseTime()!=0 || OrderType()<OP_BUYLIMIT){
         TC_End(false); continue;
      }
      RefreshRates();
      double freeze=MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point;
      double distance=OrderType()==OP_BUYLIMIT ? Ask-OrderOpenPrice() :
                      OrderType()==OP_SELLLIMIT ? OrderOpenPrice()-Bid :
                      OrderType()==OP_BUYSTOP ? OrderOpenPrice()-Ask : Bid-OrderOpenPrice();
      if(Point<=0 || freeze<0 || distance<=freeze){ TC_End(false); continue; }
      ResetLastError();
      bool deleted=OrderDelete(ticket);
      int error=GetLastError();
      gReleasePending=!TC_End(true); called=true;
      Print(gLogIdentity,"event=TRADE_REQUEST_DONE action=CANCEL ticket=",ticket," error=",error," success=",deleted);
   }
   // API成功だけでは完了扱いにせず、次Tickの注文照合を経て状態を進める。
   return(cleared && !readFailed);
}

// 初回計算と送信直前の再確認を共用。1=有効、0=条件不成立、-1=注文を読めない。
int PairConditions(Prices &p,double &lots,bool submitting)
{
   double point=MarketInfo(Symbol(),MODE_POINT), tick=MarketInfo(Symbol(),MODE_TICKSIZE);
   double stop=MarketInfo(Symbol(),MODE_STOPLEVEL);
   if(point<=0 || tick<=0 || stop<0) return(0);
   double minimum=submitting ? MathMax(1.0,MathCeil(stop*Point/tick))*tick :
                               MathMax(1.0,MathCeil(stop/(tick/point)))*tick;
   double tolerance=point/10.0;
   if(!submitting){
      double alignedBuy=NormalizeDouble(MathRound(p.buy/tick)*tick,Digits);
      double alignedBuySL=NormalizeDouble(MathRound(p.buySL/tick)*tick,Digits);
      double alignedSell=NormalizeDouble(MathRound(p.sell/tick)*tick,Digits);
      double alignedSellSL=NormalizeDouble(MathRound(p.sellSL/tick)*tick,Digits);
      if(MathAbs(p.buy-alignedBuy)>tolerance || MathAbs(p.buySL-alignedBuySL)>tolerance ||
         MathAbs(p.sell-alignedSell)>tolerance || MathAbs(p.sellSL-alignedSellSL)>tolerance) return(0);
      p.buy=alignedBuy; p.buySL=alignedBuySL; p.sell=alignedSell; p.sellSL=alignedSellSL;
   }
   int positions=0;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS)) return(-1);
      if(!OwnOrder() || OrderType()>OP_SELL) continue;
      positions++;
      double price=NormalizeDouble(MathRound(OrderOpenPrice()/tick)*tick,Digits);
      if((OrderType()==OP_BUY && MathAbs(price-p.buy)<=tolerance) ||
         (OrderType()==OP_SELL && MathAbs(price-p.sell)<=tolerance)) return(0);
   }
   RefreshRates();
   if((MaxOpenPositions>0 && positions>=MaxOpenPositions) || Ask<=Bid ||
      Ask-Bid>MaxSpreadPips*gPipsPoint || p.buy-Ask<minimum || Bid-p.sell<minimum ||
      p.buy-p.buySL<minimum || p.sellSL-p.sell<minimum ||
      p.buy-p.buySL>=SLLimitPips*gPipsPoint || p.sellSL-p.sell>=SLLimitPips*gPipsPoint) return(0);
   double value=MarketInfo(Symbol(),MODE_TICKVALUE), step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT), maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(value<=0 || step<=0 || minLot<=0 || maxLot<minLot) return(0);
   double buyLoss=(p.buy-p.buySL)/tick*value, sellLoss=(p.sellSL-p.sell)/tick*value;
   double capital=MathMin(AccountBalance(),AccountEquity());
   double risk=capital*EntryRiskPercent/100.0;
   double rawLots=MathMin(MathMin(risk/buyLoss,risk/sellLoss),maxLot);
   double halfLots=NormalizeLotsDown(rawLots/2.0,step);
   lots=NormalizeDouble(halfLots*2.0,8);
   if(halfLots<minLot || NormalizeDouble(lots-halfLots,8)<minLot || lots>maxLot+1e-8) return(0);
   ResetLastError();
   double buyMargin=AccountFreeMarginCheck(Symbol(),OP_BUY,lots);
   int buyError=GetLastError();
   ResetLastError();
   double sellMargin=AccountFreeMarginCheck(Symbol(),OP_SELL,lots);
   int sellError=GetLastError();
   return(buyError==0 && sellError==0 && buyMargin>=capital*FreeMarginBufferPercent/100.0 &&
          sellMargin>=capital*FreeMarginBufferPercent/100.0 ? 1 : 0);
}

// 半分決済の記録はAPI前にも保存する。負値の間は結果不明でも再決済しない。
// baseLotsは決済前数量。予定残量と一緒に保存し、再起動後の照合にも使用する。
bool SaveHalfClose(string key,double value,double baseLots=0)
{
   if(!IsTesting()){
      if(baseLots>0 && GlobalVariableSet(key+"_B",baseLots)==0) return(false);
      if(GlobalVariableSet(key,value)==0) return(false);
      GlobalVariablesFlush();
   }
   for(int i=0;i<ArraySize(gHalfRecords);i++){
      if(gHalfRecords[i].key==key){
         gHalfRecords[i].value=value;
         if(baseLots>0) gHalfRecords[i].baseLots=baseLots;
         return(true);
      }
   }
   int size=ArraySize(gHalfRecords);
   if(ArrayResize(gHalfRecords,size+1)!=size+1) return(false);
   gHalfRecords[size].key=key; gHalfRecords[size].value=value; gHalfRecords[size].baseLots=baseLots;
   return(true);
}

bool IsHalfCloseDone(string &key)
{
   double tick=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tick<=0 || Point<=0) return(true);
   string prefix="S1H_"+IntegerToString(AccountNumber())+"_"+Symbol()+"_"+IntegerToString(MAGIC)+"_"+
                 IntegerToString(OrderType())+"_"+IntegerToString((int)OrderOpenTime())+"_";
   key=prefix+DoubleToString(MathRound(OrderOpenPrice()/tick),0);
   // 旧版が保存したキーも読む。既存建玉を改修後にもう一度半分決済しない。
   string legacy=prefix+DoubleToString(MathRound(OrderOpenPrice()/(tick*Point)),0);
   double value=0, baseLots=0;
   for(int i=0;i<ArraySize(gHalfRecords);i++)
      if(gHalfRecords[i].key==key || gHalfRecords[i].key==legacy){
         value=gHalfRecords[i].value; baseLots=gHalfRecords[i].baseLots;
      }
   if(!IsTesting()){
      if(GlobalVariableCheck(legacy)) return(true);
      if(GlobalVariableCheck(key) && !GlobalVariableGet(key,value)) return(true);
      if(value<0 && !GlobalVariableGet(key+"_B",baseLots)) return(true);
   }
   if(value<0 && baseLots>-value && OrderLots()<=-value+1e-8){
      // 実注文の残量が予定以下なら、応答を失っていても半分決済済みと確認できる。
      if(!SaveHalfClose(key,1)) Print(gLogIdentity,"event=HALF_SAVE_FAILED key=",key);
   }
   return(value!=0); // 未確認の負値も再送せず、次Tickの残量照合に回す。
}

void NotifyFills(){
   for(int i=ArraySize(gEntryMailTickets)-1;i>=0;i--){
      if(!OrderSelect(gEntryMailTickets[i],SELECT_BY_TICKET)) continue;
      if(OwnOrder()){
         if(OrderType()==OP_BUY || OrderType()==OP_SELL) MailNotifySelected(COMMENT,MAGIC,false);
         else if(OrderCloseTime()==0) continue;
      }
      int last=ArraySize(gEntryMailTickets)-1;
      gEntryMailTickets[i]=gEntryMailTickets[last];
      ArrayResize(gEntryMailTickets,last);
   }
}
bool CanCloseSelected(int type,double freeze){
   if(freeze<=0) return(true);
   double sl=NormalizeDouble(type==OP_BUY ? Bid-OrderStopLoss() : OrderStopLoss()-Ask,Digits);
   double tp=NormalizeDouble(type==OP_BUY ? OrderTakeProfit()-Bid : Ask-OrderTakeProfit(),Digits);
   return(!((OrderStopLoss()>0 && sl<=freeze) || (OrderTakeProfit()>0 && tp<=freeze)));
}
bool CanModifySelected(int type,double stop,double minimum,double freeze){
   double distance=NormalizeDouble(type==OP_BUY ? Bid-stop : stop-Ask,Digits);
   double tp=NormalizeDouble(type==OP_BUY ? OrderTakeProfit()-Bid : Ask-OrderTakeProfit(),Digits);
   return(distance>=minimum && !(freeze>0 && distance<=freeze) &&
          !(OrderTakeProfit()>0 && (tp<minimum || (freeze>0 && tp<=freeze))));
}

// 売買の順序を上から読む。共通枠を待っても、新バー評価や記録は続ける。
void OnTimer()
{
   gTimerEvent=true;
   OnTick();
   gTimerEvent=false;
}
void OnTick()
{
   if(!gTimerEvent) gLastQuoteReceived=GetTickCount();
   if(gReleasePending) gReleasePending=!TC_End(true);
   MailReconcile(COMMENT,MAGIC,false,true);
   bool quoteFresh=!gTimerEvent || (IsConnected() && gLastQuoteReceived!=0 && (uint)(GetTickCount()-gLastQuoteReceived)<=10000);
   if(!gSendStateReadable && !IsTesting())
   {
      double restored=0;
      if(GlobalVariableGet(gSendKey,restored) && MathIsValidNumber(restored)) { gSendNumber=restored; gSendStateReadable=true; }
   }
   if(!gInitialized) return;
   bool called=false;
   if(gReleasePending) gReleasePending=!TC_End(true); // 注文は再送せず、解放だけ再試行。
   bool startupReady=IsTesting() ? TimeCurrent()-gStartedTime>=2 :
                                  (uint)(GetTickCount()-gStartedTick)>=2000;
   startupReady=startupReady && (IsTesting() || IsConnected());
   NotifyFills();

   // ① 不明なOrderSendを実注文・履歴で探す。見つからないだけでは未送信と断定しない。
   if(gSendNumber>0){
      int found=ResolveSendRecord();
      if(found>0 && OrderSelect(found,SELECT_BY_TICKET)){
         int foundType=OrderType();
         if(foundType==OP_BUY || foundType==OP_BUYSTOP) gBuyStopTicket=found;
         else if(foundType==OP_SELL || foundType==OP_SELLSTOP) gSellStopTicket=found;
         gPairState=PAIR_CANCEL; gPairBar=0;
         Print(gLogIdentity,"event=SEND_RECONCILED ticket=",found);
      }
      else if(gSendNumber<=0) { gPairState=PAIR_CANCEL; gPairBar=0; }
   }

   // ② OCOの照合。約定・期限切れなら、残った待機注文を取り消す。
   int buy=0, sell=0;
   bool readable=TicketState(gBuyStopTicket,buy);
   if(!TicketState(gSellStopTicket,sell)) readable=false;
   if(!readable){
      gPairBar=0;
      if(startupReady && !gReleasePending) CancelAllPendingOrders(called);
   }
   if(readable && buy==2 && sell==2){
      if(gPairState!=PAIR_DOUBLE) Alert(gLogIdentity,"event=OCO_DOUBLE_FILL buyTicket=",gBuyStopTicket," sellTicket=",gSellStopTicket);
      gPairState=PAIR_DOUBLE; gPairBar=0;
   }
   else if(readable){
      bool expired=gPairBar>0 && (iTime(NULL,PERIOD_H1,0)!=gPairBar ||
                   (gPairStarted>0 && (IsTesting() ? TimeCurrent()-gPairStarted>(int)MyOrderWaitingTime :
                    (uint)(GetTickCount()-gPairStartedTick)>MyOrderWaitingTime*1000)));
      if(buy>=2 || sell>=2 || expired || gPairState==PAIR_DOUBLE ||
         (gPairState==PAIR_ACTIVE && (buy!=1 || sell!=1)) || (gPairState==PAIR_SELL && buy!=1)){
         // 旧ペア取消中に片側が約定しても、次ペアの予約まで消さない。
         if(expired || gPairState!=PAIR_CANCEL) gPairBar=0;
         if(gSendNumber<=0) gPairState=PAIR_CANCEL;
      }
      if((gPairState==PAIR_CANCEL || gPairState==PAIR_CHECK) && startupReady && !gReleasePending){
         bool cleared=CancelAllPendingOrders(called);
         // 取消中の約定も再照合する。チケットはこの確認が済むまで保持する。
         readable=TicketState(gBuyStopTicket,buy);
         if(!TicketState(gSellStopTicket,sell)) readable=false;
         if(readable && buy==2 && sell==2){
            Alert(gLogIdentity,"event=OCO_DOUBLE_FILL buyTicket=",gBuyStopTicket," sellTicket=",gSellStopTicket);
            gPairState=PAIR_DOUBLE; gPairBar=0;
         }
         else if(cleared && readable && buy!=1 && sell!=1 && gSendNumber<=0){
            gBuyStopTicket=-1; gSellStopTicket=-1;
            gPairState=gPairBar>0 ? PAIR_BUY : PAIR_IDLE;
         }
      }
   }

   // ③ 前Tickからの予約だけを送る。順番待ちでは予約や5秒期限を作り直さない。
   if(gSendStateReadable && quoteFresh && readable && startupReady && !called && !gReleasePending &&
      (gPairState==PAIR_BUY || gPairState==PAIR_SELL) && TC_Begin()){
      double lots=0;
      int valid=PairConditions(gPairPrice,lots,true);
      int leg=0;
      bool legReadable=TicketState(gBuyStopTicket,leg);
      RefreshRates();
      double tick=MarketInfo(Symbol(),MODE_TICKSIZE);
      double minimum=tick>0 ? MathMax(1.0,MathCeil(MarketInfo(Symbol(),MODE_STOPLEVEL)*Point/tick))*tick : 0;
      bool expired=iTime(NULL,PERIOD_H1,0)!=gPairBar || (gPairStarted>0 && (IsTesting() ?
         TimeCurrent()-gPairStarted>(int)MyOrderWaitingTime : (uint)(GetTickCount()-gPairStartedTick)>MyOrderWaitingTime*1000));
      if(valid<0 || !legReadable){ TC_End(false); }
      else if(valid==0 || MathAbs(lots-gPairLots)>1e-8 || expired ||
              (gPairState==PAIR_SELL && leg!=1) || Ask<=Bid || Ask-Bid>MaxSpreadPips*gPipsPoint ||
              gPairPrice.buy-Ask<minimum || Bid-gPairPrice.sell<minimum){
         TC_End(false); gPairState=PAIR_CANCEL; gPairBar=0;
      }
      else{
         int type=gPairState==PAIR_BUY ? OP_BUYSTOP : OP_SELLSTOP;
         // 同一EA内だけの送信番号。API前に保存し、応答直後の異常終了にも備える。
         gSendNumber=MathMax(MathAbs(gSendNumber)+1,(double)TimeLocal()*1000.0);
         if(!PrepareSendRecord(type,gPairLots)){
            TC_End(false); gPairState=PAIR_CHECK;
            Print(gLogIdentity,"event=SEND_SAVE_FAILED");
         }
         else{
            if(!IsTesting()) GlobalVariablesFlush();
            // 保存中の価格変化・片側約定・期限切れも、実API直前に確認する。
            legReadable=TicketState(gBuyStopTicket,leg);
            RefreshRates();
            expired=iTime(NULL,PERIOD_H1,0)!=gPairBar || (gPairStarted>0 && (IsTesting() ?
               TimeCurrent()-gPairStarted>(int)MyOrderWaitingTime : (uint)(GetTickCount()-gPairStartedTick)>MyOrderWaitingTime*1000));
            if((!IsTesting() && !IsConnected()) || !legReadable || (type==OP_SELLSTOP && leg!=1) || expired || Ask<=Bid ||
               Ask-Bid>MaxSpreadPips*gPipsPoint || gPairPrice.buy-Ask<minimum || Bid-gPairPrice.sell<minimum){
               gSendCancelPending=true;
               bool cleared=FinishSendRecord();
               if(cleared) gSendNumber=-MathAbs(gSendNumber);
               if(!IsTesting()) GlobalVariablesFlush();
               TC_End(false);
               if(!cleared){ gPairState=PAIR_CHECK; gPairBar=0; }
               else if(IsTesting() || IsConnected()){ gPairState=PAIR_CANCEL; gPairBar=0; }
               // 接続断だけなら未送信の予約を維持する。期限は次Tickでも確認する。
            }
            else{
               if(gPairStarted==0){ gPairStarted=TimeCurrent(); gPairStartedTick=GetTickCount(); }
               if(!CommitSendRecord()) { TC_End(false); gPairState=PAIR_CHECK; return; }
               ResetLastError();
               int ticket=OrderSend(Symbol(),type,gPairLots,type==OP_BUYSTOP ? gPairPrice.buy : gPairPrice.sell,
                                   Slippage,type==OP_BUYSTOP ? gPairPrice.buySL : gPairPrice.sellSL,0,
                                   "R"+DoubleToString(gSendNumber,0)+"|"+COMMENT,MAGIC,0,type==OP_BUYSTOP ? clrBlue : clrRed);
               int error=GetLastError();
               gReleasePending=!TC_End(true); called=true;
               Print(gLogIdentity,"event=TRADE_REQUEST_DONE action=SEND ticket=",ticket," error=",error," success=",ticket>0);
               bool unknown=ticket<=0 && (error==0 || error==ERR_NO_RESULT || error==ERR_COMMON_ERROR ||
                                          error==ERR_NO_CONNECTION || error==ERR_TRADE_TIMEOUT);
               gSendKnownTicket=ticket; gSendFinished=!unknown;
               if(ticket>0 && !IsTesting()) GlobalVariableSet(SendRecordKey()+".k",ticket);
               bool saved=false;
               if(!unknown) saved=FinishSendRecord();
               if(unknown){
                  // API前に保存した正の印を保持する。空の注文一覧だけでは再開しない。
                  gPairState=PAIR_CHECK; gPairBar=0;
               }
               else if(saved) gSendNumber=-MathAbs(gSendNumber);
               else { gPairState=PAIR_CHECK; gPairBar=0; }
               if(!IsTesting()) GlobalVariablesFlush();
               if(ticket>0){
                  if(type==OP_BUYSTOP) gBuyStopTicket=ticket; else gSellStopTicket=ticket;
                  if(saved){
                     gPairState=type==OP_BUYSTOP ? PAIR_SELL : PAIR_ACTIVE;
                     if(type==OP_SELLSTOP) gPairBar=0; // 5秒は設置の期限。成立済みペアの寿命ではない。
                  }
                  int size=ArraySize(gEntryMailTickets);
                  if(ArrayResize(gEntryMailTickets,size+1)==size+1) gEntryMailTickets[size]=ticket;
               }
               else if(!unknown && saved && error!=ERR_TOO_FREQUENT_REQUESTS && error!=141){
                  gPairState=PAIR_CANCEL; gPairBar=0;
               }
            }
         }
      }
   }

   // ④ 新バーは一度だけ評価。ここで作った候補の実発注は次Tick以降とする。
   if(!gTimerEvent && Time[0]!=gPreviousBar){
      gPreviousBar=Time[0];
      if(IsTesting() && gEquityTick>0 && (long)TimeCurrent()/86400!=(long)gEquityTick/86400)
         FileWrite(fileHandle,TimeToString(gEquityTick,TIME_DATE|TIME_SECONDS),DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
      if(gSendStateReadable && gPairState!=PAIR_CHECK && gPairState!=PAIR_DOUBLE && readable){
         Prices candidate;
         ZeroMemory(candidate);
         double lots=0;
         bool valid=Bars>MathMax(MathMax(En_bars,SL_bars),ATRPeriod+ATRShift)+1;
         if(valid){
            candidate.buy=High[iHighest(NULL,0,MODE_HIGH,En_bars,1)];
            candidate.buySL=Low[iLowest(NULL,0,MODE_LOW,SL_bars,1)];
            candidate.sell=Low[iLowest(NULL,0,MODE_LOW,En_bars,1)];
            candidate.sellSL=High[iHighest(NULL,0,MODE_HIGH,SL_bars,1)];
            valid=PairConditions(candidate,lots,false)==1;
         }
         bool retained=valid && gPairState==PAIR_ACTIVE;
         int count=0;
         for(int i=OrdersTotal()-1;i>=0;i--){
            if(!OrderSelect(i,SELECT_BY_POS)){ retained=false; break; }
            if(!OwnOrder() || OrderType()<OP_BUYLIMIT) continue;
            count++;
            if(!valid){ retained=false; continue; }
            bool isBuy=OrderType()==OP_BUYSTOP;
            if((!isBuy && OrderType()!=OP_SELLSTOP) || MathAbs(OrderLots()-lots)>1e-8 ||
               OrderTakeProfit()!=0 || OrderExpiration()!=0 ||
               MathAbs(OrderOpenPrice()-(isBuy ? candidate.buy : candidate.sell))>Point/10.0 ||
               MathAbs(OrderStopLoss()-(isBuy ? candidate.buySL : candidate.sellSL))>Point/10.0) retained=false;
         }
         if(!retained || count!=2){
            gPairBar=valid ? Time[0] : 0;
            if(valid){ gPairPrice=candidate; gPairLots=lots; }
            gPairStarted=0; gPairStartedTick=0;
            gPairState=PAIR_CANCEL;
         }
      }
   }

   // ⑤ 退出処理は時間決済→半分決済→追尾の順。失敗したticketに枠を独占させない。
   double atr=iATR(NULL,PERIOD_H1,ATRPeriod,ATRShift);
   int halfPoints=int(atr*HalfATRMult/Point), trailPoints=int(atr*TrailATRMult/Point);
   double exitTick=MarketInfo(Symbol(),MODE_TICKSIZE);
   double exitStop=NormalizeDouble(MarketInfo(Symbol(),MODE_STOPLEVEL)*Point,Digits);
   double exitFreeze=NormalizeDouble(MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point,Digits);
   int total=OrdersTotal();
   int start=gTimeCursor>=0 && gTimeCursor<total ? gTimeCursor : total-1;
   for(int offset=0;offset<total && !gTimerEvent && quoteFresh && startupReady && !called && !gReleasePending;offset++){
      int index=(start-offset+total)%total;
      if(!OrderSelect(index,SELECT_BY_POS) || !OwnOrder() || OrderType()>OP_SELL) continue;
      if(iBarShift(NULL,PERIOD_H1,OrderOpenTime())<TimeStopBars || OrderProfit()+OrderSwap()+OrderCommission()>=0) continue;
      int ticket=OrderTicket();
      if(!TC_Begin()) break;
      RefreshRates();
      if(!OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder() || OrderCloseTime()!=0 || OrderType()>OP_SELL ||
         iBarShift(NULL,PERIOD_H1,OrderOpenTime())<TimeStopBars || OrderProfit()+OrderSwap()+OrderCommission()>=0 ||
         !CanCloseSelected(OrderType(),exitFreeze)){ TC_End(false); continue; }
      ResetLastError();
      bool closed=OrderClose(ticket,OrderLots(),OrderType()==OP_BUY ? Bid : Ask,Slippage,OrderType()==OP_BUY ? clrBlue : clrRed);
      int error=GetLastError();
      gReleasePending=!TC_End(true); called=true; gTimeCursor=index-1;
      Print(gLogIdentity,"event=TRADE_REQUEST_DONE action=TIME_STOP ticket=",ticket," error=",error," success=",closed);
   }

   total=OrdersTotal(); start=gHalfCursor>=0 && gHalfCursor<total ? gHalfCursor : 0;
   for(int offset=0;offset<total && !gTimerEvent && quoteFresh && startupReady && !called && !gReleasePending && halfPoints>0;offset++){
      int index=(start+offset)%total;
      if(!OrderSelect(index,SELECT_BY_POS) || !OwnOrder() || OrderType()>OP_SELL) continue;
      string key="";
      if(IsHalfCloseDone(key)) continue;
      double distance=OrderType()==OP_BUY ? Bid-OrderOpenPrice() : OrderOpenPrice()-Ask;
      if(distance<=halfPoints*Point) continue;
      int ticket=OrderTicket();
      if(!TC_Begin()) break;
      RefreshRates();
      if(!OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder() || OrderCloseTime()!=0 || OrderType()>OP_SELL || IsHalfCloseDone(key)){
         TC_End(false); continue;
      }
      distance=OrderType()==OP_BUY ? Bid-OrderOpenPrice() : OrderOpenPrice()-Ask;
      double closeLots=NormalizeLotsDown(OrderLots()/2.0,MarketInfo(Symbol(),MODE_LOTSTEP));
      double remaining=NormalizeDouble(OrderLots()-closeLots,8), minimum=MarketInfo(Symbol(),MODE_MINLOT);
      if(distance<=halfPoints*Point || closeLots<minimum || remaining<minimum || !CanCloseSelected(OrderType(),exitFreeze)){
         TC_End(false); continue;
      }
      // 決済前に予定残量を保存。タイムアウトや異常終了後も未決済扱いには戻さない。
      if(!SaveHalfClose(key,-remaining,OrderLots())){
         TC_End(false); Print(gLogIdentity,"event=HALF_SAVE_FAILED key=",key); continue;
      }
      RefreshRates();
      if((!IsTesting() && !IsConnected()) || !OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder() || OrderCloseTime()!=0 || OrderType()>OP_SELL ||
         MathAbs(OrderLots()-closeLots-remaining)>1e-8 ||
         (OrderType()==OP_BUY ? Bid-OrderOpenPrice() : OrderOpenPrice()-Ask)<=halfPoints*Point ||
         !CanCloseSelected(OrderType(),exitFreeze)){
         if(!SaveHalfClose(key,0)) Print(gLogIdentity,"event=HALF_SAVE_FAILED key=",key);
         TC_End(false); continue;
      }
      ResetLastError();
      bool closed=OrderClose(ticket,closeLots,OrderType()==OP_BUY ? Bid : Ask,Slippage,OrderType()==OP_BUY ? clrDodgerBlue : clrIndianRed);
      int error=GetLastError();
      gReleasePending=!TC_End(true); called=true; gHalfCursor=(index+1)%total;
      bool unknown=!closed && (error==0 || error==ERR_NO_RESULT || error==ERR_COMMON_ERROR || error==ERR_NO_CONNECTION || error==ERR_TRADE_TIMEOUT);
      if(!unknown && !SaveHalfClose(key,closed ? 1 : 0)) Print(gLogIdentity,"event=HALF_SAVE_FAILED key=",key);
      Print(gLogIdentity,"event=TRADE_REQUEST_DONE action=PARTIAL ticket=",ticket," error=",error," success=",closed);
   }

   total=OrdersTotal(); start=gTrailCursor>=0 && gTrailCursor<total ? gTrailCursor : total-1;
   for(int offset=0;offset<total && !gTimerEvent && quoteFresh && startupReady && !called && !gReleasePending && trailPoints>0 && exitTick>0 && exitStop>=0 && exitFreeze>=0;offset++){
      int index=(start-offset+total)%total;
      if(!OrderSelect(index,SELECT_BY_POS) || !OwnOrder() || OrderType()>OP_SELL) continue;
      int ticket=OrderTicket();
      double stop=OrderType()==OP_BUY ? NormalizeDouble(MathFloor((Bid-trailPoints*Point)/exitTick+1e-7)*exitTick,Digits) :
                                       NormalizeDouble(MathCeil((Ask+trailPoints*Point)/exitTick-1e-7)*exitTick,Digits);
      bool improves=OrderType()==OP_BUY ? stop>=OrderOpenPrice() && (OrderStopLoss()==0 || stop>OrderStopLoss()+0.5*Point) :
                                         stop<=OrderOpenPrice() && (OrderStopLoss()==0 || stop<OrderStopLoss()-0.5*Point);
      if(!improves || !CanModifySelected(OrderType(),stop,exitStop,exitFreeze)) continue;
      if(!TC_Begin()) break;
      RefreshRates();
      if(!OrderSelect(ticket,SELECT_BY_TICKET) || !OwnOrder() || OrderCloseTime()!=0 || OrderType()>OP_SELL){ TC_End(false); continue; }
      stop=OrderType()==OP_BUY ? NormalizeDouble(MathFloor((Bid-trailPoints*Point)/exitTick+1e-7)*exitTick,Digits) :
                                NormalizeDouble(MathCeil((Ask+trailPoints*Point)/exitTick-1e-7)*exitTick,Digits);
      improves=OrderType()==OP_BUY ? stop>=OrderOpenPrice() && (OrderStopLoss()==0 || stop>OrderStopLoss()+0.5*Point) :
                                   stop<=OrderOpenPrice() && (OrderStopLoss()==0 || stop<OrderStopLoss()-0.5*Point);
      if(!improves || !CanModifySelected(OrderType(),stop,exitStop,exitFreeze)){ TC_End(false); continue; }
      ResetLastError();
      bool modified=OrderModify(ticket,OrderOpenPrice(),stop,OrderTakeProfit(),0,OrderType()==OP_BUY ? clrBlue : clrRed);
      int error=GetLastError();
      gReleasePending=!TC_End(true); called=true; gTrailCursor=index-1;
      Print(gLogIdentity,"event=TRADE_REQUEST_DONE action=TRAIL ticket=",ticket," error=",error," success=",modified);
   }
   if(IsTesting()){ gEquityTick=TimeCurrent(); gLastEquity=AccountEquity(); gLastBalance=AccountBalance(); }
}
