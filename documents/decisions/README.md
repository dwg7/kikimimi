# Architecture Decision Records

なぜkikimimiがこの形をしているか、何を退けたか。

| # | 決定 | 状態 |
|---|---|---|
| [0001](0001-build-on-openspeechmap.md) | OpenSpeechMapを土台にする | Accepted (2026-09-16) |
| [0002](0002-omit-nominatim-grounding.md) | 地名grounding(locitorium/Nominatim)を省略する | Accepted (2026-09-16) |
| [0003](0003-hardware-split-rpi-macmini.md) | RPi 4BとMac miniで役割を分ける | Accepted (2026-09-16) |
| [0004](0004-single-output-path-github-pages.md) | 出力経路をGitHub Pagesへの一本化に限定する | Accepted (2026-09-16) |
| [0005](0005-open-mct-composite-dashboard.md) | Open MCTは合成ダッシュボード(m3xx-fleet型)を軸にする | Accepted (2026-09-16) |
| [0006](0006-docs-reserved-for-github-pages.md) | `docs/`はGitHub Pages用に予約し、ADR等は`documents/`に置く | Accepted (2026-09-16) |
| [0007](0007-agents-md-deferred.md) | AGENTS.mdはtokachi-lens確定後に追加する | Accepted (2026-09-16) |
| [0008](0008-single-custom-view-not-display-layout.md) | 合成ダッシュボードはDisplay Layoutではなく単一のカスタムビューで実装する | Accepted (2026-09-16) |

## 土台にしているOpenSpeechMap自身のADR

kikimimiの決定の多くは、OpenSpeechMap側の設計判断を前提にしている。
特に以下は読んでおく価値がある(いずれも
[yuiseki/OpenSpeechMap/docs/ADR/](https://github.com/yuiseki/OpenSpeechMap/tree/main/docs/ADR)):

- [0002-lenses-as-data](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0002-lenses-as-data.md) — レンズはコードではなくデータである
- [0005-place-identity-by-osm-id](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0005-place-identity-by-osm-id.md) — kikimimiは地名grounding自体を省略しているが([0002](0002-omit-nominatim-grounding.md))、なぜ元々grounding が必要とされたかの背景
- [0006-candidates-not-verdicts](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0006-candidates-not-verdicts.md) — 判定ではなく候補を返す、という原則。kikimimiの「verified intelligenceではない」という留保([README.md](../../README.md))と同じ思想
