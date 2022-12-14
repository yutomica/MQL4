#include <stderror.mqh>
#include <stdlib.mqh>

#define MY_OPENPOS   6
#define MY_LIMITPOS  7
#define MY_STOPPOS   8
#define MY_PENDPOS   9
#define MY_BUYPOS    10
#define MY_SELLPOS   11
#define MY_ALLPOS    12


//注文待ち時間（秒）
extern uint MyOrderWaitingTime = 10;


color ArrowColor[6] = {Blue,Red,Blue,Red,Blue,Red};

//現在のポジションのロット数
double MyCurrentOrders(int type,int magic)
{
   double lots = 0.0;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      switch(type)
      {
         case OP_BUY:
            if(OrderType()==OP_BUY) lots += OrderLots();
            break;
         case OP_SELL:
            if(OrderType()==OP_SELL) lots -= OrderLots();
            break;
         case OP_BUYLIMIT:
            if(OrderType()==OP_BUYLIMIT) lots += OrderLots();
            break;
         case OP_SELLLIMIT:
            if(OrderType()==OP_SELLLIMIT) lots -= OrderLots();
            break;
         case OP_BUYSTOP:
            if(OrderType()==OP_BUYSTOP) lots += OrderLots();
            break;
         case OP_SELLSTOP:
            if(OrderType()==OP_SELLSTOP) lots -= OrderLots();
            break; 
         case MY_OPENPOS:
            if(OrderType()==OP_BUY) lots += OrderLots();
            if(OrderType()==OP_SELL) lots -= OrderLots();
            break;
         case MY_LIMITPOS:
            if(OrderType()==OP_BUYLIMIT) lots += OrderLots();
            if(OrderType()==OP_SELLLIMIT) lots -= OrderLots();
            break;
         case MY_STOPPOS:
            if(OrderType()==OP_BUYSTOP) lots += OrderLots();
            if(OrderType()==OP_SELLSTOP) lots -= OrderLots();
            break;
         case MY_PENDPOS:
            if(OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) lots+=OrderLots();
            if(OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) lots+=OrderLots();
            break;
         case MY_BUYPOS:
            if(OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) lots+=OrderLots();
            break;
         case MY_SELLPOS:
            if(OrderType()==OP_SELL || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) lots-=OrderLots();
            break;
         case MY_ALLPOS:
            if(OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) lots+=OrderLots();
            if(OrderType()==OP_SELL || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) lots-=OrderLots();
            break;
         default:
            Print("[Current Orders Error] : Illigal order type("+type+")");
            break;
      }
      //if (lots != 0)continue;
   }
   return(lots);
}


//現在のポジション数
int MyCurrentPos(int type,int magic)
{
   int pos = 0;
   
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      switch(type)
      {
         case OP_BUY:
            if(OrderType()==OP_BUY) pos += 1;
            break;
         case OP_SELL:
            if(OrderType()==OP_SELL) pos -= 1;
            break;
         case OP_BUYLIMIT:
            if(OrderType()==OP_BUYLIMIT) pos += 1;
            break;
         case OP_SELLLIMIT:
            if(OrderType()==OP_SELLLIMIT) pos -= 1;
            break;
         case OP_BUYSTOP:
            if(OrderType()==OP_BUYSTOP) pos += 1;
            break;
         case OP_SELLSTOP:
            if(OrderType()==OP_SELLSTOP) pos -= 1;
            break; 
         case MY_OPENPOS:
            if(OrderType()==OP_BUY) pos += 1;
            if(OrderType()==OP_SELL) pos -= 1;
            break;
         case MY_LIMITPOS:
            if(OrderType()==OP_BUYLIMIT) pos += 1;
            if(OrderType()==OP_SELLLIMIT) pos -= 1;
            break;
         case MY_STOPPOS:
            if(OrderType()==OP_BUYSTOP) pos += 1;
            if(OrderType()==OP_SELLSTOP) pos -= 1;
            break;
         case MY_PENDPOS:
            if(OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) pos+=1;
            if(OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) pos+=1;
            break;
         case MY_BUYPOS:
            if(OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) pos+=1;
            break;
         case MY_SELLPOS:
            if(OrderType()==OP_SELL || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) pos-=1;
            break;
         case MY_ALLPOS:
            if(OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT || OrderType()==OP_BUYSTOP) pos+=1;
            if(OrderType()==OP_SELL || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) pos-=1;
            break;
         default:
            Print("[Current Orders Error] : Illigal order type("+type+")");
            break;
      }
      //if (pos != 0)continue;
   }
   return(pos);
}


