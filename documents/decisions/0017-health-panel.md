# ADR 0017: ダッシュボードに、RPi・Mac miniの健全性パネルを追加する

- 状態: Accepted (2026-09-20)
- 文脈タグ: Open MCT, 運用

## 背景

[ADR 0016](0016-publish-docs-via-github-pages.md)でダッシュボードを
一般公開した直後、ユーザーから「RPiとMacの健全性・負荷状況・温度などを
表示するパネルを追加しようか」と提案があった。2026-09-19〜20の2日間、
サーマルスロットリング・USB干渉・TCC権限問題・壊れたセグメント・
ゲイン過負荷と、運用面のトラブルが多かったことを踏まえると、
パイプラインが「今生きているか」を可視化する価値は高いと判断した。

## 決定

`scripts/update-health.sh`を新規追加し、`docs/data/health.json`を
`sync-segments.sh`の各tickで更新する。`kikimimi-provider.js`に
「パイプラインの健全性」パネルを追加し、RPi・Mac mini役の機体それぞれの
温度・負荷平均・録音サービスの状態を表示する。

### 公開する情報の絞り込み

このダッシュボードは既に一般公開されているため([ADR 0016](0016-publish-docs-via-github-pages.md))、
何を出すかは慎重に決めた。

- **個体のホスト名・IPアドレスは一切出さない。** ラベルは常に
  「RPi」「Mac mini」の2つの一般名詞のみ(ユーザーの指定)。
  プロジェクト全体で一貫している「個体固有の識別情報は`.env`のみ、
  公開場所には出さない」という方針([ADR 0009](0009-rpi-os-trixie-cloudinit-just.md))を、
  一般公開データについても同じ厳しさで適用した
- **温度・負荷平均値はユーザーの利便性のため公開する**(最初の提案では
  詳細値は非公開ログに留める案を出したが、ユーザーが公開を選んだ)
- 詳細な診断ログ(`journalctl`・`~/Library/Logs/kikimimi/*.log`)は
  引き続き非公開のまま

### Mac側の温度は取得しない

Apple SiliconのCPU温度は`sudo powermetrics --samplers smc`でしか
確実に取得できないことが分かった。`osx-cpu-temp`のような無料ツールは
Intel Mac世代のSMCセンサー方式にしか対応しておらず、Apple Siliconでは
`0.0°C`という無効値しか返さなかった。`sudo`は非対話SSHセッションでは
パスワード入力が必須になり(このセッション内で繰り返し確認済みの制約)、
リモートから自動化できない。**ユーザーの判断で「Macの温度は無理なら
やらなくていい」と、この項目は見送った。** Mac側は負荷平均値のみ表示する。

### データ収集方法

`update-health.sh`は`sync-segments.sh`と同じMac mini役の機体で実行し、
1回のSSH往復でRPiから`vcgencmd measure_temp`・`/proc/loadavg`・
`systemctl is-active kikimimi-record.service`をまとめて取得する。
Mac側は`uptime`をローカルで実行するだけ(SSH不要)。取得に失敗しても
`sync-segments.sh`本体は止めない(`|| log "..."`で握りつぶし、パイプラインの
本筋である録音→転写→lens→表示更新を優先する)。

`kikimimi-provider.js`側も、`health.json`の取得に失敗した場合は
「健全性データを取得できませんでした。」と表示するだけで、ダッシュボード
本体(頻度プロット・イベント一覧)の表示は妨げない。

## 影響

- `docs/data/health.json`が`docs/data/live.json`と並んで一般公開される
- 実機で確認: RPi(68.6℃、負荷0.54、録音: 正常)・Mac mini(負荷1.35、
  温度は非表示)が正しく描画されることをブラウザで確認済み

## 検討した代替案

- **健全性データもlive.jsonに統合する**: 却下。検出データ(社会センサーの
  本体)と運用メタ情報は性質が異なるため、別ファイル・別fetchに分離する
  方が関心の分離として適切
- **Macの温度取得のためsudoのNOPASSWD設定を追加する**: 保留。
  `visudo`での設定変更が必要で、ユーザー側の一度きりの作業になる。
  今回はユーザー自身が「無理ならやらなくていい」と判断したため見送った。
  将来欲しくなれば再検討する
