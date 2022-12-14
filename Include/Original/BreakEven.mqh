//+------------------------------------------------------------------+
//|                                                    BreakEven.mqh |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//|【関数】ブレイクイーブン                                          |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aMagic             マジックナンバー              |
//|         ○      aMoveExecPips      ストップ変更開始位置（pips）  |
//|         ○      aMoveStopPips      ストップ変更幅（pips）        |
//|                                                                  |
//|【戻値】なし                                                      |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
void breakeven(int aMagic, double aMoveExecPips, double aMoveStopPips)
{
  for(int i = 0; i < OrdersTotal(); i++){
    // オーダーが１つもなければ処理終了
    if(OrderSelect(i, SELECT_BY_POS) == false){
      break;
    }

    string oSymbol = OrderSymbol();

    // 別EAのオーダーはスキップ
    if(oSymbol != Symbol() || OrderMagicNumber() != aMagic){
      continue;
    }

    int oType = OrderType();

    // 待機オーダーはスキップ
    if(oType != OP_BUY && oType != OP_SELL){
      continue;
    }

    double digits = MarketInfo(oSymbol, MODE_DIGITS);

    double oPrice      = NormalizeDouble(OrderOpenPrice(), digits);
    double oStopLoss   = NormalizeDouble(OrderStopLoss(), digits);
    double oTakeProfit = NormalizeDouble(OrderTakeProfit(), digits);
    int    oTicket     = OrderTicket();

    double exec = NormalizeDouble(aMoveExecPips * gPipsPoint, digits);
    double stop = NormalizeDouble(aMoveStopPips * gPipsPoint, digits);

    if(oType == OP_BUY){
      double price = MarketInfo(oSymbol, MODE_BID);

      if(price >= oPrice + exec){
        // 何度もmodifyしないためのif文
        if(NormalizeDouble(oStopLoss, digits) != NormalizeDouble(oPrice + stop, digits)){
          Print("ロングポジションの損切りライン変更：", DoubleToStr(oStopLoss, digits), " ⇒ ", DoubleToStr(oPrice + stop, digits));
          orderModifyReliable(oTicket, 0.0, NormalizeDouble(oPrice + stop, digits), oTakeProfit, 0, gArrowColor[oType]);
        }
      }
    }else if(oType == OP_SELL){
      price = MarketInfo(oSymbol, MODE_ASK);

      if(price <= oPrice - exec){
        // 何度もmodifyしないためのif文
        if(NormalizeDouble(oStopLoss, digits) != NormalizeDouble(oPrice - stop, digits)){
          Print("ショートポジションの損切りライン変更：", DoubleToStr(oStopLoss, digits), " ⇒ ", DoubleToStr(oPrice - stop, digits));
          orderModifyReliable(oTicket, 0.0, NormalizeDouble(oPrice - stop, digits), oTakeProfit, 0, gArrowColor[oType]);
        }
      }
    }
  }
}