//注文を送信する
bool MyOrderSend(int type, double lots, double price, int slippage, double sl, double tp, string comment, int magic)
{
   price = NormalizeDouble(price,Digits);
   sl = NormalizeDouble(sl,Digits);
   tp = NormalizeDouble(tp,Digits);
   
   int starttime = GetTickCount();
   while(true)
   {
      if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
      {
         Alert("OrderSend timeout. Check the experts log.");
         return(false);
      }
      if(IsTradeAllowed()==true)
      {
         RefreshRates();
         if(OrderSend(Symbol(),type,lots,price,slippage,sl,tp,comment,magic,0,ArrowColor[type])!=-1) return(true);
         
         int err = GetLastError();
         Print("[OrderSend Error] : ",err," ",ErrorDescription(err));
         if(err==ERR_INVALID_PRICE) break;
         if(err==ERR_INVALID_STOPS) break;
      }
      Sleep(100);
   }
   return(false);
}

/*
【注文送信】
注文に成功した場合、当該注文のチケット番号を返す
*/
int SendOrder(int type, double lots, double price, int slippage, double sl, double tp, string comment, int magic)
{
   int ticket = -1;
   price = NormalizeDouble(price,Digits);
   sl = NormalizeDouble(sl,Digits);
   tp = NormalizeDouble(tp,Digits);
   
   int starttime = GetTickCount();
   while(true)
   {
      if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
      {
         Alert("OrderSend timeout. Check the experts log.");
         return(false);
      }
      if(IsTradeAllowed()==true)
      {
         RefreshRates();
         ticket = OrderSend(Symbol(),type,lots,price,slippage,sl,tp,comment,magic,0,ArrowColor[type]);
         if(ticket!=-1) return(ticket);
         
         int err = GetLastError();
         Print("[OrderSend Error] : ",err," ",ErrorDescription(err));
         if(err==ERR_INVALID_PRICE) break;
         if(err==ERR_INVALID_STOPS) break;
      }
      Sleep(100);
   }
   return(ticket);
}

//オープンポジションを変更する
bool MyOrderModify(double sl, double tp, int magic)
{
   //チケット番号を取得
   int ticket = 0;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      int type = OrderType();
      if(type==OP_BUY||type==OP_SELL)
      {
         ticket = OrderTicket();
         break;
      }
   }
   if(ticket==0) return(false);
   
   sl = NormalizeDouble(sl,Digits);
   tp = NormalizeDouble(tp,Digits);
   
   if(sl==0) sl = OrderStopLoss();
   if(tp==0) tp = OrderTakeProfit();
   if(OrderStopLoss()==sl && OrderTakeProfit()==tp) return(false);
   
   int starttime = GetTickCount();
   while(true)
   {
      if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
      {
         Alert("OrderModify timeout. Check the experts log.");
         return(false);
      }
      if(IsTradeAllowed()==true)
      {
         if(OrderModify(ticket,0,sl,tp,0,ArrowColor[type]) == true) return(true);
         
         int err = GetLastError();
         Print("[OrderModify Error] : ",err," ",ErrorDescription(err));
         if(err==ERR_NO_RESULT) break;
         if(err==ERR_INVALID_STOPS) break;
      }
      Sleep(100);
   }
   return(false);
}

