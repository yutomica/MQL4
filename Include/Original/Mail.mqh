/*

# Mail.mq4
作成日：2017/1/27
更新日：2020/1/2

・Mail送付関数

*/


void MySendMail(string title,int type)
{
   string msg;
   string ordertype;
     
   /*Buy*/
	if(type == 1){ordertype = "Buy";}
	if(type == 2){ordertype = "Sell";}
	
	msg = StringConcatenate(
      "取引口座：",AccountCompany( ),
      "\n",
	   "\n注文種別：",ordertype,
	   "\n約定時刻：",TimeToStr(TimeCurrent()),
	   "\nAsk/Bid：",Ask,"/",Bid,
      "\n",
	   "\n口座残高 = ", AccountBalance( ),
      "\n純資産額 = ", AccountEquity( ),
      "\n余剰証拠金 = ", AccountFreeMargin( ),
      "\n必要証拠金 = ", AccountMargin( )
	);
	
	SendMail(title,msg);
}
