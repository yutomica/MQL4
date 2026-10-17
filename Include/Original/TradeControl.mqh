//+------------------------------------------------------------------+
//| TradeControl.mqh : 注文送信の排他と送信間隔だけを管理する          |
//+------------------------------------------------------------------+
#ifndef ORIGINAL_TRADE_CONTROL_MQH
#define ORIGINAL_TRADE_CONTROL_MQH

/*
使い方
  OnInitで TC_Init(送信間隔ms) を1回呼ぶ。全EAで同じ値を指定する。
  注文の直前に TC_Begin() を呼び、trueの時だけ次の処理へ進む。

    if(!TC_Begin()) return;        // 未送信。必要な要求はEA側で保持する。
    // ここで最新価格・対象注文・戦略条件を再確認する。
    // 見送る場合は TC_End(false) を呼んでからreturnする。
    ResetLastError();
    int ticket = OrderSend(...);   // Modify / Close / Deleteも同じ囲み方。
    int error = GetLastError();   // TC_Endより先に取得する。
    bool released = TC_End(true); // 注文成功/失敗にかかわらず、APIを呼んだらtrue。
    // ticketとerrorから、EAの保有状態・再試行方針を更新する。

約束
  ・BeginからEndまで、同じイベント内で注文APIを1回だけ呼ぶ。
  ・その間にSleepや長い処理を挟まない。注文を呼ばずに終了する時もEnd(false)が必要。
  ・Endの戻り値は制御の解放結果であり、注文の成否ではない。
  ・End(true)失敗後にEnd(false)で解放しない。時刻更新を再試行する場合もEnd(true)を使う。
  ・要求保持、期限、再試行、価格/ロット/Magic確認、結果不明時の照合はEAの担当。
  ・同じターミナルの利用EAが対象。銘柄・時間足・EA数で送信枠を分けない。
  ・公平な順番や最大待ち時間は保証しない。未使用EA・手動注文は制御対象外。
  ・異常終了/端末再起動からの注文復旧は行わない。再送前の照合はEAで行う。
  ・下記の共有変数やロックファイルを稼働中に削除・変更しない。

実運用では空のファイルを排他的に開き、開けたEAだけが送信する。
ファイルへのデータ書込みはない。共有する送信時刻/間隔は端末内の一時GVに置く。
テスターではEA内の変数とTimeCurrentを使い、実運用のファイル/GVには触れない。
*/

int      tc_interval_ms=0;                // 0は未初期化/設定エラー
int      tc_lock=INVALID_HANDLE;          // 実行権。テスター内だけは0を使用
string   tc_account="";                   // 初期化後の口座切替を検出する
datetime tc_test_completed=0;             // テスター内の前回API完了時刻
bool     tc_completion_pending=false;    // 完了保存失敗をEnd(false)で解除しない
bool     tc_file_waiting=false;
uint     tc_file_wait_started=0, tc_log_tick=0;
string   tc_last_error="";

// 設定を受け取るだけなので、複数EAが同時に初期化しても実行権を取り合わない。
// 実運用の設定一致はBeginで確認する。間隔を変える時は全EAの設定を揃えて端末再起動。
bool TC_Init(int interval_ms)
{
   if(interval_ms<=0 || tc_lock!=INVALID_HANDLE) return(false);
   tc_interval_ms=interval_ms;
   tc_account=AccountServer()+"#"+IntegerToString(AccountNumber());
   tc_test_completed=0;
   tc_completion_pending=false; tc_file_waiting=false; tc_last_error="";
   return(true);
}