/*
【注文修正】
全注文を修正
*/
bool ModifyOrder(double sl, double tp, int magic)
{
   //チケット番号を取得
   int ticket = 0;
   for(int i=0;i<OrdersTotal();i++)
   {
      Print(i);
      if(OrderSelect(i,SELECT_BY_POS)==false) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      int type = OrderType();
      if(type==OP_BUY||type==OP_SELL)
      {
         ticket = OrderTicket();
         //break;
      }
      //if(ticket==0) continue;
      sl = NormalizeDouble(sl,Digits);
      tp = NormalizeDouble(tp,Digits);
      
      if(sl==0) sl = OrderStopLoss();
      if(tp==0) tp = OrderTakeProfit();
      //if(OrderStopLoss()==sl && OrderTakeProfit()==tp) continue;
      
      int starttime = GetTickCount();

      bool res = false;
      while(!res)
      {
         if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
         {
            Alert("OrderModify timeout. Check the experts log.");
            break;
         }
         if(IsTradeAllowed()==true)
         {
            if(OrderModify(ticket,0,sl,tp,0,ArrowColor[type]) == true) res = true;
            
            int err = GetLastError();
            Print("[OrderModify Error] : ",err," ",ErrorDescription(err));
            if(err==ERR_NO_RESULT) break;
            if(err==ERR_INVALID_STOPS) break;
         }
         Sleep(100);
      }
   }

   return(true);
}


/*
【注文修正】
指定したTicketの注文を修正
*/
bool Modify_Order(int ticket,double sl, double tp, int magic)
{
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(ticket,SELECT_BY_TICKET)==false) continue;
      
      int type = OrderType();
      sl = NormalizeDouble(sl,Digits);
      tp = NormalizeDouble(tp,Digits);
      if(sl==0) sl = OrderStopLoss();
      if(tp==0) tp = OrderTakeProfit();
      
      int starttime = GetTickCount();

      bool res = false;
      while(!res)
      {
         if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
         {
            Alert("OrderModify timeout. Check the experts log.");
            break;
         }
         if(IsTradeAllowed()==true)
         {
            if(OrderModify(ticket,0,sl,tp,0,ArrowColor[type]) == true) res = true;
            
            int err = GetLastError();
            Print("[OrderModify Error] : ",err," ",ErrorDescription(err));
            if(err==ERR_NO_RESULT) break;
            if(err==ERR_INVALID_STOPS) break;
         }
         Sleep(100);
      }
   }

   return(true);
}


//オープンポジションを決済する
bool MyOrderClose(int slippage, int magic)
{
   //チケット番号を取得
   int ticket = 0;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      int type = OrderType();
      if(type==OP_BUY||type==OP_SELL)
      {
         ticket = OrderTicket();
         break;
      }
   }
   if(ticket==0) return(false);
   
   int starttime = GetTickCount();
   while(true)
   {
      if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
      {
         Alert("OrderClose timeout. Check the experts log.");
         return(false);
      }
      if(IsTradeAllowed()==true)
      {
         RefreshRates();
         if(OrderClose(ticket,OrderLots(),OrderClosePrice(),slippage,ArrowColor[type])==true) return(true);
         
         int err = GetLastError();
         Print("[OrderClose Error] : ",err," ",ErrorDescription(err));
         if(err==ERR_INVALID_PRICE) break;
      }
      Sleep(100);
   }
   return(false);
 }
 
 //待機注文をキャンセルする
 bool MyOrderDelete(int magic)
 {
   //チケット番号を取得
   int ticket = 0;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      int type = OrderType();
      if(type!=OP_BUY && type!=OP_SELL)
      {
         ticket = OrderTicket();
         break;
      }
   }
   if(ticket==0) return(false);
   
   int starttime = GetTickCount();
   while(true)
   {
      if(GetTickCount()-starttime > MyOrderWaitingTime*1000)
      {
         Alert("OrderDelete timeout. Check the experts log.");
         return(false);
      }
      if(IsTradeAllowed()==true)
      {
         if(OrderDelete(ticket)==true) return(true);
         
         int err = GetLastError();
         Print("[OrderDelete Error] : ",err," ",ErrorDescription(err));
      }
      Sleep(100);
   }
   return(false);
 }
