# tokachi-lens

十勝岳の火山活動状況に関する報道を検出するレンズ。

2026-09-16、人間による内容レビューを一通り終えている
([CLAUDE.md](../../CLAUDE.md)4節「人の手・判断を残す範囲」)。
検出条件そのものが、公開されるsignalの品質を決めるため、実運用の
データ量が増えてきたら、下の「レビュー時に確認してほしいこと」に
沿って改めて見直すこと。

## 出自

[yuiseki/OpenSpeechMap](https://github.com/yuiseki/OpenSpeechMap)の
`lenses/ja-radio-disaster`を土台にしている。`ja-radio-disaster`は
実測結果(千葉豪雨・熊本地震での検出実績)を持つ、`lenses/README.md`が
「最初にコピーすべき」と推奨するレンズ。

`ja-radio-disaster`との違い:

- 対象を「災害全般」から「十勝岳の火山活動」一点に絞り込んだ
  (`is_disaster` → `is_tokachidake`)
- `gate.txt`を追加した。十勝岳という固有名詞を中心とした話題は、
  `ja-radio-event`(祭り・花火)と同様にlexically narrowだと判断した
  ため([lenses/README.mdの基準](https://github.com/yuiseki/OpenSpeechMap/blob/main/lenses/README.md#gatetxt-と使うべきとき)を参照)。
  `ja-radio-disaster`があえてgateを持たない理由(災害報道は語彙が
  広い)とは事情が異なる
- `alert_level_mentioned`・`mentioned_measure`を追加した。噴火警戒
  レベルの引き上げ・避難指示等、放送で明示的に述べられた事実だけを
  拾う、descriptiveなフィールド([OpenSpeechMap ADR 0006](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0006-candidates-not-verdicts.md)
  の「判定ではなく候補を、深刻度ではなく記述を」という原則を踏襲。
  推測させないために「明示的に述べられた場合のみ」と instruction.txt
  で明記している)
- 地名grounding(`--place-field topic`をlocitoriumに渡す経路)は使わない。
  `topic`は地名を保持する目的では書いているが、実際にgroundingへは
  回さない([ADR 0002](../../documents/decisions/0002-omit-nominatim-grounding.md)
  参照)。それでも地名を本文どおりに残す指示は維持している。人間が
  イベントログを読むときに有用なため

## レビュー時に確認してほしいこと(人間向け)

- `is_tokachidake`のfalse基準(観光・歴史解説の除外)が、実際の放送の
  言い回しに対して機能しているか。数十件のラベル付け結果を見てから
  判断するのが望ましい
- `gate.txt`が拾いすぎ/拾わなすぎでないか。ここに挙げた自治体名
  (上富良野町・中富良野町・南富良野町・美瑛町・新得町)は、火山防災
  協議会の構成自治体と気象庁の警報対象市町村で**顔ぶれが一致しない**
  (中富良野町/南富良野町が入れ替わる。2026-09-16、気象庁一次資料で
  裏取り済み)。したがって両方を
  gateに含めているが、この判断自体が妥当かは要確認
- `alert_level_mentioned`が本当に「明示的に述べられた場合だけ」を
  拾っており、LLMが文脈から推測して埋めていないか。運用開始後に
  サンプルを見て確認する必要がある
- `mentioned_measure`の自由記述が、`--select`でのフィルタリングに
  使えるだけの語彙的な一貫性を持つか(表記ゆれが大きいと集計しにくい)

## 使い方(参考)

```bash
speechmap lens ./transcripts --lens lenses/tokachi-lens --out ./out \
  --select '.is_tokachidake' --place-field topic
```

`--place-field topic`は指定するが、[ADR 0002](../../documents/decisions/0002-omit-nominatim-grounding.md)
のスタブにより実際のgroundingは行われず、`places.geojson`は常に空になる。
