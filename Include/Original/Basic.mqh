//+------------------------------------------------------------------+
//|                                                        Basic.mqh |
//|                                     Copyright (c) 2017, りゅーき |
//|                                            http://autofx100.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2017, りゅーき"
#property link      "http://autofx100.com/"
#property version   "1.1"

//+------------------------------------------------------------------+
//|【関数】1pips当たりの価格単位を計算する                           |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aSymbol            通貨ペア                      |
//|                                                                  |
//|【戻値】1pips当たりの価格単位                                     |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
double currencyUnitPerPips(string aSymbol)
{
  // 通貨ペアに対応する小数点数を取得
  double digits = MarketInfo(aSymbol, MODE_DIGITS);

  // 通貨ペアに対応するポイント（最小価格単位）を取得
  // 3桁/5桁のFX業者の場合、0.001/0.00001
  // 2桁/4桁のFX業者の場合、0.01/0.0001
  double point = MarketInfo(aSymbol, MODE_POINT);

  // 価格単位の初期化
  double currencyUnit = 0.0;

  // 3桁/5桁のFX業者の場合
  if(digits == 3.0 || digits == 5.0){
    currencyUnit = point * 10.0;
  // 2桁/4桁のFX業者の場合
  }else{
    currencyUnit = point;
  }

  return(currencyUnit);
}

//+------------------------------------------------------------------+
//|【関数】ポイント換算した許容スリッページを計算する                |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aSymbol            通貨ペア                      |
//|         ○      aSlippagePips      許容スリッページ（pips）      |
//|                                                                  |
//|【戻値】許容スリッページ（ポイント）                              |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
int getSlippage(string aSymbol, int aSlippagePips)
{
  double digits = MarketInfo(aSymbol, MODE_DIGITS);
  int slippage = 0;

  // 3桁/5桁業者の場合
  if(digits == 3.0 || digits == 5.0){
    slippage = aSlippagePips * 10;
  // 2桁/4桁業者の場合
  }else{
    slippage = aSlippagePips;
  }

  return(slippage);
}

//+------------------------------------------------------------------+
//|【関数】グローバル変数設定                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aName              グローバル変数名              |
//|         ○      aMagic             マジックナンバー              |
//|         ○      aValue             グローバル変数値              |
//|         △      aSymbol            通貨ペア名                    |
//|         △      aTimeframe         時間枠                        |
//|                                                                  |
//|【戻値】なし                                                      |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
void setGlobalVariables(string aName, int aMagic, double aValue, string aSymbol="", int aTimeframe=0)
{
  string name = aName + "_" + IntegerToString(aMagic);

  if(aSymbol != ""){
    name += "_" + aSymbol;
  }

  if(aTimeframe != 0){
    name += "_" + IntegerToString(aTimeframe);
  }

  datetime result = GlobalVariableSet(name, aValue);
}

//+------------------------------------------------------------------+
//|【関数】グローバル変数取得                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aName              グローバル変数名              |
//|         ○      aMagic             マジックナンバー              |
//|         △      aSymbol            通貨ペア名                    |
//|         △      aTimeframe         時間枠                        |
//|                                                                  |
//|【戻値】取得したグローバル変数値                                  |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
double getGlobalVariables(string aName, int aMagic, string aSymbol="", int aTimeframe=0)
{
  string name = aName + "_" + IntegerToString(aMagic);

  if(aSymbol != ""){
    name += "_" + aSymbol;
  }

  if(aTimeframe != 0){
    name += "_" + IntegerToString(aTimeframe);
  }

  double result = 0.0;

  if(GlobalVariableCheck(name)){
    result = GlobalVariableGet(name);
  }

  return(result);
}

//+------------------------------------------------------------------+
//|【関数】グローバル変数削除                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aName              グローバル変数名              |
//|         ○      aMagic             マジックナンバー              |
//|         △      aSymbol            通貨ペア名                    |
//|         △      aTimeframe         時間枠                        |
//|                                                                  |
//|【戻値】なし                                                      |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
void deleteGlobalVariables(string aName, int aMagic, string aSymbol="", int aTimeframe=0)
{
  string name = aName + "_" + IntegerToString(aMagic);

  if(aSymbol != ""){
    name += "_" + aSymbol;
  }

  if(aTimeframe != 0){
    name += "_" + IntegerToString(aTimeframe);
  }

  if(GlobalVariableCheck(name)){
    GlobalVariableDel(name);
  }
}

