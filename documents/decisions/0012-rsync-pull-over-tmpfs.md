# ADR 0012: RPi→作業用Macのセグメント転送は、tmpfs録音 + rsync pullとする

- 状態: Accepted (2026-09-19)
- 文脈タグ: ハードウェア, 運用
- 関連: [ADR 0011](0011-transcription-moves-to-macmini-role.md)(この転送が
  必要になった理由)

## 背景

[ADR 0011](0011-transcription-moves-to-macmini-role.md)で、whisper.cppに
よる文字起こしをRPi 4Bから作業用Mac(Mac mini役)へ移す決定をした。これに
伴い、RPiで`speechmap record`が生成するセグメントファイル(`.ts`、60秒
あたり数百KB)を作業用Macへ転送する仕組みが新たに必要になった。

検討中、以下の論点が挙がった:

1. rsyncのような「ファイルをコピーする」方式と、CIFS/SMBのような
   「ネットワーク共有をマウントする」方式のどちらが良いか
2. RPiのmicroSDカードへの書き込みをできるだけ避けたい(長期運用での
   カード寿命への配慮)
3. 真のストリーミング処理が理想だが、[CLAUDE.md](../../CLAUDE.md)・
   OpenSpeechMap自身の設計方針(ファイルベース、各段階が独立して
   再実行可能)に従い、今回はセグメント単位のバッチ処理を維持する
   (2026-09-19、ユーザー確認)
4. 無理をしすぎない、省資源な設計にする

## 調査

決定の前に、OpenSpeechMap自身のソース(`record.py`・`transcribe.py`)を
RPi実機上で直接確認した。

- `speechmap record --out <dir>`の`<dir>`は普通のディレクトリであれば
  何でもよい(ffmpegがそこに`<label>-YYYYMMDD-HHMMSS.ts`という名前で
  書き込むだけ)。ネットワークマウントである必要も、ローカルディスクで
  ある必要もない
- `transcribe.py`の`started_at()`のコメントに、**「ファイル名を優先する
  のは、コピーされた/rsyncされたファイルはmtimeを失うから」**と明記
  されている——upstream自身がrsync的な転送を前提にした設計であることが
  読み取れる
- `speechmap transcribe --skip-newest`は「`speechmap-record`が今も
  書き込み中の最新ファイルを次回に回す」ためのフラグで、まさに
  「常に増え続けるディレクトリに対して定期的にtranscribeを回す」
  という今回のユースケース向けに用意されている
- `speechmap record`には`--retention-hours`(既定168時間)・
  `--max-gb`(既定50GB)による自動掃除が既に組み込まれている
- RPi実機のRAMは3.7GB中2.5GBが空き。60秒セグメントでの想定データ量は
  1日あたり最大でも1GB未満(実測: 60秒/約480KB〜600KB台)

## 決定

**RPi側の録音先をtmpfs(RAM上のディレクトリ)にし、作業用Macが定期的に
rsyncで取りに行く(pull)。** CIFS/SMB等のネットワーク共有マウントは
採らない。

```
RPi 4B
  speechmap record --out /mnt/kikimimi-audio (tmpfs)
    → SDカードには一切書き込まれない
    → --retention-hours を短め(tmpfsのサイズに収まる範囲)に設定

作業用Mac(cron/launchdで定期実行、scripts/sync-segments.sh)
  rsync -a <RPi>:/mnt/kikimimi-audio/ ~/kikimimi-audio/
  speechmap transcribe ~/kikimimi-audio --skip-newest --out ~/kikimimi-transcripts
```

### なぜCIFSではなくrsyncか

- **録音プロセス自体をネットワークから切り離せる。** CIFSマウントを
  録音先にすると、ネットワーク瞬断時に`rtl_fm | ffmpeg`パイプが詰まる
  リスクがある(今日孤児プロセス問題で経験した種類の壊れ方に近い)。
  rsyncを別プロセスとして疎結合にしておけば、同期が止まっても録音自体は
  ローカル(tmpfs)で継続できる
- **upstreamの設計と整合する。** 上記の通り、`transcribe.py`はrsync的な
  転送(ファイル名保持・mtime非依存)を明示的に想定している
- **新しいサービスを増やさない。** smbd/NFSサーバーのような常駐サービスを
  RPi側・Mac側どちらにも追加せずに済む。「無理をしすぎない、省資源に」
  という方針([ユーザー確認、2026-09-19])に合う

