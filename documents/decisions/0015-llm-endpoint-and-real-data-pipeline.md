# ADR 0015: LLMエンドポイント構築と、lens→series→Open MCTの実データ経路の検証

- 状態: Accepted (2026-09-20)
- 文脈タグ: ハードウェア, ソフトウェア, Open MCT

## 背景

CLAUDE.md 6節の残タスク「Mac mini役の機体側のLLMエンドポイント構築 — 物理作業」
は、実際に確認したところ**ほぼ完了済みだった**。ユーザーが以前に`ollama`を
導入し、日本語特化の**Tanuki-8B-dpo-v1.0**(GGUF、Q4_K_M)と、多言語対応の
**qwen2.5:14b**を既にダウンロード済みだったが、サーバーが起動していなかった
だけだった。この機会に、LLMエンドポイントの常駐化と、`speechmap
lens`→`speechmap series`→Open MCTという経路全体を、実際に蓄積したデータで
通す検証まで、ユーザーの承認を得て自律的に進めた。

## 決定・実施内容

### 1. ollamaの常駐化(launchd)、およびTCC問題の解決

`scripts/install-llm-service.sh`を新規作成し、`ollama serve`を
`com.dwg7.kikimimi.ollama`というLaunchAgentとして登録した
(`whisper-server`・`sync-segments`と同じ設計判断)。

**ハマった落とし穴**: 対話シェルから`nohup ollama serve &`で起動すると
正常に動くが、launchd経由だと`Ollama cloud disabled`のログの直後で
無応答のままハングする現象が発生した。切り分けのため、`~/github/dot.ollama/models`
(モデル実体の場所、dotfiles管理下のシンボリックリンク先)に対して
`ls`するだけの最小限のテスト用LaunchAgentを作ったところ、
**`Operation not permitted`**という明確なエラーが出た——launchdから
起動したプロセスは、対話シェルと違いmacOSのTCC(プライバシー保護)の
承認を経ていないため、このディレクトリへのアクセスがブロックされていた。
`~/whisper.cpp/models`への同様のテストは問題なく通ったため、**ホーム
ディレクトリ全体ではなく`~/github`配下に特有の制限**だと判明した。

**対処**: GUIでの許可(システム設定 > プライバシーとセキュリティ >
フルディスクアクセス)を求める代わりに、モデル本体(13GB)を
`~/ollama-models`という素のパスにコピーし、`OLLAMA_MODELS`環境変数を
明示的にこちらへ向けることで、GUI操作なしに完全にリモートから解決した。

### 2. speechmap lens/series/aiqの導入確認・不足分の補完

`speechmap check`で`aiq`・`locitorium`・`detempus`が未導入と判明。

- `detempus`のインストールが、今日のwhisper.cppビルドと**全く同じ**
  `MacOSX27.0.sdk`破損問題([ADR 0011](0011-transcription-moves-to-macmini-role.md))
  で失敗した。同じ`SDKROOT`固定の回避策で解決
- `aiq`(yuisekiさんのフォーク、`extract`コマンド付き)をクローンし、
  OpenSpeechMapの仮想環境へeditableインストール
- `locitorium`スタブ([ADR 0002](0002-omit-nominatim-grounding.md))を、
  sudo不要な`~/.local/bin`へ配置(sudoパスワードが非対話SSHで要求され、
  当初の`/usr/local/bin`インストールが失敗したため)
- `aiq extract`が`OPENAI_API_KEY`環境変数の**存在**を要求することが
  判明(値はOllamaには無視される)。ダミー値を設定して解決

### 3. 実データでのlens実行

`speechmap lens`を蓄積済み全711件の文字起こしに対して実行した結果、
**gateが31キーワードで711件全てを除外し、LLM呼び出し0回・0.68秒で
完走**した。想定通り、この日蓄積した放送内容に十勝岳関連の言及が
一件も無かったため。

### 4. `speechmap series`が「該当0件」でエラー終了する制約の発見

`speechmap series`は、`--select`が0件にしかマッチしない場合、
`Nothing to count`というエラーで終了し、**series.jsonを一切書き出さない**
(それどころか空のディレクトリだけ残す)ことが分かった。これは
kikimimiの実運用で最も頻繁に起きるはずの状態(十勝岳の言及が無い)を
正常系として扱えていない、という制約である。

**対処**: `scripts/lens-to-openmct.sh`側で、`labeled.jsonl`から
`is_tokachidake == true`のレコード数を先に数え、0件なら`speechmap series`
を呼ばずに`series: []`を直接生成するようにした。1件以上ある場合のみ
`speechmap series`を呼び、その出力(`{series: [{key, t: [...], value: [...],
baseline: [...], ...}]}`という、detempusのベースライン・異常検知情報を
含む配列形式)を、ダッシュボードが期待する単純な`{t, count}`のペア列に
変換する。

