# ADR 0006: `docs/`はGitHub Pages用に予約し、ADR等は`documents/`に置く

- 状態: Accepted (2026-09-16)
- 文脈タグ: 運用, リポジトリ構成

## 背景

[ADR 0004](0004-single-output-path-github-pages.md)で、Open MCTダッシュボードは
`stars`と同じ方式でGitHub Pagesへプッシュする方針を決めている。GitHub Pagesは
リポジトリのmainブランチ直下の`docs/`をそのまま公開ディレクトリとして使う設定が
選べる。プロジェクト文書(ADR等)を先に`docs/`に置いてしまうと、後で
ダッシュボードの公開設定をする際に名前が衝突する。

## 決定

ADR等のプロジェクト文書は`documents/decisions/`に置く。`docs/`はGitHub Pagesの
公開ディレクトリとして予約し、他の用途に使わない。

## 影響

- `docs/`は将来Open MCTダッシュボードのビルド成果物専用になる
- 本リポジトリ内の相対リンクはすべて`documents/decisions/...`を指す。
  OpenSpeechMap本体(別リポジトリ)の`docs/ADR/`・`docs/PREREQUISITES.md`
  への参照はそのまま(あちらの`docs/`はこの制約の対象外)

## 検討した代替案

- **`docs/`にADRを置き、GitHub Pagesはgh-pagesブランチや`/docs`以外の
  設定にする**: 却下。`stars`が`docs/`直下運用の実績を持っており、
  それに揃える方が手数が少ない