### なぜtmpfsか(SDカードを一切触らない)

- `speechmap record`の`--out`は任意のディレクトリでよいと確認済みなので、
  tmpfsに向けるだけで**音声セグメントがSDカードに一度も書き込まれなく
  なる**。長期運用でのSDカード摩耗という、rpi-geoserver0・kaga0双方でも
  意識されてきたリスクを、この経路については構造的に無くせる
- データ量が小さい(1日最大1GB未満)ため、RAMを圧迫しない。tmpfsサイズは
  512MB〜1GB程度で十分な安全マージンが取れる
- 代償: tmpfsは揮発性なので、RPiが再起動・電源断すると、直近で
  rsyncされていないセグメントは失われる。「状況認識のための補助的な
  signal」という位置づけ([README.md](../../README.md))であり、
  90日間の観測全体を左右するような重大な損失ではないと判断する
  (通常運用なら同期間隔は数分オーダーで、失われうるのはその範囲のみ)

### 削除ロジックを増やさない

「同期完了を確認してから削除する」という組み方も考えられるが、
今回は採らない。`speechmap record`の`--retention-hours`/`--max-gb`
という既存の(実績のある)掃除機能にそのまま任せ、同期スクリプト側には
削除ロジックを一切持たせない。同期が一時的に遅れても、retention
window内であれば単に次のrsyncで拾われるだけで、二重の状態管理
(「送った/送っていない」をどこかで記録する)を避けられる

## 実装

- `scripts/sync-segments.sh`(作業用Mac側、新規): rsync pull →
  `speechmap transcribe --skip-newest`を1セットで実行。多重起動防止に
  `flock`を使用
- `scripts/setup-rpi.sh`: whisper.cppのビルド手順を削除(ADR 0011により
  RPiでは不要)。tmpfsマウントのセットアップ手順を追加
- `scripts/setup-macmini.sh`: whisper.cppのビルド手順(Metal backend)を
  追加。転送手段が未定だった箇所を`scripts/sync-segments.sh`への参照に
  更新
- `.env.example`: `KIKIMIMI_RPI_AUDIO_DIR`・`KIKIMIMI_LOCAL_AUDIO_DIR`・
  `KIKIMIMI_TRANSCRIPT_DIR`を追加
- `Justfile`: `sync-segments`タスクを追加

**同期を定期実行するcron/launchdジョブの実際の有効化(常駐化)は、人間の
確認を経てから行う。** スクリプト自体はClaude Codeの担当範囲
([CLAUDE.md](../../CLAUDE.md)4節)だが、作業用Macに常駐する自動実行の
仕組みを実際に組み込む(`launchctl load`する等)のは、範囲を超えると
判断した

## 実機検証(2026-09-19)

上記の実装一式を、RPi実機・作業用Mac実機の両方に適用して動作確認した。

- RPi実機に`/mnt/kikimimi-audio`(tmpfs、1GB)を作成・マウント
  (`scripts/setup-rpi.sh`のロジックを手動適用)。RAMは3.7GB中2.5GB空きの
  状態から、影響は無視できる範囲
- `speechmap record --out /mnt/kikimimi-audio --retention-hours 12
  --max-gb 0.8`でNHK-FM北海道(85.2MHz)を録音。**SDカードを一切使わずに
  60秒セグメント(約600KB)が正常に生成される**ことを確認
  (`df -h`でtmpfs使用量が実際に増減することも確認)
- 作業用Macに`scripts/sync-segments.sh`を配置し、`just sync-segments`で
  実行。**rsync pull → `speechmap transcribe --skip-newest`が1コマンドで
  完走**し、書き込み中の最新セグメント(262KB、まだ成長中)は正しく
  スキップされた
- 実際の放送内容(ジャズ番組、John Coltraneの特集)が転写された。
  英数字混じりの固有名詞も含め、実用的な精度で文字起こしできている
  ことを確認(smallモデル、Metal backend)

### 実装時に見つかった修正

- **macOSには`flock(1)`が無い**(Linuxのutil-linux由来)。
  `scripts/sync-segments.sh`の多重起動防止は、`mkdir`の原子性を使う
  方式に変更した(追加のツール導入が要らず、依存が増えない)