架空のテストレコード(「気象庁は本日、十勝岳の噴火警戒レベルを2から3に
引き上げ...」)を1件だけ用意し、実際にollama(qwen2.5:14b)で正しく
`is_tokachidake: true`・`alert_level_mentioned: 3`・`mentioned_measure:
"入山規制"`と判定できることも確認した。`labeled.jsonl`の1レコードは、
元の文字起こしフィールド(`t`・`seg`・`text`)とlensが追加したフィールド
(`category`・`is_tokachidake`・`alert_level_mentioned`・
`mentioned_measure`・`topic`)が1つのオブジェクトに結合された形になって
おり、これは`preview-fixture.json`の`events`配列とほぼ同じ形だった。

### 5. Open MCTでの実データ表示確認(検出0件・検出1件の両方)

`openmct/plugins/kikimimi-provider.js`の`DATA_URL`を
`data/preview-fixture.json`から`data/live.json`へ変更した。

ブラウザでの実機確認の結果:

- **検出0件(現在の実データ)**: 「まだ蓄積されたデータがありません。」
  「まだ検出されたイベントはありません。」と、既存の空データ処理
  ロジック(2026-09-16実装)がそのまま正しく機能し、エラーは一切
  発生しなかった。プレビュー用ダミーデータの警告バナーも(`note`
  フィールドが無いため)表示されず、実データとして正しく扱われている
- **検出1件(架空のテストデータ)**: LADサマリー・頻度プロット(点1つ)・
  イベント一覧(十勝岳のハイライト表示含む)いずれも正しく描画された

**つまり、録音→転送→文字起こし→lens判定→series集計→Open MCT表示
という経路全体を、本物のソフトウェアスタックで、検出ゼロ・検出ありの
両方の状態について確認できた。**

## 追記: sync-segments.shへの統合、常時自律稼働化(2026-09-20)

上記の手動検証を踏まえ、`scripts/sync-segments.sh`(60秒間隔のlaunchd
常駐ジョブ)に、lens適用とOpen MCTライブデータ更新のステップを追加した。
これで**録音(RPi/systemd)→転送・文字起こし・lens判定・series集計・
Open MCT表示更新という経路全体が、人手を介さず60秒サイクルで回る**
ようになった。

### 発見1: bash 3.2との非互換(`mapfile`)

壊れたセグメントを自動検知・隔離するロジックに`mapfile`(配列への
一括読み込みビルトイン)を使ったところ、`command not found`で
毎回失敗した。**macOSはGPLv3を避けるため、bash 3.2(2007年当時の
バージョン)を標準搭載し続けており、`mapfile`(bash 4以降で追加)が
存在しない。** RPi(Debian系、新しいbashが標準)とMac miniの両方で
同じスクリプトを書く際、この差に気づかず書いてしまった。`while read`
ループでの配列構築に書き換えて解決した。この種のbashバージョン差は
今後も踏み抜く可能性があるので記録しておく。

### 発見2: 壊れたセグメントの再発(2回目、5個同時)

`sync-segments.sh`を統合した直後、[ADR 0012](0012-rsync-pull-over-tmpfs.md)
で記録した「1個の壊れたファイルが後続すべてを止める」障害が**再発**し、
しかも今回は**5個同時**(`121342`・`125034`・`125538`・`135636`・`143039`の
各タイムスタンプ)だった。今日一日、アンテナ・ゲイン調整のために
`kikimimi-record.service`を何度も再起動したことが原因と見られる。

**今回は自動化した**: `sync-segments.sh`が毎tick、`--skip-newest`と同じ
「最新の1つを除く」ルールで全セグメントを`ffprobe`検査し、壊れている
ものを`~/kikimimi-audio-quarantine/`へ自動退避してから`speechmap
transcribe`を呼ぶようにした。これにより、今後同種の障害が起きても
**人間やClaude Codeの手動介入なしに自己修復する**ようになった。
RPi側の同名ファイルも手動で削除し(rsyncは削除を伝播しないため、
放置すると毎tick再取得され続ける)、以降は正常化した。

実機で2回連続のtickが正常完了(それぞれ23秒・24秒程度)することを
確認し、蓄積していたバックログ(208件→7件)も自動的に処理された。

## 影響

- CLAUDE.md 6節の「Mac mini役の機体側のLLMエンドポイント構築」は完了
- `scripts/install-llm-service.sh`・`scripts/lens-to-openmct.sh`を新規追加
- `.env`の`KIKIMIMI_LLM_URL`を`http://127.0.0.1:11434/v1`(ollama)に更新
- `openmct/data/live.json`が新しいデータソースとなり、
  `preview-fixture.json`はデザイン検討用の参考資料として残すのみになった
- **`speechmap series`の「0件でエラー」という制約は、上流
  (yuiseki/OpenSpeechMap)への改善提案の候補になり得る**。今回は
  kikimimi側のラッパースクリプトで吸収したが、根本的にはOpenSpeechMap
  自身が「稀にしか起きないイベントの監視」という用途を想定していない
  可能性がある
- 今回はlens→series→変換を手動で1回通しただけで、定期実行への組み込み
  (`sync-segments.sh`への統合等)はまだ行っていない。次のステップの
  候補として残す

## 検討した代替案

- **ollamaのTCC問題をGUIでの許可(フルディスクアクセス付与)で解決する**:
  却下。リモートセッションからはGUI操作ができず、モデルを非保護パスへ
  コピーする方が確実かつユーザーの手を煩わせない