//+------------------------------------------------------------------+
//|【関数】グローバル変数存在チェック                                |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aName              グローバル変数名              |
//|         ○      aMagic             マジックナンバー              |
//|         △      aSymbol            通貨ペア名                    |
//|         △      aTimeframe         時間枠                        |
//|                                                                  |
//|【戻値】true ：存在する                                           |
//|        false：存在しない                                         |
//|                                                                  |
//|【備考】△：既定値あり                                            |
//+------------------------------------------------------------------+
bool checkGlobalVariables(string aName, int aMagic, string aSymbol="", int aTimeframe=0)
{
  string name = aName + "_" + IntegerToString(aMagic);

  if(aSymbol != ""){
    name += "_" + aSymbol;
  }

  if(aTimeframe != 0){
    name += "_" + IntegerToString(aTimeframe);
  }

  return(GlobalVariableCheck(name));
}

//+------------------------------------------------------------------+
//|【関数】ポジション数変動時にバックテスト一時停止                  |
//|                                                                  |
//|【引数】 IN OUT  引数名              説明                         |
//|        --------------------------------------------------------- |
//|         ○      aOpenOrderNumber    ポジション数                 |
//|         ○      aPrvOpenOrderNumber 1ティック前のポジション数    |
//|                                                                  |
//|【戻値】なし                                                      |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
void pauseExecEA(int aOpenOrderNumber, int aPrvOpenOrderNumber)
{
  if(aOpenOrderNumber != aPrvOpenOrderNumber){
    int hwnd = WindowHandle(Symbol(), Period());

    PostMessageA(hwnd, WM_KEYDOWN, 19, 0); // 19 = Pause

    string msg      = "Order Number Changed. Tester Stopped.";
    string boxTitle = "Break Point";
    int r = MessageBoxW(hwnd, msg, boxTitle, 0);

    if(r == 1){
      PostMessageA(hwnd, WM_KEYDOWN, 19, 0); // 19 = Pause
    }
  }
}

//+------------------------------------------------------------------+
//|【関数】フォーマットログ出力                                      |
//|                                                                  |
//|【引数】 IN OUT  引数名              説明                         |
//|        --------------------------------------------------------- |
//|         ○      aFileName           呼び出し元のファイル名       |
//|         ○      aFunctionName       呼び出し元の関数名           |
//|         ○      aLogMessage         ログメッセージ               |
//|                                                                  |
//|【戻値】なし                                                      |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
void PrintFormatLog(string aFileName, string aFunctionName, string aLogMessage)
{
  string timeString = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);

  int cnt = StringReplace(timeString, ".", "/");

  Print(",", timeString, ",File:,", aFileName, ",Function:,", aFunctionName, ",", aLogMessage);
}

//+------------------------------------------------------------------+
//|【関数】バー生成時チェック                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名              説明                         |
//|        --------------------------------------------------------- |
//|                 なし                                             |
//|                                                                  |
//|【戻値】true  : バー生成時                                        |
//|        false : バー生成時ではない                                |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
  static datetime dt = 0;

  if(Time[0] != dt){
    dt = Time[0];
    return(true);
  }

  return(false);
}

//+------------------------------------------------------------------+
//|【関数】時間足の文字列変換                                        |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      aPeriod            時間足                        |
//|                                                                  |
//|【戻値】時間足の文字列                                            |
//|                                                                  |
//|【備考】なし                                                      |
//+------------------------------------------------------------------+
string ToTimeFrameString(int aPeriod)
{
  if(aPeriod == PERIOD_M1){
    return("M1");
  }else if(aPeriod == PERIOD_M5){
    return("M5");
  }else if(aPeriod == PERIOD_M15){
    return("M15");
  }else if(aPeriod == PERIOD_M30){
    return("M30");
  }else if(aPeriod == PERIOD_H1){
    return("H1");
  }else if(aPeriod == PERIOD_H4){
    return("H4");
  }else if(aPeriod == PERIOD_D1){
    return("D1");
  }else if(aPeriod == PERIOD_W1){
    return("W1");
  }else if(aPeriod == PERIOD_MN1){
    return("MN1");
  }else{
    return("Unknown");
  }
}