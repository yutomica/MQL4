
/*
トラッカー

作成日：2019/08/19
更新日：2022/03/05

・保有ポジションの注文価格からの値動きをトラッキング
・出力項目：
　- 注文番号
　- Barshift
　- 時刻
　- 値動き（現在値-OrderOpenPrice） pips

*/

double CurrencyUnit;
double CurrencyPoint;

void Tracker(int fhndl,int magic)
{
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS)==false) break;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=magic) continue;
      int type = OrderType();
      
      CurrencyPoint = MarketInfo(OrderSymbol(), MODE_POINT);
      if(Digits == 3 || Digits == 5){
         CurrencyUnit = CurrencyPoint*10;
      }
      else{CurrencyUnit = CurrencyPoint;}
      
      if((type==OP_BUY||type==OP_BUYLIMIT||type==OP_BUYSTOP))
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (Close[0] - OrderOpenPrice())/CurrencyUnit      
         );
         continue;
      }
      if((type==OP_SELL||type==OP_SELLLIMIT||type==OP_SELLSTOP))
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (OrderOpenPrice() - Close[0])/CurrencyUnit
         );
         continue;
      }      
      
/*     
      if((type==OP_BUY||type==OP_BUYLIMIT||type==OP_BUYSTOP)&&OrderProfit()>0)
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (High[0] - OrderOpenPrice())/CurrencyUnit      
         );
         continue;
      }
      if((type==OP_BUY||type==OP_BUYLIMIT||type==OP_BUYSTOP)&&OrderProfit()<0)
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (Low[0] - OrderOpenPrice())/CurrencyUnit
         );
         continue;
      }
      if((type==OP_SELL||type==OP_SELLLIMIT||type==OP_SELLSTOP)&&OrderProfit()>0)
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (OrderOpenPrice()-Low[0])/CurrencyUnit    
         );
         continue;
      }
      if((type==OP_SELL||type==OP_SELLLIMIT||type==OP_SELLSTOP)&&OrderProfit()<0)
      {
         FileWrite(
            fhndl,OrderTicket(),iBarShift(OrderSymbol(),NULL,OrderOpenTime()),TimeCurrent(),
            (OrderOpenPrice() - High[0])/CurrencyUnit
         );
         continue;
      }
*/
   }
}
