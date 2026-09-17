//+------------------------------------------------------------------+
//|                                              STR01_USDJPY_H1.mq4 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

/*
売買ロジック
- En:
  新バーごとに既存の待機注文を取り消し、確定済み直近En_bars本の最高値へBuy Stop、最安値へSell Stopを同一ロットでOCO発注する。
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

#include <stderror.mqh>
#include <stdlib.mqh>
#include <WinUser32.mqh>
#include <Original/MyLib.mqh>
#include <Original/OCO.mqh>
#include <Original/Basic.mqh>
#include <Original/DateAndTime.mqh>
#include <Original/LotSizing.mqh>
#include <Original/RiskManagement.mqh>
#include <Original/Mail.mqh>
#include <Original/Tracker.mqh>

#define MAGIC 20260912
#define COMMENT "STR01_USDJPY_H1"

//+------------------------------------------------------------------+
//| EAパラメータ設定情報                                             |
//+------------------------------------------------------------------+
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
extern int MaxOpenPositions = 6; // 0: legacy unlimited entries, for comparison
extern double MaxSpreadPips = 2.0;


//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
// 共通
double gPipsPoint     = 0.0;
int    gSlippage      = 0;
color  gArrowColor[6] = {Blue, Red, Blue, Red, Blue, Red}; //BUY: Blue, SELL: Red
int    fileHandle;
datetime gEquityTick = 0;
double gLastEquity = 0;
double gLastBalance = 0;
int    orders_cnt;
int    gBuyStopTicket = -1;               // OCO注文のticket番号を保持する変数、-1は未保持
int    gSellStopTicket = -1;
bool   gPendingRecoveryRequired = true;
bool   gPairRollbackRequired = false;
bool   gRiskConfigValid = false;
double order_price,TP,SL;
string gHalfClosedKeys[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{  
  gBuyStopTicket = -1;
  gSellStopTicket = -1;
  gPendingRecoveryRequired = true;
  gPairRollbackRequired = false;
  gRiskConfigValid = false;
  order_price = 0;
  TP = 0;
  SL = 0;
  ArrayResize(gHalfClosedKeys,0);
  fileHandle = INVALID_HANDLE;
  gEquityTick = 0;
  gLastEquity = AccountEquity();
  gLastBalance = AccountBalance();
  gPipsPoint = Point;
  if(Digits == 3 || Digits == 5) gPipsPoint *= 10.0;
  if(StringSubstr(Symbol(),0,6)!="USDJPY" || Period()!=PERIOD_H1){
     Print("[STR01_rev] USDJPY H1 is required.");
     return(INIT_PARAMETERS_INCORRECT);
  }
  if(En_bars<1 || SL_bars<1 || ATRPeriod<1 || SLLimitPips<=0 ||
     TimeStopBars<1 || ATRShift<0 || ATRShift>1 ||
     HalfATRMult<=0 || TrailATRMult<=0 || MaxOpenPositions<0 ||
     MaxSpreadPips<=0 || Slippage<0){
     Print("[STR01_rev] Invalid strategy parameter.");
     return(INIT_PARAMETERS_INCORRECT);
  }
  if(EntryRiskPercent<=0 ||
     FreeMarginBufferPercent<0 || FreeMarginBufferPercent>=100){
     Print("[STR01] Invalid risk parameter. entryRiskPercent=",EntryRiskPercent,
           " freeMarginBufferPercent=",FreeMarginBufferPercent);
     return(INIT_PARAMETERS_INCORRECT);
  }
  if(IsTesting()){
     fileHandle = FileOpen("STR01_USDJPY_H1_rev_equity.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
     if(fileHandle==INVALID_HANDLE){
        Print("[STR01_rev] Cannot open tester equity output. error=",GetLastError());
        return(INIT_FAILED);
     }
     FileWrite(fileHandle,"time","equity","balance");
  }
  gRiskConfigValid = true;
  return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  if(gRiskConfigValid) CancelAllPendingOrders(MAGIC);
  if(fileHandle!=INVALID_HANDLE){
     if(gEquityTick>0) FileWrite(fileHandle,TimeToString(gEquityTick,TIME_DATE|TIME_SECONDS),
                               DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
     FileClose(fileHandle);
  }
  fileHandle = INVALID_HANDLE;
  gBuyStopTicket = -1;
  gSellStopTicket = -1;
  gPendingRecoveryRequired = true;
  gPairRollbackRequired = false;
  ArrayResize(gHalfClosedKeys,0);
}

//待機注文数をカウント
int CountPendingOrders(int magic)
{
   int pendingOrderCount = 0;
   for(int i=0;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      int type = OrderType();
      // 待機中オーダーかどうかを判定
      if (type == OP_BUYLIMIT || type == OP_SELLLIMIT ||
          type == OP_BUYSTOP  || type == OP_SELLSTOP)
      {
          pendingOrderCount++;
      }
   }
   return(pendingOrderCount);
}

// 指値注文をすべてキャンセルする関数
// FREEZELEVEL内の待機注文削除を避け、削除未完了時は新規発注を抑止する
bool CancelAllPendingOrders(int magic){
   bool result;
   bool allDeleted = true;
   int totalOrders = OrdersTotal();
   for (int i = totalOrders - 1; i >= 0; i--) {
      // 注文選択失敗を取消未完了として扱い、新規発注を抑止する
      if(OrderSelect(i,SELECT_BY_POS)==false){
         allDeleted = false;
         break;
      }
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      int type = OrderType();
      // 指値注文の種類をチェック（Buy Limit, Sell Limit, Buy Stop, Sell Stop）
      if(type == OP_BUYLIMIT || type == OP_SELLLIMIT || type == OP_BUYSTOP || type == OP_SELLSTOP){
         // FREEZELEVEL内の待機注文には削除要求を送信しない
         int ticket = OrderTicket();
         double pointPrice = MarketInfo(Symbol(),MODE_POINT);
         double freezeLevelPoints = MarketInfo(Symbol(),MODE_FREEZELEVEL);
         if(pointPrice<=0 || freezeLevelPoints<0){
            Print("[STR01] Invalid symbol property for pending cancellation. ticket=",ticket,
                  " point=",pointPrice," freezeLevelPoints=",freezeLevelPoints);
            allDeleted = false;
            continue;
         }

         RefreshRates();
         double marketDistance = 0;
         if(type == OP_BUYLIMIT) marketDistance = Ask-OrderOpenPrice();
         if(type == OP_SELLLIMIT) marketDistance = OrderOpenPrice()-Bid;
         if(type == OP_BUYSTOP) marketDistance = OrderOpenPrice()-Ask;
         if(type == OP_SELLSTOP) marketDistance = Bid-OrderOpenPrice();
         double freezeDistance = freezeLevelPoints*pointPrice;
         if(marketDistance<=freezeDistance){
            Print("[STR01] Pending cancellation deferred by FREEZELEVEL. ticket=",ticket,
                  " type=",type," distance=",marketDistance," freezeDistance=",freezeDistance);
            allDeleted = false;
            continue;
         }

         result = false;
         // 待機注文をキャンセルする直前で当該注文が執行されたため、OrderDeleteできずに無限ループに陥ってしまう事象を回避
         int starttime = GetTickCount();
         while(!result){
            if(GetTickCount()-starttime > MyOrderWaitingTime*1000){
               Alert("CancelAllPendingOrders timeout. Check the experts log.");
               allDeleted = false;
               break;
            }
            // 削除失敗理由を記録し、freezeによる拒否では再試行しない
            ResetLastError();
            result = OrderDelete(ticket);
            if(result){continue;}
            int deleteError = GetLastError();
            Print("[STR01] OrderDelete failed. ticket=",ticket," error=",deleteError,
                  " ",ErrorDescription(deleteError));
            if(deleteError==ERR_TRADE_MODIFY_DENIED){
               allDeleted = false;
               break;
            }
            Sleep(100);
         }
      }
   }
   return(allDeleted);
}

// entryとSLをtick gridへ整列し、元の価格がgrid上にあるか判定する
bool AlignAndCheckTickGrid(double entryPrice,double stopPrice,double tickSizePrice,
                           int symbolDigits,double tickTolerance,
                           double &alignedEntryPrice,double &alignedStopPrice){
   alignedEntryPrice = NormalizeDouble(MathRound(entryPrice/tickSizePrice)*tickSizePrice,symbolDigits);
   alignedStopPrice = NormalizeDouble(MathRound(stopPrice/tickSizePrice)*tickSizePrice,symbolDigits);
   return(MathAbs(entryPrice-alignedEntryPrice)<=tickTolerance &&
          MathAbs(stopPrice-alignedStopPrice)<=tickTolerance);
}

// 指定した売買方向について、候補entryと同一tick価格の既存ポジションを検索する
bool FindDuplicatePosition(int orderType,double candidatePrice,double tickSizePrice,
                           int symbolDigits,double tickTolerance,bool &duplicateEntry){
   duplicateEntry = false;
   for(int orderIndex=OrdersTotal()-1;orderIndex>=0;orderIndex--){
      if(OrderSelect(orderIndex,SELECT_BY_POS)==false) return(false);
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC || OrderType()!=orderType) continue;
      double openPrice = NormalizeDouble(MathRound(OrderOpenPrice()/tickSizePrice)*tickSizePrice,symbolDigits);
      if(MathAbs(openPrice-candidatePrice)<=tickTolerance){
         duplicateEntry = true;
         break;
      }
   }
   return(true);
}

// 両側の注文に共通する取引数量を、損失額と証拠金の上限内で決定する
// 関数内でentryLotsを算出、各種チェックで発注拒否条件に引っかかった際はreturn false
bool PrepareOcoLots(double buyEntry,double buySL,double sellEntry,double sellSL,
                    double &entryLots,string &reason){
   entryLots = 0;
   // 取引数量と損失額の計算に必要な銘柄情報を取得する
   double pointPrice = MarketInfo(Symbol(),MODE_POINT);
   double tickSizePrice = MarketInfo(Symbol(),MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(),MODE_TICKVALUE);
   double minLots = MarketInfo(Symbol(),MODE_MINLOT);
   double maxLots = MarketInfo(Symbol(),MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(),MODE_LOTSTEP);
   if(pointPrice<=0 || tickSizePrice<=0 || tickValue<=0 ||
      minLots<=0 || maxLots<minLots || lotStep<=0){
      reason = "INVALID_SYMBOL_VOLUME_PROPERTY";
      return(false);
   }

   // 買いと売りの損切り価格までの予定損失額を、一ロット当たりで求める
   double buyLossPerLot = 0;
   double sellLossPerLot = 0;
   if(!CalculateLossPerLot(OP_BUY,buyEntry,buySL,tickSizePrice,tickValue,
                           0.0,buyLossPerLot) ||
      !CalculateLossPerLot(OP_SELL,sellEntry,sellSL,tickSizePrice,tickValue,
                           0.0,sellLossPerLot) ||
      buyLossPerLot<=0 || sellLossPerLot<=0){
      reason = "INVALID_CANDIDATE_RISK";
      return(false);
   }

   // 残高と有効証拠金の小さい方を基準に、一注文当たりの取引数量を求める
   double capitalBase = MathMin(AccountBalance(),AccountEquity());
   double riskCash = capitalBase*EntryRiskPercent/100.0;
   double rawLots = MathMin(riskCash/buyLossPerLot,riskCash/sellLossPerLot);
   rawLots = MathMin(rawLots,maxLots);

   // 発注時と半分決済後の取引数量を、銘柄の取引数量刻みに合わせる
   double halfLots = NormalizeLotsDown(rawLots/2.0,lotStep);
   entryLots = NormalizeDouble(halfLots*2.0,8);
   double remainingLots = NormalizeDouble(entryLots-halfLots,8);

   // 最小＆最大ロットと比較して適正ロット数かを確認
   if(halfLots<minLots || remainingLots<minLots){
      reason = "BELOW_MINIMUM_HALF_LOT";
      return(false);
   }
   if(entryLots<minLots || entryLots>maxLots+1.0e-8){
      reason = "ENTRY_LOT_OUT_OF_RANGE";
      return(false);
   }

   // 買いまたは売りが約定しても余剰証拠金が下限を割らないことを確認する
   RefreshRates();
   // marginBuffer:最低限残したい余剰証拠金
   double marginBuffer = capitalBase*FreeMarginBufferPercent/100.0;

   // 買い約定後の余剰証拠金を試算する
   ResetLastError();
   double buyFreeMargin = AccountFreeMarginCheck(Symbol(),OP_BUY,entryLots); // buyFreeMargin:買い約定後の余剰証拠金
   int buyMarginError = GetLastError();

   // 売り約定後の余剰証拠金を試算する 
   ResetLastError();
   double sellFreeMargin = AccountFreeMarginCheck(Symbol(),OP_SELL,entryLots);
   int sellMarginError = GetLastError();

   // 次のいずれかに該当すると証拠金チェック失敗として発注拒否
   // - 買い側で証拠金不足エラーが発生した
   // - 売り側で証拠金不足エラーが発生した
   // - 証拠金不足以外も含め、何らかのエラーが発生した
   // - 買い約定後の余剰証拠金が設定した下限未満になる
   // - 売り約定後の余剰証拠金が設定した下限未満になる   
   if(buyMarginError==ERR_NOT_ENOUGH_MONEY || sellMarginError==ERR_NOT_ENOUGH_MONEY ||
      buyMarginError!=0 || sellMarginError!=0 ||
      buyFreeMargin<marginBuffer || sellFreeMargin<marginBuffer){
      reason = "FREE_MARGIN_CHECK_FAILED buyFree="+DoubleToString(buyFreeMargin,2)+
               " sellFree="+DoubleToString(sellFreeMargin,2)+
               " buffer="+DoubleToString(marginBuffer,2)+
               " buyError="+IntegerToString(buyMarginError)+
               " sellError="+IntegerToString(sellMarginError);
      return(false);
   }

   Print("[STR01] OCO lots prepared. entryLots=",entryLots," halfLots=",halfLots,
         " buyLossPerLot=",buyLossPerLot," sellLossPerLot=",sellLossPerLot,
         " buyFreeMargin=",buyFreeMargin," sellFreeMargin=",sellFreeMargin,
         " marginBuffer=",marginBuffer);
   return(true);
}

// 注文を識別する文字列を作り、半分決済済みかを確認する
bool IsHalfCloseDone(int magic,string &key){
   double pointPrice = MarketInfo(Symbol(),MODE_POINT);
   double tickSizePrice = MarketInfo(Symbol(),MODE_TICKSIZE);
   long openPriceTicks = 0;
   if(tickSizePrice>0) openPriceTicks = (long)MathRound(OrderOpenPrice()/tickSizePrice);
   string keyPrefix = "S1H_"+IntegerToString(AccountNumber())+"_"+Symbol()+"_"+
                      IntegerToString(magic)+"_"+IntegerToString(OrderType())+"_"+
                      IntegerToString((int)OrderOpenTime())+"_";
   key = keyPrefix+DoubleToString((double)openPriceTicks,0);

   // 旧版の二重換算で記録された半分決済済み状態も引き継ぐ
   double legacyTickSizePrice = tickSizePrice*pointPrice;
   long legacyOpenPriceTicks = 0;
   if(legacyTickSizePrice>0) legacyOpenPriceTicks = (long)MathRound(OrderOpenPrice()/legacyTickSizePrice);
   string legacyKey = keyPrefix+DoubleToString((double)legacyOpenPriceTicks,0);

   for(int i=ArraySize(gHalfClosedKeys)-1;i>=0;i--){
      if(gHalfClosedKeys[i]==key || gHalfClosedKeys[i]==legacyKey) return(true);
   }
   if(!IsTesting() && (GlobalVariableCheck(key) || GlobalVariableCheck(legacyKey))) return(true);
   return(false);
}

// 半分決済の完了状態を記録し、再度の半分決済を防止する
void MarkHalfCloseDone(string key){
   bool recorded = false;
   for(int i=ArraySize(gHalfClosedKeys)-1;i>=0;i--){
      if(gHalfClosedKeys[i]==key){
         recorded = true;
         break;
      }
   }
   if(!recorded){
      int size = ArraySize(gHalfClosedKeys);
      if(ArrayResize(gHalfClosedKeys,size+1)==size+1) gHalfClosedKeys[size] = key;
   }
   if(!IsTesting()) GlobalVariableSet(key,TimeCurrent());
}

/*
N/2戦略
*/
void CloseHalf(double band,int slippage,int magic){
   bool res_cl;
   int starttime;
   for(int i=0;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      if(OrderType() == OP_BUY)
      {
         string buyStateKey = "";
         if((Bid - OrderOpenPrice() > band*Point) && !IsHalfCloseDone(magic,buyStateKey)){
            // 半分決済後にも最小取引数量を残せる数量だけを決済する
            double lotStep = MarketInfo(Symbol(),MODE_LOTSTEP);
            double minLots = MarketInfo(Symbol(),MODE_MINLOT);
            double closeLots = NormalizeLotsDown(OrderLots()/2.0,lotStep);
            double remainLots = NormalizeDouble(OrderLots()-closeLots,8);
            if(closeLots<minLots || remainLots<minLots){
               Print("[STR01] CloseHalf skipped: invalid Buy volume. ticket=",OrderTicket(),
                     " orderLots=",OrderLots()," closeLots=",closeLots," remainLots=",remainLots);
               continue;
            }
            res_cl = false;
            starttime = GetTickCount();
            while(!res_cl){
               if(GetTickCount()-starttime > MyOrderWaitingTime*1000){
                  Alert("CloseHalf timeout. Check the experts log.");
                  break;
               }
               RefreshRates();
               ResetLastError();
               res_cl = OrderClose(OrderTicket(),closeLots,MarketInfo(Symbol(),MODE_BID),slippage,clrDodgerBlue);
               if(res_cl){
                  MarkHalfCloseDone(buyStateKey);
                  break;
               }
               int closeError = GetLastError();
               Print("[STR01] CloseHalf Buy failed. ticket=",OrderTicket()," lots=",closeLots,
                     " error=",closeError," ",ErrorDescription(closeError));
               Sleep(100);
            }
         }
         continue;
      }
      if(OrderType() == OP_SELL)
      {
         string sellStateKey = "";
         if((OrderOpenPrice()-Ask > band*Point) && !IsHalfCloseDone(magic,sellStateKey)){
            // 半分決済後にも最小取引数量を残せる数量だけを決済する
            double sellLotStep = MarketInfo(Symbol(),MODE_LOTSTEP);
            double sellMinLots = MarketInfo(Symbol(),MODE_MINLOT);
            double sellCloseLots = NormalizeLotsDown(OrderLots()/2.0,sellLotStep);
            double sellRemainLots = NormalizeDouble(OrderLots()-sellCloseLots,8);
            if(sellCloseLots<sellMinLots || sellRemainLots<sellMinLots){
               Print("[STR01] CloseHalf skipped: invalid Sell volume. ticket=",OrderTicket(),
                     " orderLots=",OrderLots()," closeLots=",sellCloseLots," remainLots=",sellRemainLots);
               continue;
            }
            res_cl = false;
            starttime = GetTickCount();
            while(!res_cl){
               if(GetTickCount()-starttime > MyOrderWaitingTime*1000){
                  Alert("CloseHalf timeout. Check the experts log.");
                  break;
               }               
               RefreshRates();
               ResetLastError();
               res_cl = OrderClose(OrderTicket(),sellCloseLots,MarketInfo(Symbol(),MODE_ASK),slippage,clrIndianRed);
               if(res_cl){
                  MarkHalfCloseDone(sellStateKey);
                  break;
               }
               int sellCloseError = GetLastError();
               Print("[STR01] CloseHalf Sell failed. ticket=",OrderTicket()," lots=",sellCloseLots,
                     " error=",sellCloseError," ",ErrorDescription(sellCloseError));
               Sleep(100);
            }
         }
         continue;
      }            
   }
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{  
   if(!gRiskConfigValid) return;
   // 再初期化後は以前の注文番号を推測せず、すべての待機注文が取り消されるまで毎回確認する
   bool recoveryReady = true;
   if(gPendingRecoveryRequired){
      recoveryReady = CancelAllPendingOrders(MAGIC);
      if(recoveryReady){
         gBuyStopTicket = -1;
         gSellStopTicket = -1;
         gPairRollbackRequired = false;
         gPendingRecoveryRequired = false;
      }
   }

   bool ocoReady = ApplyOCO(Symbol(),MAGIC,gBuyStopTicket,gSellStopTicket,
                            gPairRollbackRequired,MyOrderWaitingTime);
   bool newBar = IsNewBar();
   if(IsTesting() && newBar && gEquityTick>0 &&
      (long)TimeCurrent()/86400!=(long)gEquityTick/86400){
      FileWrite(fileHandle,TimeToString(gEquityTick,TIME_DATE|TIME_SECONDS),
                DoubleToString(gLastEquity,2),DoubleToString(gLastBalance,2));
   }
   int oTicket;
   int TPPoints;
   
   if(newBar==True){
      //既存の待機注文をキャンセル
      // 既存の待機注文をすべて取り消した後に限り、新しい待機注文を配置する
      bool canPlaceOrders = false;
      if(recoveryReady) canPlaceOrders = CancelAllPendingOrders(MAGIC);
      if(!ocoReady || gPendingRecoveryRequired) canPlaceOrders = false;
      int openPositions = 0;
      for(int positionIndex=OrdersTotal()-1;positionIndex>=0;positionIndex--){
         if(!OrderSelect(positionIndex,SELECT_BY_POS)){
            canPlaceOrders = false;
            break;
         }
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGIC &&
            (OrderType()==OP_BUY || OrderType()==OP_SELL)) openPositions++;
      }
      if(MaxOpenPositions>0 && openPositions>=MaxOpenPositions) canPlaceOrders = false;
      RefreshRates();
      if(Ask-Bid>MaxSpreadPips*gPipsPoint ||
         Bars<=MathMax(MathMax(En_bars,SL_bars),ATRPeriod+ATRShift)+1) canPlaceOrders = false;
      // 価格刻みに合わせた値で、市場価格・待機注文価格・損切り価格の必要距離を確認する
      if(canPlaceOrders){
         gBuyStopTicket = -1;
         gSellStopTicket = -1;
         RefreshRates();
         double pointPrice = MarketInfo(Symbol(),MODE_POINT);
         int symbolDigits = (int)MarketInfo(Symbol(),MODE_DIGITS);
         double tickSizePrice = MarketInfo(Symbol(),MODE_TICKSIZE);
         double stopLevelPoints = MarketInfo(Symbol(),MODE_STOPLEVEL);
         double marketBid = Bid;
         double marketAsk = Ask;
         double tickSizePoints = 0;
         if(pointPrice>0) tickSizePoints = tickSizePrice/pointPrice;

         // 銘柄情報が無効な場合は推測値で発注しない
         if(pointPrice>0 && tickSizePrice>0 && tickSizePoints>0 && stopLevelPoints>=0){
            // 必要な価格差を価格刻み単位で切り上げ、設定値が零でも最低一刻みを要求する
            int requiredStopTicks = (int)MathCeil(stopLevelPoints/tickSizePoints);
            if(requiredStopTicks<1) requiredStopTicks = 1;
            double requiredStopDistance = requiredStopTicks*tickSizePrice;
            double tickTolerance = pointPrice/10.0;

            // 買い側と売り側の発注価格と損切り価格を算出し、送信前に全条件を確認する
            double buyEntry = High[iHighest(NULL, 0, MODE_HIGH, En_bars, 1)];
            double buySL = Low[iLowest(NULL, 0, MODE_LOW, SL_bars, 1)];
            double alignedBuyEntry;
            double alignedBuySL;
            bool buyPricesOnTickGrid = AlignAndCheckTickGrid(buyEntry,buySL,tickSizePrice,symbolDigits,tickTolerance,alignedBuyEntry,alignedBuySL);
            double sellEntry = Low[iLowest(NULL, 0, MODE_LOW, En_bars, 1)];
            double sellSL = High[iHighest(NULL, 0, MODE_HIGH, SL_bars, 1)];
            double alignedSellEntry;
            double alignedSellSL;
            bool sellPricesOnTickGrid = AlignAndCheckTickGrid(sellEntry,sellSL,tickSizePrice,symbolDigits,tickTolerance,alignedSellEntry,alignedSellSL);

            // 買い側と売り側の候補価格に、同一価格の既存建玉がないことを確認する
            bool duplicateBuyEntry;
            bool duplicateScanReady = FindDuplicatePosition(OP_BUY,alignedBuyEntry,tickSizePrice,symbolDigits,tickTolerance,duplicateBuyEntry);
            bool duplicateSellEntry;
            if(!FindDuplicatePosition(OP_SELL,alignedSellEntry,tickSizePrice,symbolDigits,tickTolerance,duplicateSellEntry)) duplicateScanReady = false;

            bool buyDistanceValid = alignedBuyEntry-alignedBuySL<SLLimitPips*gPipsPoint &&  // 買いの発注価格と損切り価格の差が上限未満
                                    alignedBuyEntry-marketAsk>=requiredStopDistance &&      // 買いの発注価格が売値から必要距離以上離れている
                                    alignedBuyEntry-alignedBuySL>=requiredStopDistance;     // 買いの損切り価格が発注価格から必要距離以上離れている
            bool sellDistanceValid = alignedSellSL-alignedSellEntry<SLLimitPips*gPipsPoint && // 売りの発注価格と損切り価格の差が上限未満
                                     marketBid-alignedSellEntry>=requiredStopDistance &&       // 売りの発注価格が買値から必要距離以上離れている
                                     alignedSellSL-alignedSellEntry>=requiredStopDistance;      // 売りの損切り価格が発注価格から必要距離以上離れている
            bool pairPricesValid = buyPricesOnTickGrid &&  // 買いの発注価格と損切り価格が価格刻みに一致する
                                   sellPricesOnTickGrid && // 売りの発注価格と損切り価格が価格刻みに一致する
                                   buyDistanceValid &&     // 買い側の全距離条件を満たす
                                   sellDistanceValid;      // 売り側の全距離条件を満たす
            bool pairReady = pairPricesValid &&     // 買い側と売り側の価格条件を満たす
                             duplicateScanReady &&  // 既存建玉の走査が正常に完了している
                             !duplicateBuyEntry &&  // 買いの候補価格と同一価格の既存買い建玉がない
                             !duplicateSellEntry;   // 売りの候補価格と同一価格の既存売り建玉がない

            // 価格条件を満たした場合だけ、損失額と証拠金から発注数量を決定する
            double entryLots = 0;
            string lotRejectReason = "";
            if(pairReady && !PrepareOcoLots(alignedBuyEntry,alignedBuySL,alignedSellEntry,alignedSellSL,
                                             entryLots,lotRejectReason)){
               pairReady = false;
               Print("[STR01] OCO pair skipped by lot/risk check. reason=",lotRejectReason,
                     " buyEntry=",alignedBuyEntry," buySL=",alignedBuySL,
                     " sellEntry=",alignedSellEntry," sellSL=",alignedSellSL);
            }

            if(pairReady){
               TP = 0;
               order_price = alignedBuyEntry;
               SL = alignedBuySL;
               Print("[STR01] OrderSend request. type=",OP_BUYSTOP," entry=",order_price,
                     " sl=",SL," bid=",marketBid," ask=",marketAsk," stopLevelPoints=",stopLevelPoints,
                     " freezeLevelPoints=",MarketInfo(Symbol(),MODE_FREEZELEVEL)," tickSizePoints=",tickSizePoints);
               oTicket = SendOrder(OP_BUYSTOP,entryLots,order_price,Slippage,SL,TP,COMMENT,MAGIC);
               if(oTicket>0) gBuyStopTicket = oTicket;
               Print("[STR01] OrderSend result. type=",OP_BUYSTOP," ticket=",oTicket);

               // 買いの逆指値注文が受け付けられた場合だけ、検証済みの売り逆指値注文を送信する
               // 片側だけの取引機会を残すことより、対になる注文を確実に成立させることを優先する
               if(gBuyStopTicket>0){
                  order_price = alignedSellEntry;
                  SL = alignedSellSL;
                  Print("[STR01] OrderSend request. type=",OP_SELLSTOP," entry=",order_price,
                        " sl=",SL," bid=",marketBid," ask=",marketAsk," stopLevelPoints=",stopLevelPoints,
                        " freezeLevelPoints=",MarketInfo(Symbol(),MODE_FREEZELEVEL)," tickSizePoints=",tickSizePoints);
                  oTicket = SendOrder(OP_SELLSTOP,entryLots,order_price,Slippage,SL,TP,COMMENT,MAGIC);
                  if(oTicket>0) gSellStopTicket = oTicket;
                  Print("[STR01] OrderSend result. type=",OP_SELLSTOP," ticket=",oTicket);
               }
            }
            else{
               // ペアの一方でも不成立なら、両方の注文を見送る
               if(!buyPricesOnTickGrid){
                  Print("[STR01] OCO pair skipped: Buy Stop price is off tick grid. entry=",buyEntry,
                        " sl=",buySL," tickSizePrice=",tickSizePrice);
               }
               if(!sellPricesOnTickGrid){
                  Print("[STR01] OCO pair skipped: Sell Stop price is off tick grid. entry=",sellEntry,
                        " sl=",sellSL," tickSizePrice=",tickSizePrice);
               }
               if(!duplicateScanReady){
                  Print("[STR01] OCO pair skipped: duplicate-price scan failed.");
               }
               else if(duplicateBuyEntry || duplicateSellEntry){
                  Print("[STR01] OCO pair skipped: same-price position exists. buyDuplicate=",
                        duplicateBuyEntry," sellDuplicate=",duplicateSellEntry);
               }
               if(!buyDistanceValid){
                  Print("[STR01] OCO pair skipped: Buy Stop distance condition failed. entryMarketDistance=",
                        alignedBuyEntry-marketAsk," entrySLDistance=",alignedBuyEntry-alignedBuySL,
                        " requiredStopDistance=",requiredStopDistance);
               }
               if(!sellDistanceValid){
                  Print("[STR01] OCO pair skipped: Sell Stop distance condition failed. entryMarketDistance=",
                        marketBid-alignedSellEntry," entrySLDistance=",alignedSellSL-alignedSellEntry,
                        " requiredStopDistance=",requiredStopDistance);
               }
            }
         }
         else{
            Print("[STR01] Pending orders skipped: invalid symbol property. point=",pointPrice,
                  " digits=",symbolDigits," tickSizePoints=",tickSizePoints,
                  " stopLevelPoints=",stopLevelPoints);
         }

         // 片側だけが発注された場合は、対になる注文がない待機注文を取り消す
         if((gBuyStopTicket>0 && gSellStopTicket<=0) ||
            (gSellStopTicket>0 && gBuyStopTicket<=0)){
            gPairRollbackRequired = true;
            Print("[STR01] Incomplete OCO pair. Rolling back the unpaired pending order. buyTicket=",
                  gBuyStopTicket," sellTicket=",gSellStopTicket);
         }
      }
   }

   // 発注処理中に即時約定した場合も、同じ価格更新内で検知する
   if(!ApplyOCO(Symbol(),MAGIC,gBuyStopTicket,gSellStopTicket,
                gPairRollbackRequired,MyOrderWaitingTime)){
      Print("[STR01] OCO is not complete. New entries will remain blocked until the state is resolved.");
   }
    
   double exitATR = iATR(NULL,PERIOD_H1,ATRPeriod,ATRShift);
   TPPoints = int(exitATR*HalfATRMult/Point);
   int trailPoints = int(exitATR*TrailATRMult/Point);
   if(TPPoints>0) CloseHalf(TPPoints,Slippage,MAGIC);
   // 追尾と時間決済はこのEAの銘柄・Magicだけを処理する。失敗時は次tickで再判定する。
   double exitTickSize = MarketInfo(Symbol(),MODE_TICKSIZE);
   double exitStopDistance = NormalizeDouble(MarketInfo(Symbol(),MODE_STOPLEVEL)*Point,Digits);
   double exitFreezeDistance = NormalizeDouble(MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point,Digits);
   if(trailPoints>0 && exitTickSize>0 && exitStopDistance>=0 && exitFreezeDistance>=0){
      for(int trailIndex=OrdersTotal()-1;trailIndex>=0;trailIndex--){
         ResetLastError();
         if(!OrderSelect(trailIndex,SELECT_BY_POS)){
            Print("[STR01_rev] Trailing selection failed. error=",GetLastError());
            continue;
         }
         int trailType = OrderType();
         if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC ||
            (trailType!=OP_BUY && trailType!=OP_SELL)) continue;
         RefreshRates();
         double newStop = 0;
         double stopDistance = 0;
         double takeDistance = 0;
         bool improvesStop = false;
         if(trailType==OP_BUY){
            newStop = NormalizeDouble(MathFloor((Bid-trailPoints*Point)/exitTickSize+1e-7)*exitTickSize,Digits);
            stopDistance = NormalizeDouble(Bid-newStop,Digits);
            takeDistance = NormalizeDouble(OrderTakeProfit()-Bid,Digits);
            improvesStop = newStop>=OrderOpenPrice() &&
                           (OrderStopLoss()==0 || newStop>OrderStopLoss()+0.5*Point);
         }
         else{
            newStop = NormalizeDouble(MathCeil((Ask+trailPoints*Point)/exitTickSize-1e-7)*exitTickSize,Digits);
            stopDistance = NormalizeDouble(newStop-Ask,Digits);
            takeDistance = NormalizeDouble(Ask-OrderTakeProfit(),Digits);
            improvesStop = newStop<=OrderOpenPrice() &&
                           (OrderStopLoss()==0 || newStop<OrderStopLoss()-0.5*Point);
         }
         if(!improvesStop || stopDistance<exitStopDistance) continue;
         if(exitFreezeDistance>0 && stopDistance<=exitFreezeDistance) continue;
         if(OrderTakeProfit()>0 && (takeDistance<exitStopDistance ||
            (exitFreezeDistance>0 && takeDistance<=exitFreezeDistance))) continue;
         ResetLastError();
         if(!OrderModify(OrderTicket(),OrderOpenPrice(),newStop,OrderTakeProfit(),0,gArrowColor[trailType])){
            int modifyError = GetLastError();
            Print("[STR01_rev] Trailing modify failed. ticket=",OrderTicket(),
                  " error=",modifyError," ",ErrorDescription(modifyError));
         }
      }
   }
   for(int timeIndex=OrdersTotal()-1;timeIndex>=0;timeIndex--){
      ResetLastError();
      if(!OrderSelect(timeIndex,SELECT_BY_POS)){
         Print("[STR01_rev] Time-stop selection failed. error=",GetLastError());
         continue;
      }
      int timeType = OrderType();
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MAGIC ||
         (timeType!=OP_BUY && timeType!=OP_SELL)) continue;
      if(iBarShift(NULL,PERIOD_H1,OrderOpenTime())<TimeStopBars ||
         OrderProfit()+OrderSwap()+OrderCommission()>=0) continue;
      RefreshRates();
      double closePrice = timeType==OP_BUY ? Bid : Ask;
      if(exitFreezeDistance>0){
         double currentSLDistance = NormalizeDouble(timeType==OP_BUY ? Bid-OrderStopLoss() : OrderStopLoss()-Ask,Digits);
         double currentTPDistance = NormalizeDouble(timeType==OP_BUY ? OrderTakeProfit()-Bid : Ask-OrderTakeProfit(),Digits);
         if((OrderStopLoss()>0 && currentSLDistance<=exitFreezeDistance) ||
            (OrderTakeProfit()>0 && currentTPDistance<=exitFreezeDistance)) continue;
      }
      ResetLastError();
      if(!OrderClose(OrderTicket(),OrderLots(),closePrice,Slippage,gArrowColor[timeType])){
         int timeCloseError = GetLastError();
         Print("[STR01_rev] Time-stop close failed. ticket=",OrderTicket(),
               " error=",timeCloseError," ",ErrorDescription(timeCloseError));
      }
   }
   if(IsTesting()){
      gEquityTick = TimeCurrent();
      gLastEquity = AccountEquity();
      gLastBalance = AccountBalance();
   }

}
