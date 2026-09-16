# ADR 0002: 地名grounding(locitorium/Nominatim)を省略する

- 状態: Accepted (2026-09-16)
- 文脈タグ: アーキテクチャ, 依存, 地図

## 背景

OpenSpeechMapの`speechmap lens`は、自由文から言及された地名を抽出し、
[locitorium](https://github.com/yuiseki/locitorium)経由でOSM実体に
grounding(接地)する。locitoriumは自前のLLMエンドポイントとNominatim
インスタンスを必要とし、Nominatimの日本国内インポートはNVMeと大きな
RAMを要求する。

kikimimiが監視する対象は**十勝岳という既知の単一地点**であり、自由文
からの地名抽出そのものは今回の主眼ではない。UI設計([CLAUDE.md](../../CLAUDE.md)
3節)も、地図ビューを持たない、時系列+イベントログ+Notebookの構成に
既に決めている。したがって、地名groundingの出力(`places.geojson`)は
そもそも使わない。

## 調査したこと

`speechmap lens`が地名groundingを本当に「使わなければ気にしなくていい」
ものかどうかを、`src/openspeechmap/pipeline.py`を読んで確認した。

結果、`pipeline.run()`は冒頭で`locitorium = find("locitorium")`を
無条件に呼んでおり(`tools.py`の`find()`は、PATH上にもLOCITORIUM環境
変数が指す先にも見つからなければ`ToolError`を投げて即座に失敗する)、
これは地図出力を使う・使わないに関係なく発生する。`speechmap lens`
コマンドには、地名groundingだけを無効化するフラグは無い。

## 決定

locitorium本体・Nominatim・実際のLLM呼び出しは導入せず、代わりに
**`locitorium resolve`のCLI契約だけを満たすスタブ**を`locitorium`と
いう名前でPATHに置く。

この手法はOpenSpeechMap自身のテストスイート
(`tests/stubs/locitorium`)で、Nominatimなしにテストを走らせるために
既に使われている。標準入力でJSONLを受け、`--format geojson`のとき
標準出力にGeoJSON `FeatureCollection`を返す、という契約だけを満たせば
よい。kikimimiでは地図出力自体を使わないため、空の
`FeatureCollection`を返すだけでよく、既知の地名テーブルを持たせる
必要すらない。

実装は[scripts/locitorium-stub.sh](../../scripts/locitorium-stub.sh)。
Mac mini側のセットアップ(`scripts/setup-macmini.sh`)でPATHに配置する。

## 影響

- Nominatimの日本国内インポート(NVMe、大きなRAM)が一切不要になる
- locitorium自体の環境構築(自前のLLMエンドポイント含む)も不要になる
- `speechmap lens`の出力のうち`places.geojson`は常に空になる。使わない
  ので実害はないが、`speechmap lens`実行時のログに「0 places」が出る
  ことは想定内であり、故障ではない
- 将来、他のレンズ(他の火山、他のテーマ)で自由文からの地名抽出が
  必要になった場合は、このスタブを外し、実際のlocitorium/Nominatim
  環境を構築する必要がある。その際はこのADRを Superseded にすること

## 検討した代替案

- **`speechmap lens`にフラグを追加するようOpenSpeechMap本体を改修する**:
  却下(今回は)。フォークして本体に手を入れると、アップストリームの
  更新を素直に追えなくなる([ADR 0001](0001-build-on-openspeechmap.md)の
  判断と矛盾する)。将来、同種のニーズがdwg7の他プロジェクトからも
  出るようであれば、upstreamへの提案を検討する価値はある
- **実際にNominatimを導入する**: 却下。今回のスコープ(十勝岳一点)には
  過剰な投資であり、CLAUDE.mdで最初から避ける方針が定まっていた
