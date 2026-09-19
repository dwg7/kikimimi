# ADR 0011: 文字起こし(whisper.cpp)をRPiからMac mini役の機体へ移す

- 状態: Accepted (2026-09-19)
- 文脈タグ: ハードウェア, 運用
- 関連: [ADR 0003](0003-hardware-split-rpi-macmini.md)(前提の見直し)、
  [ADR 0010](0010-whisper-model-benchmark.md)(RPi実測データの元)

## 背景

[ADR 0003](0003-hardware-split-rpi-macmini.md)は「whisper.cppはRPi 4Bで
十分にこなせる(tiny/baseモデルで実時間より速い)」という、他者の実測報告に
基づく仮定で、RPiに録音・文字起こしの両方を割り当てていた。

[ADR 0010](0010-whisper-model-benchmark.md)でこの仮定をRPi実機で検証した
結果、2つの問題が見つかった。

1. **速度**: tinyのみ実時間より速い(0.38〜0.56倍)。baseは実時間より遅く
   (1.22倍)、smallは著しく遅い(4.77倍)。実用的な選択肢が事実上tiny一択
   に絞られてしまう
2. **発熱**: 放熱策(ヒートシンク・ファン)なしのRPi 4Bでは、tinyのような
   軽量モデルでも5回連続実行で75.0℃→82.7℃まで上昇し、
   `vcgencmd get_throttled`が`0x80008`(ソフト温度制限が現在進行形で
   発動中)を示した。一方`speechmap record`(RTL-SDR録音のみ)は3分間で
   69.6℃で安定——**発熱源はwhisper.cpp推論であり、録音自体ではない**

## 決定

**whisper.cppによる文字起こしをRPi 4Bから、Mac mini役の機体(以下
「作業用Mac」、個体名は`.env`のみ)へ移す。** RPi 4Bの役割は
`speechmap record`(RTL-SDR録音)のみに軽量化する。

```
RPi 4B (RTL-SDR接続)
  → speechmap record のみ(60秒セグメントのtsファイル、約600KB/60秒)
  → セグメントファイルを作業用Macへ転送
作業用Mac(Mac mini役、Apple Silicon)
  → speechmap transcribe(whisper.cpp、Metal backend)
  → speechmap lens(LLMレンズ判定)
  → speechmap series(時系列・異常検知、detempus)
  → GeoJSON/出力生成 → Open MCT
```

### 作業用MacでのMetal backend実測(2026-09-19)

ADR 0010と同一の15.3秒サンプル(`test-16k.wav`、16kHzリサンプル済み)を
使用。CLT(Xcode Command Line Tools)の破損修復後、Metal backend有効で
ビルドしたwhisper.cppで実測した(`-- Metal framework found` `--
Including METAL backend`をcmake configure時に確認済み)。

| モデル | 実行環境 | 総処理時間 | 実時間比 |
|---|---|---|---|
| tiny | RPi 4B(CPU、NEON) | 8.53秒 | 0.56倍 |
| base | RPi 4B(CPU、NEON) | 18.68秒 | 1.22倍(不採用) |
| small | RPi 4B(CPU、NEON) | 72.98秒 | 4.77倍(RPiでは非現実的) |
| small | 作業用Mac(Metal) | **0.60秒** | **約0.04倍** |
| medium | 作業用Mac(Metal) | **2.35秒** | **約0.15倍** |

RPiでsmallが4.77倍(実時間の5倍近くかかる)だったのに対し、同じsmallを
作業用MacのMetal backendで動かすと0.04倍——**100倍以上高速**になった。
mediumですら実時間の0.15倍で、連続運用に十分な余裕がある。

文字起こし品質もmediumが最も自然だった(文の区切りが適切):

> こともいっぱいあるはずなのに あるねぇ / うん ある /
> でもさ 介護の仕事はいかに面白がれるか

(smallは同じ箇所を3文に分断、「介護の仕事は」の固有名詞転記自体は
tiny/base時代の「海語」「会後」からsmall以降で正しくなっている——
ADR 0010参照)

### モデル選定

**medium を第一候補とする(暫定。最終確認は人間の判断を待つ、
ADR 0010からの運用方針を継続)。** 理由:

- 作業用Macでは速度面の制約がほぼ消える(medium でも実時間の0.15倍)ため、
  「速いが精度の粗いtiny/small」を選ぶ動機が無くなった
- OpenSpeechMap本家(`docs/PREREQUISITES.md`)がmediumを「日本語が実用に
  なる境目」としている、という既存の推奨と整合する
- 残る確認事項: 十勝岳関連の固有名詞(地名・火口名等)を含む実際のニュース
  音声での精度(今回のテストも含め、これまでのテストは全て一般的な会話
  音声のみ)

## 影響

- **同期の仕組みが新たに必要になる**(まだ未実装)。RPi側で生成される
  セグメントファイル(60秒あたり約600KB)を作業用Macへ転送する手段
  (rsyncをタイマーで回す、`speechmap`側の増分検出を使う等)を設計する
- `Justfile`・`scripts/setup-rpi.sh`・`scripts/setup-macmini.sh`は、
  「RPiはwhisper.cppを使わない」「作業用Macがwhisper.cpp一式(モデル
  含む)を持つ」という前提に合わせて見直しが必要
- RPi 4Bの発熱リスクは、録音専任化によって大きく下がる(3分間69.6℃で
  安定という実測に基づく)。ただし24時間365日の連続録音でどうなるかは
  未検証で、長時間運用での再確認は引き続き必要
- 音声(圧縮すれば数十〜数百kbps)をLANで送ること自体は帯域的に問題に
  ならない、という前提は据え置き(ADR 0003から継続)

## 今後の検討事項:ストリーミング処理

現状の`speechmap record`→`speechmap transcribe`は、60秒セグメント単位の
準リアルタイム処理であり、真の逐語ストリーミング(whisper.cppの`stream`
サンプルのような、VADトリガー式の低遅延処理)ではない。medium実測で
60秒分を10秒未満で処理できる見込みが立ったため、体感遅延は小さいが、
「セグメントの区切りで文が分断される」問題は残る。

真のストリーミング化は、OpenSpeechMapのパイプライン構造(ファイルベース、
各段階が独立して再実行可能という設計、[CLAUDE.md](../../CLAUDE.md)2節)
や、レンズ判定が文脈のまとまりを前提にしている点との整合を要する、
別の設計判断になる。今回のADRのスコープには含めず、**今後の検討事項**
として記録するに留める(2026-09-19、ユーザーからの示唆)。

## 検討した代替案

- **RPiのままsmallに上げる**: 却下。ADR 0010の実測通り、RPiでは
  smallが実時間の4.77倍と非現実的
- **RPiにヒートシンク・ファン等の放熱策を追加してtinyのまま続行**:
  却下はしていないが優先度を下げた。物理的な追加対応が必要な上、
  moving transcription offがより根本的な解決になるため、まずこちらを
  試す
- **whisper.cppをRPi・作業用Macの両方で動かし、状況に応じて切り替える**:
  却下。運用の複雑さに見合う利点が無い(作業用Mac側が速度面で
  RPiを大きく上回るため、常時作業用Mac側に寄せる方が単純)
