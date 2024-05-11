/*

# TrailingStop.mqh
作成日：2017/01/20
更新日：2022/05/04

・トレーリングストップ

*/

#include <Original/MyLib.mqh>




/*
トレーリングストップ
tspips : トレーリングストップ開始幅
gpips  : 利確幅
*/
bool TrailingStop(int oTicket,int tspips,int gpips)
{
   double newsl,tp;
   if(OrderSelect(oTicket, SELECT_BY_TICKET) == false) return(false);
   
   if(OrderType() == OP_BUY)
   {
      if(OrderStopLoss()==0) newsl = Bid - tspips*Point;
      else newsl = Bid - tspips*Point + gpips*Point;
      newsl = NormalizeDouble(newsl,Digits);
      if(newsl >= OrderOpenPrice() && (newsl > OrderStopLoss() || OrderStopLoss() == 0)){
         tp = OrderTakeProfit();
         ModifyOrder(oTicket,newsl,tp);
         //Print("Open:",OrderOpenPrice()," Bid:",Bid," newsl:",newsl);
      }
   }
   if(OrderType() == OP_SELL)
   {
      if(OrderStopLoss()==0) newsl = Ask + tspips*Point;
      else newsl = Ask + tspips*Point - gpips*Point;
      newsl = NormalizeDouble(newsl,Digits);
      if(newsl <= OrderOpenPrice() && (newsl < OrderStopLoss() || OrderStopLoss() == 0)){
         tp = OrderTakeProfit();
         ModifyOrder(oTicket,newsl,tp);
         //Print("sl:",OrderStopLoss()," Ask:",Ask," newsl:",newsl);
      }
   }   

   return(true);
}

/*
通常のトレーリングストップ
*/
bool MyTrailingStop(int ts, int magic)
{
   double newsl,tp;
   int ticket;
   
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS) == false) break;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;

      if(OrderType() == OP_BUY)
      {
         newsl = Bid-ts*Point;
         newsl = NormalizeDouble(newsl,Digits);
         ticket = OrderTicket();
         if(newsl >= OrderOpenPrice() && (newsl > OrderStopLoss() || OrderStopLoss() == 0)){
            tp = OrderTakeProfit();
            Modify_Order(ticket,newsl,tp,magic);
         }
         continue;
      }

      if(OrderType() == OP_SELL)
      {
         newsl = Ask+ts*Point;
         newsl = NormalizeDouble(newsl,Digits);
         ticket = OrderTicket();
         if(newsl <= OrderOpenPrice() && (newsl < OrderStopLoss() || OrderStopLoss() == 0)){
            tp = OrderTakeProfit();
            Modify_Order(ticket,newsl,tp,magic);
         }
         continue;
      }
   }
   return(true);
}

/*
ATRトレーリングストップ
・（2017/1/20） トレーリング幅がストップレベル内に入る場合には、OrderModifyを実行しないように修正
*/
void MyTrailingStopATR(int period,double mult,int magic)
{
   double spread = Ask - Bid;
   double atr = iATR(NULL,0,period,1)*mult;
   double HH = Low[1] + atr + spread;
   double LL = High[1] - atr;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      if(OrderType()==OP_BUY)
      {
         RefreshRates();
         if(LL > OrderStopLoss() && Bid-LL>MarketInfo(Symbol(), MODE_STOPLEVEL)*Point){
            MyOrderModify(LL,0,magic);
         }
         break;
      }
      
      if(OrderType()==OP_SELL)
      {
         RefreshRates();
         if((HH < OrderStopLoss() || OrderStopLoss()==0) && HH-Ask>MarketInfo(Symbol(), MODE_STOPLEVEL)*Point){
            MyOrderModify(HH,0,magic);
         }
         break;
      }
   }
}

/*
HLバンドトレーリングストップ
*/
void MyTrailingStopHL(int period,int magic)
{
   double spread = Ask-Bid;
   double HH = iCustom(Symbol(), 0, "HLBand", period, 1, 1)+spread;
   double LL = iCustom(Symbol(), 0, "HLBand", period, 2, 1);

   if(MyCurrentOrders(OP_BUY, magic) != 0) ModifyOrder(LL, 0, magic);
   if(MyCurrentOrders(OP_SELL, magic) != 0) ModifyOrder(HH, 0, magic);
}

/*
N/2戦略
*/
/*
旧チケット番号を入力すると新チケット番号を返す
https://btj0.com/blog/mt4/how-to-get-new-ticket/
*/
int GetNewTicketNum(int preTicketNum) {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS) == false) break;
      // コメントに分割決済前のチケット番号が含まれない場合はcontinue
      if(StringFind(OrderComment(), IntegerToString(preTicketNum)) == -1) continue;
      return OrderTicket();
   }
   return -1;
}
void CloseHalf(double band,int slippage,int magic){
   bool res_cl;
   bool res_md;
   int new_oTicket;
   for(int i=0;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      if(OrderType() == OP_BUY)
      {
         if((Bid - OrderOpenPrice() > band*Point) && OrderStopLoss() < OrderOpenPrice()){   
            res_cl = false;
            res_md = false;
            while(!res_cl){
               Print(OrderLots()/2);
               res_cl = OrderClose(OrderTicket(),OrderLots()/2,Bid,slippage,clrDodgerBlue);
            }
            new_oTicket = GetNewTicketNum(OrderTicket());
            while(!res_md){
               res_md = OrderModify(new_oTicket,0,Bid - band*Point,0,0,clrDodgerBlue);
            }
         }
         continue;
      }
      if(OrderType() == OP_SELL)
      {
         if((OrderOpenPrice()-Ask > band*Point) && OrderStopLoss() > OrderOpenPrice()){
            res_cl = false;
            res_md = false;
            while(!res_cl){
               res_cl = OrderClose(OrderTicket(),OrderLots()/2,Ask,slippage,clrIndianRed);
            }
            new_oTicket = GetNewTicketNum(OrderTicket());
            while(!res_md){
               res_md = OrderModify(new_oTicket,0,Ask + band*Point,0,0,clrIndianRed);
            }
         }
         continue;
      }            
   }
}