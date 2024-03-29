/*

# FXKouryaku_201703_TokyoHourBreakout
作成日：2018/3/21
更新日：2018/3/

・東京時間高値/安値更新ブレイクアウト

*/


#include <MyLib.mqh>

#define MAGIC 20180321
#define COMMENT "FXKouryaku_201703_TokyoHourBreakout"


extern double Safety_ratio = 3.0;
extern int Slippage = 3;
extern double TPPips = 50.0;
extern double SLPips = 15.0;
datetime Bar_Time = 0;

void init()
{
   if(Digits == 3 || Digits == 5) TPPips *= 10;
   if(Digits == 3 || Digits == 5) SLPips *= 10;
}

void OCO(int magic){

   int cntr_open = 0;
   int cntr_pend = 0;
   for(int i;i<OrdersTotal();i++){
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) cntr_open += 1;
      if(OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP) cntr_pend += 1;
   }
   
   if(cntr_open > 0 && cntr_pend==1) MyOrderDelete(magic);
}

int start()
{
   
   double Target_High;
   double Target_Low;
   
   int lotsize = (AccountBalance()*AccountLeverage( ))/(Bid*MarketInfo(Symbol(), MODE_LOTSIZE)*Safety_ratio)/MarketInfo(Symbol(), MODE_MINLOT);
   double order_lots = lotsize*MarketInfo(Symbol(), MODE_MINLOT);
   if (order_lots > 2.0 ) order_lots = 2.0;
   order_lots = 0.01;
   
   //OCO
   OCO(MAGIC);
   
   if(Bar_Time == Time[0]){
      return(0);
   }
   else if(Bar_Time!=Time[0]){
      Bar_Time = Time[0];
   }
   
   /*東京時間17時に新規OCO注文*/
   if(Hour()==11){
      Target_High = 0.0;
      Target_Low = 9999.99;
      for(int i=0;i<10;i++){
         if(Target_High < High[i]){Target_High = High[i];}
         if(Target_Low > Low[i]){Target_Low = Low[i];}
      }
      
      //Buy Stop Order
      MyOrderSend(OP_BUYSTOP,order_lots,Target_High,Slippage,Target_High - SLPips*Point,Target_High + TPPips*Point,COMMENT,MAGIC);
      
      //Sell Stop Order
      MyOrderSend(OP_SELLSTOP,order_lots,Target_Low,Slippage,Target_Low + SLPips*Point,Target_Low - TPPips*Point,COMMENT,MAGIC);
   }
   
   /*東京時間24時にキャンセル注文*/
   if(Hour()==18){
      if(MyCurrentOrders(MY_PENDPOS,MAGIC)>0){
         MyOrderDelete(MAGIC);
      }
   }
   

   
   return(0);
}
