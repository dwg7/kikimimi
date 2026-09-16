# ADR 0008: 合成ダッシュボードはOpen MCT純正のDisplay Layoutではなく、単一のカスタムビューで実装する

- 状態: Accepted (2026-09-16)
- 文脈タグ: UI, Open MCT

## 背景

[ADR 0005](0005-open-mct-composite-dashboard.md)は「4種のコンテンツを1つの
合成ダッシュボードとして見せる」という方向性(m3xx-fleet型)を決めた際、
Open MCT純正の**Display Layout**でこれを組む想定だった。同ADRは同時に、
「PlanLayoutが非永続オブジェクトと相性が悪くエラーを起こす」という
3プロジェクト一致の記録があり、Display Layout系の機能も同様の制約を
持つ可能性がある、とも記していた。

実装に入るにあたり、cafebabe経由で`m3xx-fleet`(`/Users/hfu/m3xx-fleet/plugins/fleet-provider.js`)
と`sas0`(`/Users/hfu/sas0/docs/core.js`、`instruments/quake-trend.js`)の
実コードを直接確認した。

## 分かったこと

どちらのプロジェクトも、Display Layoutを一切使っていない。「複数の情報を
1画面にまとめる」という同じ目的を、**1つのobject provider(非永続・
合成/computed)+ 1つのview provider**で達成している。view providerの
`view()`が返す`show(element)`の中で、プレーンなDOM(HTMLテーブル、
手書きのstat card、SVG)を直接組み立てて`element`に流し込む。これは
ADR 0005が懸念した「非永続オブジェクトとDisplay/PlanLayoutの相性問題」を
そもそも踏まない、実績のある回避策になっている。

## 決定

kikimimiの合成ダッシュボードも、Open MCT純正のDisplay Layoutは使わず、
`openmct/plugins/kikimimi-provider.js`の単一view provider内で、頻度
プロット(SVG)・イベントログ(HTMLテーブル)・LADサマリー(stat card)を
直接描画する。`openmct/layouts/`は使わないため削除した。

Notebookだけは例外で、Open MCT純正のNotebook plugin(`openmct.plugins.Notebook()`)
をそのままインストールし、`openmct.plugins.MyItems()`配下に人間が
「+Create」で作成する、実在の永続オブジェクトとして使う。これは
Display Layout/PlanLayoutとは別の機能であり、非永続オブジェクトを
巻き込まないため、上記の懸念には当たらない。

## 影響

- [CLAUDE.md](../../CLAUDE.md)3節のUIマッピング表・5節の構成図は、この
  ADRに合わせて更新した(`layouts/`を削除、Plot/Table/LADは「単一ビュー内の
  描画要素」という位置づけに修正)
- Open MCTの標準的な「+Create → Display Layout → ドラッグして配置」という
  GUI操作は、kikimimiのダッシュボードでは発生しない(ダッシュボードは
  コードで組み立てられ、レイアウトの調整もコード側で行う)。UIをGUIで
  微調整したい場合は、この設計を見直す必要がある

## 検討した代替案

- **当初案通りDisplay Layoutで組む**: 却下。実績のある確実な経路
  (m3xx-fleet/sas0)が既にあり、ADR 0005が懸念した通りのリスクを
  わざわざ引き受ける理由がない
