# ADR 0007: AGENTS.mdはtokachi-lens確定後に追加する

- 状態: Accepted (2026-09-16)
- 文脈タグ: 運用, ドキュメント

## 背景

OpenSpeechMap自身の`AGENTS.md`は、プロジェクトの経緯・引き継ぎ文脈
(`CLAUDE.md`の役割)とは別の役割を持つ。`COMMANDS.md`が「AGENTS.mdは
このパイプラインを実際に動かすagent向けの契約」と明記する通り、何が
candidateで何がverdictでないか、接地失敗をどう読むか、といった
**出力の読み方の契約**である。

kikimimiでも、`tokachi-lens`の出力(是非ではなく候補)をどう読むべきかは、
同じ理由でagent向けの契約として書く価値がある。ただし、これは
`CLAUDE.md`(引き継ぎ文脈)の代替ではなく追加であり、`tokachi-lens`の
内容そのものが人間の確認待ちだった段階では時期尚早だった。

## 決定

- `CLAUDE.md`(引き継ぎ・経緯)は現状維持。フリート運用の起動規約
  (ユーザーのグローバルCLAUDE.md、kaga0・rpi-geoserver0との相互参照)
  との整合を優先する
- `AGENTS.md`(kikimimi自身の出力契約)は、`tokachi-lens`の内容が
  人間によって確定した後に追加する。2026-09-16時点で`tokachi-lens`は
  一通り人間のレビューを終えているため、次のマイルストーン
  (Open MCTダッシュボードの試作)と並行して着手してよい

## 検討した代替案

- **AGENTS.mdに一本化する**: 却下。AGENTS.mdはOpenSpeechMap本体の
  慣習では「出力契約」という別の役割を持っており、フリート運用の
  引き継ぎ文脈をそこに混ぜると、他のdwg7プロジェクトとの一貫性が
  崩れる
