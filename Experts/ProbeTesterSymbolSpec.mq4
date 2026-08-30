#property strict

bool gPrinted=false;

void PrintTesterSymbolSpec()
  {
   Print("[ProbeTesterSymbolSpec] symbol=",Symbol(),
         " digits=",(int)MarketInfo(Symbol(),MODE_DIGITS),
         " point=",DoubleToString(MarketInfo(Symbol(),MODE_POINT),8),
         " spreadPoints=",DoubleToString(MarketInfo(Symbol(),MODE_SPREAD),2),
         " stopLevelPoints=",DoubleToString(MarketInfo(Symbol(),MODE_STOPLEVEL),2),
         " freezeLevelPoints=",DoubleToString(MarketInfo(Symbol(),MODE_FREEZELEVEL),2),
         " lotSize=",DoubleToString(MarketInfo(Symbol(),MODE_LOTSIZE),2),
         " tickValue=",DoubleToString(MarketInfo(Symbol(),MODE_TICKVALUE),8),
         " tickSizePoints=",DoubleToString(MarketInfo(Symbol(),MODE_TICKSIZE),8),
         " minLot=",DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),8),
         " lotStep=",DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),8),
         " maxLot=",DoubleToString(MarketInfo(Symbol(),MODE_MAXLOT),8),
         " profitCalcMode=",(int)MarketInfo(Symbol(),MODE_PROFITCALCMODE),
         " marginCalcMode=",(int)MarketInfo(Symbol(),MODE_MARGINCALCMODE),
         " marginInitial=",DoubleToString(MarketInfo(Symbol(),MODE_MARGININIT),8),
         " marginMaintenance=",DoubleToString(MarketInfo(Symbol(),MODE_MARGINMAINTENANCE),8),
         " marginHedged=",DoubleToString(MarketInfo(Symbol(),MODE_MARGINHEDGED),8),
         " marginRequired=",DoubleToString(MarketInfo(Symbol(),MODE_MARGINREQUIRED),8));
  }

int OnInit()
  {
   PrintTesterSymbolSpec();
   gPrinted=true;
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   if(!gPrinted)
     {
      PrintTesterSymbolSpec();
      gPrinted=true;
     }
  }