// true: 実行権を取得した。false: 未送信なので、今回は戻って後続Tick/Timerで再確認。
// falseを注文失敗やエラー141として扱わない。Sleepや取得待ちループは使わない。
bool TC_Begin()
{
   if(tc_interval_ms<=0 || tc_lock!=INVALID_HANDLE || !IsTradeAllowed() ||
      tc_account!=AccountServer()+"#"+IntegerToString(AccountNumber())) return(false);

   if(IsTesting())
   {
      // 秒単位のテスター時刻で待つ。初回は直ちに送信できる。
      if(tc_test_completed>0 &&
         (double)(TimeCurrent()-tc_test_completed)*1000.0<tc_interval_ms) return(false);
      tc_lock=0;
      return(true);
   }

   // FILE_SHARE_*を付けない。通常の排他待ちを障害と断定せず、長時間待機だけを通知する。
   ResetLastError();
   tc_lock=FileOpen("TradeControl.simple.lock",FILE_BIN|FILE_READ|FILE_WRITE);
   if(tc_lock==INVALID_HANDLE)
   {
      int file_error=GetLastError();
      if(!tc_file_waiting){ tc_file_waiting=true; tc_file_wait_started=GetTickCount(); }
      if((uint)(GetTickCount()-tc_file_wait_started)>=30000)
      {
         Print("[TradeControl] api=FileOpen key=TradeControl.simple.lock error=",file_error,
               " state=WAITING reason=lock_busy_or_io_failure");
         tc_file_wait_started=GetTickCount();
      }
      return(false);
   }
   tc_file_waiting=false;

   // 一時GVは既存時に再作成しない。各APIを個別に確認し、一過性障害では設定を破棄しない。
   string keys[3]={"TradeControl.simple.interval","TradeControl.simple.completed","TradeControl.simple.active"};
   double values[3]={0,0,0};
   string failure="";
   int error=0;
   for(int i=0;i<3;i++)
   {
      ResetLastError();
      if(!GlobalVariableCheck(keys[i]) && !GlobalVariableTemp(keys[i]))
      { error=GetLastError(); failure="api=GlobalVariableTemp key="+keys[i]; break; }
      ResetLastError();
      if(!GlobalVariableGet(keys[i],values[i]))
      { error=GetLastError(); failure="api=GlobalVariableGet key="+keys[i]; break; }
      if(!MathIsValidNumber(values[i]) || values[i]<0)
      { failure="api=ValidateState key="+keys[i]; break; }
   }
   if(failure=="")
   {
      if(values[0]==0)
      {
         ResetLastError();
         if(GlobalVariableSet(keys[0],tc_interval_ms)==0)
         { error=GetLastError(); failure="api=GlobalVariableSet key="+keys[0]; }
         else values[0]=tc_interval_ms;
      }
      if(failure=="" && values[0]!=tc_interval_ms)
         failure="api=ValidateInterval key="+keys[0]+" reason=interval_mismatch";
      if(failure=="" && (values[1]>4294967296.0 || values[1]!=MathFloor(values[1]) ||
                          (values[2]!=0 && values[2]!=1)))
         failure="api=ValidateState reason=invalid_completion_or_active";
      if(failure=="" && values[2]==1)
      {
         // 排他ファイルを取得できたのにactiveなら、前所有者は保存を完了せず終了した。
         // 注文を再送せず、観測時刻から共通間隔を取り直して次の要求を待たせる。
         ResetLastError();
         if(GlobalVariableSet(keys[1],(double)GetTickCount()+1.0)==0)
         { error=GetLastError(); failure="api=GlobalVariableSet key="+keys[1]+" phase=recover"; }
         else
         {
            ResetLastError();
            if(GlobalVariableSet(keys[2],0)==0)
            { error=GetLastError(); failure="api=GlobalVariableSet key="+keys[2]+" phase=recover"; }
            else Print("[TradeControl] state=RECOVERED reason=previous_owner_incomplete interval_ms=",tc_interval_ms);
         }
         // 復旧したイベントでは注文を許可しない。
      }
      else if(failure=="" && (values[1]==0 ||
              (uint)(GetTickCount()-(uint)(values[1]-1.0))>=(uint)tc_interval_ms))
      {
         // API前の印は、完了時刻が書けないまま所有EAが終了する場合の間隔保護に使う。
         ResetLastError();
         if(GlobalVariableSet(keys[2],1)==0)
         { error=GetLastError(); failure="api=GlobalVariableSet key="+keys[2]+" phase=begin"; }
         else
         {
            if(tc_last_error!="") Print("[TradeControl] state=READY reason=storage_recovered");
            tc_last_error="";
            return(true);
         }
      }
   }
   if(failure!="" && (failure!=tc_last_error || (uint)(GetTickCount()-tc_log_tick)>=30000))
   {
      Print("[TradeControl] ",failure," error=",error," state=WAIT_RETRY");
      tc_last_error=failure; tc_log_tick=GetTickCount();
   }
   FileClose(tc_lock);
   tc_lock=INVALID_HANDLE;
   return(false);
}

// api_called=true : 成否にかかわらず、注文APIの完了時刻を記録してから解放する。
// api_called=false: 注文APIを一度も呼ばずに見送った場合。送信時刻は進めない。
// この関数自体は注文を送信せず、自動再試行もしない。
bool TC_End(bool api_called)
{
   if(tc_lock==INVALID_HANDLE) return(false);
   if(tc_completion_pending && !api_called) return(false);
   if(IsTesting())
   {
      if(api_called) tc_test_completed=TimeCurrent();
   }
   else
   {
      if(api_called)
      {
         tc_completion_pending=true;
         ResetLastError();
         if(GlobalVariableSet("TradeControl.simple.completed",(double)GetTickCount()+1.0)==0)
         {
            int error=GetLastError();
            string failure="api=GlobalVariableSet key=TradeControl.simple.completed phase=end";
            if(failure!=tc_last_error || (uint)(GetTickCount()-tc_log_tick)>=30000)
            {
               Print("[TradeControl] ",failure," error=",error," state=LOCK_HELD_RETRY");
               tc_last_error=failure; tc_log_tick=GetTickCount();
            }
            return(false);
         }
      }
      ResetLastError();
      if(GlobalVariableSet("TradeControl.simple.active",0)==0)
      {
         int error=GetLastError();
         string failure="api=GlobalVariableSet key=TradeControl.simple.active phase=end";
         if(failure!=tc_last_error || (uint)(GetTickCount()-tc_log_tick)>=30000)
         {
            Print("[TradeControl] ",failure," error=",error," api_called=",api_called);
            tc_last_error=failure; tc_log_tick=GetTickCount();
         }
         if(api_called) return(false); // API完了保存と所有印の消去が揃うまで保持する。
         // 未送信ならロックを返せる。残ったactiveは次Beginが保守的に間隔待ちへ復旧する。
         FileClose(tc_lock); tc_lock=INVALID_HANDLE;
         return(false);
      }
      FileClose(tc_lock);
   }
   tc_completion_pending=false;
   tc_lock=INVALID_HANDLE;
   return(true);
}

#endif // ORIGINAL_TRADE_CONTROL_MQH
