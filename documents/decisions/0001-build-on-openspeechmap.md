# ADR 0001: OpenSpeechMapを土台にする

- 状態: Accepted (2026-09-16)
- 文脈タグ: アーキテクチャ, 依存

## 背景

十勝岳の火山活動を、公共ラジオへの言及頻度・文脈でテレメトリしたい。
ゼロから作るか、既存の実装に乗るかの選択がある。

## 決定

[yuiseki/OpenSpeechMap](https://github.com/yuiseki/OpenSpeechMap)(MIT License)を
土台にする。

- dwg7の仲間(Yuisekiさん)自身の実装であり、外部組織への従属ではなく
  与力/個人単位の多中心的協調の自然な実践
- MITライセンスで「税金」がほぼない
- アーキテクチャ(`ffmpeg`→`whisper.cpp`→`aiq`(レンズ)→`locitorium`
  (地名grounding)→`detempus`(時系列・異常検知))が、既にほぼ今回の
  ニーズに合致している
- 「レンズ」という仕組みが、コードを書き換えずテーマを追加できる設計
  ([ADR 0002 in OpenSpeechMap](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0002-lenses-as-data.md)、
  レンズはデータであってコードではない)
- `--source sdr`(RTL-SDR直接キャプチャ)が既にサポートされている

## 実装上の要点(調査で確認したこと)

- レンズは`schema.json`(必須)・`instruction.txt`(必須)・`system.txt`(任意)・
  `gate.txt`(任意、キーワードでLLM呼び出し前にふるい落とす)の3〜4ファイルで
  完結する。Pythonコードを書く必要はない
- `lenses/ja-radio-disaster`が、公開されている実測結果(千葉豪雨・熊本地震)
  を持つ「最初にコピーすべき」レンズ(lenses/README.mdの推奨)。
  `tokachi-lens`はこれを土台に対象を絞り込む
- `speechmap lens`は`aiq extract`(LLM)→`jq select`→`locitorium resolve`
  (地名grounding)を束ねた1コマンドであり、地名groundingだけを個別に
  無効化するフラグは無い(詳細は[ADR 0002](0002-omit-nominatim-grounding.md))
- `detempus`(時系列異常検知)は`speechmap series`という別コマンドで、
  LLMを再実行せずにbucketやパラメータを変えて何度でも呼び直せる

## 検討した代替案

- **ゼロから実装**: 却下。ffmpeg/whisper.cpp/LLM/detempusの結線自体は
  「車輪の再発明」であり、OpenSpeechMapが既にこの結線を検証済みの形で
  提供している
- **他の音声監視OSSを探す**: 検討していない。dwg7の仲間の実装という
  性質そのものが、今回の判断で重視する価値(与力単位の多中心的協調)
  に直結するため

## 影響

十勝岳固有のロジックは`lenses/tokachi-lens/`の3〜4テキストファイルに
閉じ込められ、OpenSpeechMap本体を fork・改変する必要がない。
アップストリームの更新を素直に追える。
