# Open MCT ダッシュボード

十勝岳への言及頻度・イベントログ・LADサマリーを1画面にまとめた、単一の
合成ダッシュボード。ビルドツールは使わない(m3xx-fleet・sas0と同じ、
CDNからOpen MCTを読み込む静的ページ構成)。

## 見る

```bash
python3 -m http.server 4173 --directory .
```

ブラウザで `http://localhost:4173` を開くと、ツリーに「十勝岳 聞き耳
ダッシュボード」と「My Items」が並ぶ。前者をクリックするとダッシュボードが
表示される(現状、起動直後に自動でこちらへ遷移する処理は入れていない。
m3xx-fleetも同様で、`router.setPath`をstartフックから呼ぶと内部エラーが
出たため踏襲していない。詳細は[ADR 0008](../documents/decisions/0008-single-custom-view-not-display-layout.md))。

コンソールに`Uncaught (in promise) TypeError: Cannot read properties of
undefined (reading 'key')`が1件出るが、これはm3xx-fleetの実際の稼働ページ
でも同じく発生することを確認済みで、Open MCT v4.3.1自体の既知の(無害な)
起動時ノイズ。kikimimi固有の問題ではない。

## 構成

```
index.html            CDNからOpen MCT 4.3.1・kikimimi-provider.jsを読み込む
style.css             ダッシュボードの見た目
plugins/
  kikimimi-provider.js root type・object provider・単一のview providerを
                       まとめて定義(SVGプロット・イベントログ・LADを
                       この中で直接DOM生成する。Display Layoutは使わない)
data/
  preview-fixture.json プレビュー用のダミーデータ(実データではない)。
                       実運用では`speechmap series`のseries.jsonと
                       `speechmap lens`のselected.jsonlを、この形に整形した
                       ファイルに置き換える(整形の変換ステップは未実装)
```

## 設計判断

- [ADR 0005](../documents/decisions/0005-open-mct-composite-dashboard.md) — 合成ダッシュボード(m3xx-fleet型)を選んだ理由
- [ADR 0008](../documents/decisions/0008-single-custom-view-not-display-layout.md) — Display Layoutではなく単一カスタムビューで実装した理由(m3xx-fleet・sas0の実コードを確認して決めた)

## Notebook(人間による確認・注釈)

`openmct.plugins.Notebook()`と`openmct.plugins.MyItems()`をインストール
済み。ツリーの「My Items」で「+Create → Notebook」から作成すると使える
(Open MCT純正の永続オブジェクト。ダッシュボード自体は読み取り専用の表示)。
`LocalStorage`プラグインで永続化しているため、同じブラウザ・同じ
`localStorage`である限り、ノートは再読み込み後も残る(共有はされない。
GitHub Pagesに静的公開した場合、閲覧者ごとに別々のノートになる点に注意)。

## まだやっていないこと

- Condition Setsを小さく検証してから、しきい値の色分けをそちらに置き換える
  かどうかの判断(現状はSVG側の自前ロジックで暫定実装済み)
- 実データへの接続(`speechmap`の出力を`data/`が読む形に整形する変換)
- レスポンシブ・モバイル対応の検討(CLAUDE.md 3節、dwg7として前例のない
  課題になる見込み)
