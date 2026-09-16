# ADR 0003: RPi 4BとMac miniで役割を分ける

- 状態: Accepted (2026-09-16)
- 文脈タグ: ハードウェア, 運用

## 背景

RTL-SDRでの録音・文字起こし・レンズ判定(LLM)・時系列異常検知という
一連の処理を、どのハードウェアにどう配置するかを決める必要がある。
既にRTL-SDR Blog V4 R828Dは購入済みで、RPi 4Bへの接続を前提とする。

## 決定

台数を増やして並列化するのではなく、**役割ごとに専任機を分ける**。

```
RPi 4B (RTL-SDR接続)
  → whisper.cpp で文字起こし(tiny/baseモデル)
  → テキストを Mac mini の LLM エンドポイントに送信
Mac mini
  → LLM(レンズ判定): 十勝岳関連か、緊急度、文脈を分類
  → series(時系列・異常検知、detempus)
  → GeoJSON/出力生成 → Open MCT
```

- whisper.cppはRPi 4BのARM NEON最適化で、tiny/baseモデルなら実時間より
  速く動作するという実測報告がある
- LLMエンドポイント(レンズ判定に使う`aiq extract`の呼び出し先)は
  RPi単体では非現実的(小型量子化モデルでも遅い)。Mac miniの
  Apple Silicon(統合メモリ)の方がローカルLLM推論に適する
- `speechmap transcribe`と`speechmap lens`はOpenSpeechMap上で別コマンド
  なので、この分担はアーキテクチャの制約とも整合する
  ([ADR 0001](0001-build-on-openspeechmap.md))

## 影響

- RPi 4Bとwhisper.cppの文字起こし精度・速度の実測は、dwg7としてまだ
  誰も記録していない領域(cafebabeに横断実績なし、2026-09-16確認)。
  運用が進んだらcafebabeに書き戻す
- ネットワーク越しにテキスト(文字起こし結果)を送るだけなので、
  RPi・Mac miniの間の帯域要求は小さい。音声そのものを送る構成より
  堅牢
- `docs/PREREQUISITES.md`のmacOS向け記述は「未検証」と明記されており、
  `--source sdr`関連(rtl_fmのgain値など)はMac mini側では使わない
  (RPi側専用)ため影響は無い

## 検討した代替案

- **RPi単体で完結させる**: 却下。LLM推論がRPi単体では非現実的に遅い
- **Mac miniにRTL-SDRを直接繋ぐ**: 却下。捕獲は「専任機」の対象外に
  したいという判断([CLAUDE.md](../../CLAUDE.md)3節、RPiの役割を
  キャプチャ+文字起こしに限定する方針)と矛盾する
- **クラウドLLMエンドポイントを使う**: 却下(今回は)。
  `docs/PREREQUISITES.md`が示す通り、OpenSpeechMapの設計そのものが
  「材料は公開放送だが、結論はマシンの外に出さなくてよい」という
  ローカル完結を前提にしており、この前提を崩さない