- **`.env`の`KIKIMIMI_RPI_HOST`(`.local`無しの想定)を、mDNS解決可能な
  形に補う処理が`scripts/sync-segments.sh`に無かった。** 裸のホスト名
  では`ssh`/`rsync`とも名前解決に失敗することを実機で確認し、
  `${KIKIMIMI_RPI_HOST%.local}.local`という形で補う処理を追加した。
  同じ問題が`Justfile`の`ssh`レシピにも(未使用のまま)潜んでいたため、
  あわせて修正した

## 常駐登録(2026-09-19、ユーザーの明示的な依頼を受けて実施)

`scripts/install-sync-timer.sh`を追加し、`scripts/sync-segments.sh`を
作業用Macのlaunchd LaunchAgent(`com.dwg7.kikimimi.sync-segments`、
60秒間隔の`StartInterval`、ログは`~/Library/Logs/kikimimi/sync-segments.log`)
として登録した。LaunchDaemonではなくLaunchAgentを選んだのは、
ログインユーザーのSSH鍵にアクセスできる必要があるため(rsync/sshの
実行に必要)。

実機で60秒間隔の連続実行を確認済み(23:55:32→23:56:32→23:57:33の
3回、いずれも正常終了)。`speechmap transcribe`の冪等性により、
新着セグメントが無いtickは「nothing to do」で軽く完了することも確認した。

登録時に2点、launchd/cronの非対話・非ログイン環境向けの修正を
`scripts/sync-segments.sh`に追加した:

- **PATHの補強**: launchd/cronはHomebrewや`uv`のパスを含まない最小限の
  PATHで起動するため、スクリプト冒頭で明示的に`/opt/homebrew/bin`・
  `$HOME/.local/bin`を追加するようにした(非対話SSHでbrewが見つからな
  かった、という[ADR 0011](0011-transcription-moves-to-macmini-role.md)
  の教訓と同じパターン)
- **`.env`の自動読み込み**: `just`経由なら`set dotenv-load`で自動的に
  読まれるが、launchd/cronから直接呼ばれる場合はそうならないため、
  スクリプト自身が`.env`が未読み込みなら読み込むようにした

## RPi側の常駐化(2026-09-20、ユーザーの明示的な依頼を受けて実施)

「しばらくデータを貯めてからOpen MCT実装を考える」という方針を受けて、
録音側(RPi)も同様にsystemdサービス化した——さもないと、そもそも
貯まるデータが無い。`scripts/install-record-service.sh`を追加し、
RPi実機に`kikimimi-record.service`(system-level、`User=hfu`、
`Restart=on-failure`)として登録した。`systemctl --user`ではなく
system-levelのunitを選んだのは、ログインセッションの維持
(`loginctl enable-linger`)を必要とせず、再起動後も自動起動するため。

周波数・ゲイン・局ラベル・segment-sec・retention設定は、暫定値のまま
`.env`(`KIKIMIMI_FREQ`等)から注入できるようにした——対象局・周波数は
[CLAUDE.md](../../CLAUDE.md)6節にある通りまだ正式決定していないため、
後で変えるときにスクリプトを書き換えずに済むようにする狙い。

実機で確認: サービス起動直後から新しいセグメントが生成され、
Mac側のlaunchd(`sync-segments`)が次のtick(60秒後)で自動的に
rsync・文字起こしを実行することを確認した。**これで録音から
文字起こしまでの経路全体が、人手を介さず継続稼働する状態になった**
(レンズ判定・時系列異常検知はまだ——[ADR 0011](0011-transcription-moves-to-macmini-role.md)
の通りMac mini役の機体のLLMエンドポイントが未構築のため)。

## 検討した代替案

- **CIFS/SMB共有をマウントし、そこに直接録音する**: 却下。上記の通り、
  録音プロセスがネットワークに直接依存することになり、堅牢性で劣る
- **RPi側からMacへpush(scp/rsync)する**: 却下。cloud-initがRPiの
  `authorized_keys`に作業用Macの鍵しか入れておらず、RPi→Mac方向の
  新しい鍵配布が必要になる。これは「RPiの設定に極力手を入れない」という
  今回の方針と逆行するため、既存のMac→RPi方向のSSHアクセスをそのまま
  使えるpull方式を選んだ
- **真のストリーミング転送(音声を都度送る)**: 却下(今回は)。
  OpenSpeechMapのファイルベース設計から外れ、レンズ判定の文脈の
  まとまりとの整合も別途必要になる。[ADR 0011](0011-transcription-moves-to-macmini-role.md)
  の「今後の検討事項」に記載済み
