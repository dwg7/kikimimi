# kikimimi — Claude Code 引き継ぎドキュメント

このファイルは `dwg7/kikimimi` リポジトリのルートに置く、Claude Code向けの
プロジェクト文脈。新しいセッションを開始する際は、まずこのファイルを
読んでください。

姉妹プロジェクト: [dwg7/kaga0](../kaga0/CLAUDE.md)、
[dwg7/rpi-geoserver0](../rpi-geoserver0/CLAUDE.md)(同じ「実装より先に調査」
「観測可能性を作り込む」という作法を踏襲)

---

## 1. プロジェクト概要・コンセプト

**kikimimi(聞き耳)** は、公共ラジオ放送を「社会センサー」として使い、
火山活動をめぐる社会の反応(報道量・言及の文脈)をテレメトリするプロジェクト。
第一の適用対象は**十勝岳**。

### 位置づけ(重要)

**十勝対応に参加する北海道地方測量部を、dwg7の観点から支援するプロジェクト。**
より precise に言えば:「dwg7帽子」の藤村さんが、「北海道地方測量部帽子」の
藤村さんを**外部支援**する、という構図。dwg7という立場は、GSIの公式対応の
指揮系統を代替・介入するものではなく、その外側から、軽量・機動的な
補助線を提供する立場に徹する。

### 公開範囲について

**public で進める。** dwg7がprivateなリポジトリを抱えすぎると、組織として
失速する(rpi-geoserver0のようなprivate運用は、対外的な合意形成が
必要な個人間プロジェクトには適切だが、それを標準化すべきではない)。
勇気を持ってオープンにする一方、品位は保持する——「verified intelligence
ではなく、状況認識のための補助的なsignalである(気象庁の噴火警戒レベル・
警報等の公式判断の代替ではない)」という、okapi-map以来一貫している言明を、
kikimimiでも崩さない。検出結果の公開時は、この留保を明示すること。

### 名前の由来

「聞き耳」(耳を澄まして聞く)と「危機」(kiki)の音を重ねた命名。
JMAの「キキクル」(危険度分布の愛称)と同じ、音の遊びによる命名の系譜。
リポジトリ名は機能そのもの(聞く、という行為)を指し、特定の対象(十勝岳)
に縛られない。将来、他の火山・他のテーマを監視する場合も、
リポジトリ名は変えず、レンズ(後述)を追加するだけで対応できる設計。

### 「社会センサーによるテレメトリ」という捉え方

JMA/GSIの公式観測網(地震計、GNSS、傾斜計)は**火山そのもの**を
テレメトリする。kikimimiは、**火山をめぐる社会の反応(報道量、言及の
文脈・頻度)**をテレメトリする、補完的なレイヤーとして位置づける。
報道量の時系列変化そのものが、公式観測データだけでは掴めない、
社会の受け止め方の推移という、独自の信号になる。

### 背景:十勝岳の状況(2026年9月時点、一次資料で確認済み)

8月17日以降、山体付近を震源とする振幅の大きな火山性地震が増加。
2026年9月12日09時30分、札幌管区気象台が噴火警戒レベルを2(火口周辺規制)
から3(入山規制)に引き上げ(気象庁報道発表、2026-09-12付、
`地震火山部`名義)。警戒範囲は**62-2火口から概ね3km**(大正火口とは別の
火口)。2026年4月以降、火山ガス(二酸化硫黄)放出量も増加傾向。

上富良野町では吹上温泉地区に避難指示、十勝岳温泉地区に高齢者等避難情報。
気象庁の警報対象市町村:富良野市、美瑛町、上富良野町、南富良野町、新得町。

**留意点(dwg7内の別プロジェクトから得た情報を、気象庁一次資料で裏取り済み)**:
火山防災協議会の構成自治体(上富良野町・**中富良野町**・美瑛町・富良野市・
新得町)と、気象庁の警報対象市町村(上富良野町・**南富良野町**・美瑛町・
富良野市・新得町)は**一致しない**(中富良野町/南富良野町が入れ替わる)。
放送中の言及からこの2つの地名を混同しないよう、レンズ設計・人間による
確認の両方で注意すること。

北海道地方測量部の管轄に関わる、進行中の事案。積雪期を挟んだ長期対応に
なる見込み。

---

## 2. 技術方針

### 土台:OpenSpeechMap(Yuiseki氏)の上に作る

