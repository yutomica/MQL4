/*

# Pyramitting.mqh
作成日：2020/3/2
更新日：2020/3/9

・ピラミッティング（増し玉）

*/

#include <Original/MyLib.mqh>

/*
Pyramitting
*/
bool Pyramitting(double N,double lots,int oTicket,int oMagic,int maxpos){
   int ahead;
   int oSlippage = 3;
   double newsl;
   int pos = MyCurrentPos(MY_OPENPOS,oMagic);
   
   if(pos==0) return false;
   
   // Buy order pyramitting
   if(pos > 0){
      if(OrderSelect(oTicket,SELECT_BY_TICKET)==false) return false;
      ahead = int((Ask - OrderOpenPrice())/(N*Point));
      if(ahead+1 > fabs(pos)){
         newsl = Ask - 2*N*Point;
         newsl = NormalizeDouble(newsl,Digits);
         if(newsl > OrderStopLoss()) ModifyOrder(newsl,0,oMagic);
         if(fabs(pos)<maxpos) MyOrderSend(OP_BUY,lots,Ask,oSlippage,newsl,0,"pyramitting",oMagic);
         
      }
   }
   
   // Sell order pyramitting
   if(pos < 0){
      if(OrderSelect(oTicket,SELECT_BY_TICKET)==false) return false;
      ahead = int((OrderOpenPrice() - Bid)/(N*Point));
      if(ahead+1 > fabs(pos)){
         newsl = Bid + 2*N*Point;
         newsl = NormalizeDouble(newsl,Digits);
         if(newsl < OrderStopLoss()) ModifyOrder(newsl,0,oMagic);
         if(fabs(pos)<maxpos) MyOrderSend(OP_SELL,lots,Bid,oSlippage,newsl,0,"pyramitting",oMagic);
      }   
   }
   
   return true;
      
}