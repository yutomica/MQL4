//+------------------------------------------------------------------+
//|                                                    LotSizing.mqh |
//|                                     Copyright (c) 2015, りゅーき     |
//|                                            https://autofx100.com/|
//|                     参考：https://autofx100.com/2015/02/28/204337/ | 
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2015, りゅーき"
#property link      "https://autofx100.com/"
#property version   "1.00"

//+------------------------------------------------------------------+
//|【関数】資産のＮ％のリスクのロット数を計算する                    |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aFunds             資金                          |
//|                                      AccountFreeMargin()         |
//|                                      AccountBalance()            |
//|         ○      aSymbol            通貨ペア                      |
//|         ○      aStopLossPips      損切り値（pips）              |
//|         ○      aRiskPercent       リスク率（％）                |
//|                                                                  |
//|【戻値】ロット数                                                  |
//|                                                                  |
//|【備考】計算した結果、最小ロット数未満になる場合、-1を返す        |
//+------------------------------------------------------------------+
double calcLotSizeRiskPercent(double aFunds, string aSymbol, double aStopLossPips, double aRiskPercent)
{
  // 取引対象の通貨を1ロット売買した時の1ポイント（pipsではない！）当たりの変動額
  double tickValue = MarketInfo(aSymbol, MODE_TICKVALUE);

  // tickValueは最小価格単位で計算されるため、3/5桁業者の場合、10倍しないと1pipsにならない
  if(MarketInfo(aSymbol, MODE_DIGITS) == 3 || MarketInfo(aSymbol, MODE_DIGITS) == 5){
    tickValue *= 10.0;
  }

  double riskAmount = aFunds * (aRiskPercent / 100.0);

  double lotSize = riskAmount / (aStopLossPips * tickValue);

  double lotStep = MarketInfo(aSymbol, MODE_LOTSTEP);

  // ロットステップ単位未満は切り捨て
  // 0.123⇒0.12（lotStep=0.01の場合）
  // 0.123⇒0.1 （lotStep=0.1の場合）
  lotSize = MathFloor(lotSize / lotStep) * lotStep;

  // 証拠金ベースの制限
  double margin = MarketInfo(aSymbol, MODE_MARGINREQUIRED);
  
  if(margin > 0.0){
    double accountMax = aFunds / margin;

    accountMax = MathFloor(accountMax / lotStep) * lotStep;

    if(lotSize > accountMax){
      lotSize = accountMax;
    }
  }

  // 最大ロット数、最小ロット数対応
  double minLots = MarketInfo(aSymbol, MODE_MINLOT);
  double maxLots = MarketInfo(aSymbol, MODE_MAXLOT);

  if(lotSize < minLots){
    // 仕掛けようとするロット数が最小単位に満たない場合、
    // そのまま仕掛けると過剰リスクになるため、エラーに
    lotSize = -1.0;
  }else if(lotSize > maxLots){
    lotSize = maxLots;
  }

  return(lotSize);
}