ゼロから実装せず、[yuiseki/OpenSpeechMap](https://github.com/yuiseki/OpenSpeechMap)
(MIT license)を土台にする。理由:

- dwg7の仲間(Yuisekiさん)自身の実装であり、外部組織への従属ではなく
  与力/個人単位の多中心的協調の自然な実践
- MITライセンスで「税金」がほぼない
- アーキテクチャ(`ffmpeg`→`whisper.cpp`→`aiq`(レンズ)→`locitorium`
  (地名grounding)→`detempus`(時系列・異常検知)→GeoJSON)が、
  既にほぼ今回のニーズに合致している
- 「レンズ」という仕組みが、コードを書き換えずテーマを追加できる設計。
  レンズはディレクトリ内の3〜4つのテキストファイルだけで定義される
  (`schema.json`・`instruction.txt`必須、`system.txt`・`gate.txt`任意)
- `--source sdr`(RTL-SDR直接キャプチャ)が既にサポートされている

詳細は[documents/decisions/0001-build-on-openspeechmap.md](documents/decisions/0001-build-on-openspeechmap.md)。

既存レンズの`lenses/ja-radio-disaster`は、公開されている実測結果
(千葉豪雨・熊本地震での検出実績)を持つ「最初にコピーすべき」レンズ
(lenses/README.mdの推奨)。`tokachi-lens`はこれを土台に、対象を
十勝岳一点に絞り込んだもの。

### Nominatim(地名grounding)は省略

十勝岳という**既知の単一地点**を監視する構成なので、自由文からの地名抽出
は今回の主眼ではない。

**調査の結果**: `speechmap lens`(`aiq extract`→`jq select`→`locitorium
resolve`を束ねる内部コマンド)は、`locitorium`実行ファイルの存在を
`pipeline.py`の`run()`冒頭で無条件に`find()`しており、地図出力を使わない
場合でも、これが失敗すると`speechmap lens`全体が止まる。フラグでの
無効化は用意されていない。

回避策は、OpenSpeechMap自身のテストスイートが使っている手法
(`tests/stubs/locitorium`)を production 用に転用すること: `locitorium
resolve`のCLI契約(標準入力でJSONL、`--format geojson`で標準出力に
GeoJSON FeatureCollection)だけを満たす、空の`FeatureCollection`を返す
シェルスクリプトを`locitorium`という名前でPATHに置く。これで
Nominatimのインポート要件(NVMe、大きなRAM)を一切気にせず、
`speechmap lens`を通せる。詳細と実装は
[documents/decisions/0002-omit-nominatim-grounding.md](documents/decisions/0002-omit-nominatim-grounding.md)
と`scripts/locitorium-stub.sh`。

### ハードウェア構成:RPi 4B + Mac mini の役割分担

台数を増やして並列化する発想ではなく、**役割ごとに専任機を分ける**。

```
RPi 4B (RTL-SDR接続)
  → whisper.cpp で文字起こし(tiny/baseモデル、実時間より速く動作)
  → テキストを Mac mini の LLM エンドポイントに送信
Mac mini
  → LLM(レンズ判定): 十勝岳関連か、緊急度、文脈を分類
  → series(時系列・異常検知、detempus)
  → GeoJSON/出力生成 → Open MCT
```

- whisper.cppはRPi 4Bで十分にこなせる(ARM NEON最適化、tiny/baseモデルで
  実時間より速い、という実測報告あり)
- LLMエンドポイントはRPi単体では非現実的(小型量子化モデルでも遅い)。
  Mac miniのApple Silicon(統合メモリ)の方がローカルLLM推論に適する
- 既に購入済みのRTL-SDR Blog V4 R828D をRPi 4Bに接続する想定
- 詳細は[documents/decisions/0003-hardware-split-rpi-macmini.md](documents/decisions/0003-hardware-split-rpi-macmini.md)

---

## 3. UI設計:Open MCT

### オブジェクトのマッピング

| 検出したいこと | Open MCTのオブジェクト |
|---|---|
| 十勝岳への言及頻度(時系列) | **プロット**(SVG自前ロジック。Plot APIは使わない。理由は下記) |
| detempusの異常検知(閾値超え) | **しきい値の色分け**(未検証。Condition Setsの採用可否は小さく検証してから決める) — SVG側の自前ロジックで、しきい値以上の点を警戒色にする(OpenSpeechMap付属ビューアの「赤帯=閾値超え、紫線=水準シフト」に相当) |
| 個別の検出イベント(時刻・種別・措置・文字起こしの抜粋) | **イベントログ**(HTMLテーブル) |
| 現在の状態(直近の言及数、最終検出からの経過時間) | **LADサマリー**(stat card) |
| 人間による確認・注釈 | **Notebook plugin**(Open MCT純正、「マイアイテム」配下に人間が作成) — 「境界は人間の判断に委ねる」という、Unite Wave/JMACの議論で確認した原則をUIに落とし込む場所 |

これらのうちプロット・イベントログ・LADサマリーは、Open MCT純正の
**Display Layout**では組まない。単一のカスタムroot type + 単一のview
providerが、上記3つをまとめて描画する一枚のビューとして実装する
(m3xx-fleet・sas0の実コードを確認した上での判断。
[ADR 0008](documents/decisions/0008-single-custom-view-not-display-layout.md))。
Notebookだけは例外で、Open MCT純正の永続オブジェクトとして別に作成する。

Nominatimを外したことで地理的次元が不要になり、地図ビューを持たない、
純粋な時系列+イベントログ+人間の確認という構成に単純化されている。

### 出力先:単一の経路(RPiでWebサーバー+ブラウザは同時稼働させない)

**kaga0のノウハウは、このプロジェクトでは転用しない。** RPi上で
Webサーバーとブラウザを同時に動かす構成(キオスクモードを含む)は
採らない、という判断を承認済み。理由を問わず、RPiの役割は
**キャプチャ+文字起こしに徹する**、という境界を明確にしておく。

- RPi 4Bの仕事は、RTL-SDRでの録音とwhisper.cppでの文字起こしまで。
  結果はMac miniへ送るだけで完結し、RPi自身が何かを表示することはない
- Open MCTダッシュボードは、`stars`と同じ方式でGitHub Pagesへプッシュし、
  必要な人が必要な端末(Mac、ブラウザのある任意の端末)から見る、
  という単一の経路に絞る
- 「現場でのair-gapped表示」という当初のアイデアは、今回のスコープからは
  外す。将来必要になった場合は、改めて別の手段(kaga0とは別の設計)を
  検討する

### 既存のOpen MCTプロジェクトとの整合(横断エージェントより回答あり、2セッションにわたり確認済み)

cafebabe(横断知見リポジトリ)の蓄積に基づく回答が得られた。要点:

**1. どのプロジェクトが一番近いか**

分岐点は「型の数」ではなく「ビュー切り替えの選択肢を絞りたいかどうか」。
今回のように、4種のコンテンツ(頻度プロット・イベントログ・LAD
サマリー・Notebook)を**1つの合成ダッシュボード**として見せたいなら、
**m3xx-fleet型**(rootを`folder`ではなくカスタムtypeにし、そのtypeにだけ
自作ビューを紐付けて選択肢を1つに絞る)が一番近い。sas0は「多数の
交換可能な計器を1本のツリーに並べる」用途で、今回の「単一対象の複合
ビュー」とは動機が異なる。逆に4種を個別に独立して見たい場合は
claude-mct型が近くなる。**この「合成ダッシュボードか、個別ビューか」を
先に決めておくと設計が早まる**(想定は合成ダッシュボード→m3xx-fleet型)。

**2. Plot APIのリスクについて**

再発の可能性は現実的にある。sas0で見つかった「線も点も描画されない」
という主障壁は、claude-mctの最小再現環境でも(複数バージョンにわたって)
再現しているが、**claude-mctのフルアプリ(実際にsubscribeする構成)では
正常に描画されている**。今回subscribeを本格実装する予定がないなら、
**最初からSVGでの表現を計画しておくのが安全**(4プロジェクト中3件で、
既に実績のある確実な経路)。

Condition Setsについては、cafebabeにまだ横断実績がない。関連する知見
として、PlanLayoutが「非永続オブジェクト」と相性が悪くエラーを起こす、
という3プロジェクト一致の記録があり、Condition Setsも同様の制約を
持つ可能性がある。**本格採用前に小さく検証してから決める**のが良く、
しきい値の色分け自体は、実績のあるSVG側の自前ロジックとして実装する
方が手堅い。

**3. root登録の方式**

固定identifierでの踏襲は妥当(4プロジェクトとも関数/Promise版の実例は
まだない)。rootをカスタムtypeにする設計も、「既定のGrid Viewが
ビュー切り替えメニューに競合表示されるのを防ぐ」というm3xx-fleetの
動機がそのまま当てはまるなら妥当。将来、型を増やす方向に転じる場合は、
「1 namespace = 1 provider」制約の中での分岐ロジックが型数とともに
肥大化しやすい、という点は早めに意識しておくとよい。

**4. ツリーの見づらさ・モバイル対応**

cafebabeに横断的な記録はまだない。近いものとしてキオスクモードの技法
(`.l-shell__pane-tree`のCSS非表示)があるが、これは無人巡回表示用で、
モバイルでの対話的な操作性とは別の課題。横断的な改善が先行している
わけではないので、待つ理由はない。**kikimimiでこの課題に当たったら、
dwg7として初めての記録になる**——その際はcafebabeに書き戻す。

whisper.cpp on RPi 4Bの実測値、レンズ設計の知見についても、cafebabeには
まだ横断実績がない(2026-09-16時点で確認済み)。運用実績が積もったら
書き戻す。

---

## 4. 作業分担(重要)

kaga0・rpi-geoserver0と同じく、Claude Codeが単独で進めてよい範囲と、
人の手・判断を残す範囲を分ける。

### Claude Codeが担当してよい範囲

- `lenses/README.md`・`docs/PREREQUISITES.md`等の調査、要点の報告
- `tokachi-lens`の**初稿**の作成(3〜4テキストファイル)
- `setup-rpi.sh`・`setup-macmini.sh`等のセットアップスクリプトの作成
- Open MCTのプラグイン・ビュー(SVGプロット、イベントログ、LAD、Notebook型)の
  実装
- Condition Sets vs SVG自前ロジックの、小さなスパイク検証(動かして結果を
  見る、という調査段階まで)
- `documents/decisions/`へのADR記録
- `scripts/diagnose.sh`等、観測可能性を作り込むための診断コマンド一式

### 人の手・判断を残す範囲

- **RTL-SDRの物理接続、RPi/Mac miniの電源投入・実機確認**
  (kaga0・rpi-geoserver0と同じく、物理作業はエージェントの範囲外)
- **`tokachi-lens`の内容(何を検出条件とするか)の最終確認。**
  初稿はClaude Codeが書いてよいが、これは「何が検出され、何が
  検出されないか」を決める、**公開されるsignalの品質そのもの**に
  関わる判断。品位の保持(verified intelligenceではないと明示しつつ、
  質の低い誤検出を垂れ流さない)のため、稼働前に必ず人が内容を確認する
- **Condition Sets/SVGどちらを採用するか、という最終判断。** 検証結果を
  見た上で、どちらの経路を本採用するかは人が決める
- **公開する検出結果・抜粋の内容確認。** GitHub Pagesへ実際に何を
  プッシュするかは、特に稼働初期は人が一度目を通してから公開する。
  「状況認識のための補助的なsignal」という留保を保つための、最後の砦
- **90日間の観測期間中の解釈。** 異常検知(閾値超え)が出た際、それが
  実際に注目すべき事象か、単なる誤検出かの判断は、Notebook plugin上で
  人が行う

---

## 5. リポジトリ構成方針

```
dwg7/kikimimi/
├── README.md
├── CLAUDE.md                   # このファイル
├── documents/
│   └── decisions/               # なぜOpenSpeechMapの上に作るか、
│                                  # なぜNominatimを外すか等のADR
│                                  # (docs/ はGitHub Pages用に予約、使わない)
├── lenses/
│   └── tokachi-lens/            # 十勝岳向けのレンズ(3〜4テキストファイル)
├── openmct/                     # ビルドレス(CDNからOpen MCTを読み込む、
│                                  # m3xx-fleet/sas0と同じ静的ページ構成)
│   ├── index.html
│   ├── style.css
│   ├── plugins/                  # root type・単一のダッシュボードview
│   │                              # (Display Layoutは使わない。ADR 0008)
│   └── data/                     # プレビュー用ダミーデータ
│                                  # (実運用ではspeechmap seriesの出力に置換)
├── scripts/
│   ├── setup-rpi.sh              # RPi 4B側(RTL-SDR + whisper.cpp)
│   ├── setup-macmini.sh          # Mac mini側(LLMエンドポイント + locitorium stub)
│   ├── locitorium-stub.sh        # grounding省略用のダミーlocitorium
│   └── diagnose.sh
└── notes/
    └── observations.md           # 一緒に観察した結果の記録
```

---

## 6. 現時点でのステータス

- [x] コンセプト確立(「社会センサーによるテレメトリ」という捉え方)
- [x] 土台をOpenSpeechMapにする判断、Nominatimを外す判断
- [x] ハードウェア構成(RPi 4B + Mac mini)の判断
- [x] Open MCTでのUIマッピング方針の決定
- [x] プロジェクト名の決定(kikimimi、レンズ名はtokachi-lens)
- [x] 既存Open MCTプロジェクト群を担当する横断エージェントへの質問と回答
      (m3xx-fleet型を軸に、Plot APIはSVGを最初から計画、root登録は
      固定identifier、ツリー課題は前例なし)
- [x] 公開範囲の決定(public)、プロジェクトの位置づけの確定
      (dwg7帽子がGSI帽子を外部支援する、という整理)
- [x] 出力経路の決定(RPiでWebサーバー+ブラウザ同時稼働はしない、
      GitHub Pagesへのプッシュのみに一本化。kaga0のノウハウは転用しない)
- [x] 作業分担の確立(Claude Codeが担当する範囲/人の手を残す範囲)
- [x] `dwg7/kikimimi` リポジトリ作成(public、CC0 LICENSE済み)
- [x] `lenses/README.md`を確認し、grounding省略設定の方法を調査
      (`speechmap lens`は`locitorium`実行ファイルを無条件に要求するため、
      OpenSpeechMap自身のテストスイートが使うスタブ手法を production
      用に転用する方針を確定。`scripts/locitorium-stub.sh`)
- [x] `docs/PREREQUISITES.md`の`--source sdr`要件を確認
      (ffmpeg + rtl_fm(rtl-sdr/librtlsdr) + whisper.cppサーバー。macOSは
      「未検証」との明記あり。RPi 4B/Raspberry Pi OSでの検証はこちらが
      dwg7として初めての記録になる見込み)
- [x] dwg7内の他プロジェクトとの重複確認 —
      重複なし。関係市町村の不一致など有用な公開情報を入手し、
      気象庁一次資料で裏取り済み
- [x] `tokachi-lens`初稿の作成(`ja-radio-disaster`を土台に十勝岳へ
      絞り込み)
- [x] `tokachi-lens`初稿の人間によるレビュー(2026-09-16、一通り完了。
      ブロッカー解除)
- [x] `setup-rpi.sh`・`setup-macmini.sh`・`diagnose.sh`の初稿作成
- [x] `docs/`はGitHub Pages用に予約し、ADR等は`documents/`に置く決定
      ([ADR 0006](documents/decisions/0006-docs-reserved-for-github-pages.md))
- [x] CLAUDE.md/AGENTS.mdの役割分担を決定。CLAUDE.mdは現状維持、
      AGENTS.md(kikimimi自身の出力契約)はtokachi-lens確定後に追加する
      という二段構え([ADR 0007](documents/decisions/0007-agents-md-deferred.md))
- [ ] `AGENTS.md`(kikimimi自身の出力契約)の追加。tokachi-lensのレビュー
      が完了したので着手可能
- [x] 「合成ダッシュボード」か「個別ビュー」かを最終確定(合成ダッシュボード
      →m3xx-fleet型)。実装段階でm3xx-fleet/sas0の実コードを直接確認し、
      Display Layoutではなく単一カスタムビューで組む方針に精緻化
      ([ADR 0008](documents/decisions/0008-single-custom-view-not-display-layout.md))
- [x] Open MCTダッシュボードの試作(SVGプロット + イベントログ + LAD)。
      `openmct/`でローカル起動・ブラウザ確認まで完了(プレビュー用ダミー
      データ)。**ダッシュボードのデザインは重要なので、この時点で
      人間のレビューを挟む**(2026-09-16、ユーザーの指示。まだレビュー
      前)
- [ ] Condition Sets(しきい値の色分け)を小さく検証してから採用可否を
      決める。現状はSVG自前ロジックでの色分けを実装済み(既定の代替案)
- [ ] Notebookオブジェクトの実際の作成手順の確認(プラグインは
      インストール済みだが、実機での動作確認はまだ)
- [ ] 実データへの接続(`speechmap series`のseries.json、`selected.jsonl`を
      `openmct/data/`が読む形に整形する変換ステップ。現状はプレビュー用
      ダミーデータ`preview-fixture.json`)
- [ ] RPi 4B側のセットアップ(RTL-SDR接続、whisper.cpp導入) — 物理作業
- [ ] Mac mini側のLLMエンドポイント構築 — 物理作業
