# ADR 0018: `ja-radio-disaster`を独立タイマーで並行稼働させ、判定パイプラインの生存確認とする

- 状態: Accepted (2026-09-20)
- 文脈タグ: レンズ, 運用, 検証

## 背景

large-v3-turboへのbackfillと`tokachi-lens --redo`の再実行([ADR
0011](0011-transcription-moves-to-macmini-role.md)追記)を経ても、
`tokachi-lens`のgate.txt(キーワード事前フィルタ)を通過するレコードは
稼働開始からずっと0件のままである。これは「実際に十勝岳関連の放送内容が
無い」という、想定通りの状態である可能性が高い(手作業でのサンプル確認
でも、台風情報・地方ニュース・音楽番組が中心で、十勝岳関連の言及は
見当たらなかった)。

しかし、0件が続く状態だけでは、**「本当に何もない」のか「LLM判定の
経路のどこかが壊れていて常に0を返しているだけ」なのかを区別できない**、
という懸念をユーザーから受けた。gate.txtが極めて狭い十勝岳関連キーワード
のみを通す設計である以上、tokachi-lens単体ではこの2つを見分けられない。

## 決定

OpenSpeechMap本体が提供する`ja-radio-disaster`レンズ
(`lenses/README.md`が「最初にコピーすべき」と推奨し、千葉豪雨・熊本地震
での検出実績を持つレンズ。[CLAUDE.md](../../CLAUDE.md)2節)を、
`tokachi-lens`とは別に、**独立したタイマー・独立した出力先で並行稼働**
させる。

- `scripts/run-disaster-lens.sh`: `speechmap lens`を`ja-radio-disaster`
  (gate.txtが無いレンズ)に対して実行し、`--select ".is_disaster"`で判定
- `scripts/install-disaster-lens-timer.sh`: launchd LaunchAgentとして
  常駐登録(既定10分間隔)

### `sync-segments.sh`の60秒cadenceには混ぜない

`ja-radio-disaster`にはgate.txtが無いため、**新規/未判定の全レコードが
無条件にLLM呼び出しの対象になる**。`tokachi-lens`のように大半がgateで
弾かれる設計とは負荷特性が全く異なり、60秒サイクルに混ぜると詰まる
リスクがある。そのため独立した、より長い間隔(既定10分)のタイマーとして
分離した。

### 出力は`docs/`の外に置く(公開経路には含めない)

`docs/`はGitHub Pagesの配信実体であり([ADR
0006](0006-docs-reserved-for-github-pages.md)、[ADR
0016](0016-publish-docs-via-github-pages.md))、そこに何を置くかは
稼働初期は人間が確認してから公開する、という標準の作業分担
([CLAUDE.md](../../CLAUDE.md)4節)がある。`ja-radio-disaster`の判定は
**まだ内容を人間が確認していない検証用シグナル**であるため、
`~/kikimimi-disaster-lens-output`(リポジトリ外、`docs/`の外)に出力し、
`publish-live-data.sh`の自動pushの対象にも含めない。ダッシュボードへの
組み込み(検証用の別パネル、または`live.json`とは別の
`live-disaster.json`)は、この検証結果を見た上で改めて判断する。

## 検討した代替案

- **`tokachi-lens`のgate.txtを緩める**: 却下。gateを緩めると
  tokachi-lens自体の検出精度・LLM呼び出しコストの前提が変わってしまい、
  「十勝岳に絞り込む」という本来の設計目的([CLAUDE.md](../../CLAUDE.md)
  2節)と衝突する。生存確認は別レンズで行う方が関心の分離として適切
- **`ja-radio-disaster`を`sync-segments.sh`の60秒cadenceに混ぜる**:
  却下。上記の負荷特性の違いにより、本筋の録音→転写→表示更新の
  サイクルを遅延・詰まらせるリスクがある
- **検証結果をすぐ`docs/data/`へ書き込む**: 却下。公開判断は人間が
  行うという標準の作業分担に反する。まずローカルな検証出力として様子を
  見る

## 影響

- Ollama(`qwen2.5:14b`)への呼び出し頻度が増える(gateなしの全件判定)。
  Mac mini役の機体のリソース負荷を見ながら間隔を調整する余地を残す
- `tokachi-lens`が「本当に0件」なのか「判定経路が壊れているだけ」なのか
  を、独立した経路で区別できるようになる
