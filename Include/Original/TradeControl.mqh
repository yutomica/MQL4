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

// 設定を受け取るだけなので、複数EAが同時に初期化しても実行権を取り合わない。
// 実運用の設定一致はBeginで確認する。間隔を変える時は全EAの設定を揃えて端末再起動。
bool TC_Init(int interval_ms)
{
   if(interval_ms<=0 || tc_lock!=INVALID_HANDLE) return(false);
   tc_interval_ms=interval_ms;
   tc_account=AccountServer()+"#"+IntegerToString(AccountNumber());
   tc_test_completed=0;
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

   // FILE_SHARE_*を付けず、同じファイルを他EAが同時に開けないようにする。
   tc_lock=FileOpen("TradeControl.simple.lock",FILE_BIN|FILE_READ|FILE_WRITE);
   if(tc_lock==INVALID_HANDLE) return(false);

   // 必ず実行権取得後に時刻を読む。他EAが送信する前の古い値は使わない。
   // Tempは既存値を上書きしない。端末終了時には消えるのでPC再起動にも持ち越さない。
   double interval=0, completed=0;
   if(GlobalVariableTemp("TradeControl.simple.interval") &&
      GlobalVariableTemp("TradeControl.simple.completed") &&
      GlobalVariableGet("TradeControl.simple.interval",interval) &&
      GlobalVariableGet("TradeControl.simple.completed",completed))
   {
      // 最初に利用するEAが共通間隔を設定する。この処理も排他区間内で行う。
      if(interval==0 && GlobalVariableSet("TradeControl.simple.interval",tc_interval_ms)!=0)
         interval=tc_interval_ms;
      if(interval==tc_interval_ms)
      {
         // 0は未送信を表すため、共有時刻はGetTickCount()+1で記録する。
         // uintの差分で約49.7日ごとのカウンタ一周にも対応する。
         if(completed==0 || (uint)(GetTickCount()-(uint)(completed-1.0))>=(uint)tc_interval_ms)
            return(true); // Endまでハンドルを保持し、実行権を渡さない。
      }
      else
      {
         Print("[TradeControl] 送信間隔が他EAと異なります。全EAの設定を揃えてください。");
         tc_interval_ms=0; // 同じ設定エラーを毎Tick出力しない。
      }
   }
   else
   {
      Print("[TradeControl] 共通の送信時刻を読み取れないため、送信を停止します。");
      tc_interval_ms=0;
   }

   FileClose(tc_lock); // 間隔待ち/設定エラーなら、実行権だけを返す。
   tc_lock=INVALID_HANDLE;
   return(false);
}

// api_called=true : 成否にかかわらず、注文APIの完了時刻を記録してから解放する。
// api_called=false: 注文APIを一度も呼ばずに見送った場合。送信時刻は進めない。
// この関数自体は注文を送信せず、自動再試行もしない。
bool TC_End(bool api_called)
{
   if(tc_lock==INVALID_HANDLE) return(false);
   if(IsTesting())
   {
      if(api_called) tc_test_completed=TimeCurrent();
   }
   else
   {
      if(api_called &&
         GlobalVariableSet("TradeControl.simple.completed",(double)GetTickCount()+1.0)==0)
      {
         // 時刻更新に失敗したまま次の送信を許さない。注文結果はEA側で処理する。
         Print("[TradeControl] 送信時刻の更新に失敗したため、実行権を保持します。");
         return(false);
      }
      FileClose(tc_lock);
   }
   tc_lock=INVALID_HANDLE;
   return(true);
}

#endif // ORIGINAL_TRADE_CONTROL_MQH
