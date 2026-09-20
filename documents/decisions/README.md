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
| [0009](0009-rpi-os-trixie-cloudinit-just.md) | RPi 4BはRaspberry Pi OS Lite (64-bit, Trixie) + cloud-init、タスクランナーは`just` | Accepted (2026-09-17) |
| [0010](0010-whisper-model-benchmark.md) | whisper.cppモデル選定の実測(tiny/base) | 実測完了、選定は人間の判断待ち (2026-09-19) |
| [0011](0011-transcription-moves-to-macmini-role.md) | 文字起こし(whisper.cpp)をRPiからMac mini役の機体へ移す | Accepted (2026-09-19) |
| [0012](0012-rsync-pull-over-tmpfs.md) | RPi→作業用Macのセグメント転送は、tmpfs録音 + rsync pullとする | Accepted (2026-09-19) |
| [0013](0013-stay-on-fm-am-switch-rejected.md) | 対象波はNHK-FM北海道を継続、AMへの切り替えは見送り | Accepted (2026-09-20) |
| [0014](0014-oneseg-tuner-sufficient-for-kikimimi.md) | kikimimiの用途では「ワンセグチューナーで十分」——yuisekiさんの助言と実測の整合 | Accepted (2026-09-20) |
| [0015](0015-llm-endpoint-and-real-data-pipeline.md) | LLMエンドポイント構築と、lens→series→Open MCTの実データ経路の検証 | Accepted (2026-09-20) |
| [0016](0016-publish-docs-via-github-pages.md) | `openmct/`を`docs/`へ移設し、GitHub Pagesで公開する | Accepted (2026-09-20) |
| [0017](0017-health-panel.md) | ダッシュボードに、RPi・Mac miniの健全性パネルを追加する | Accepted (2026-09-20) |

## 土台にしているOpenSpeechMap自身のADR

kikimimiの決定の多くは、OpenSpeechMap側の設計判断を前提にしている。
特に以下は読んでおく価値がある(いずれも
[yuiseki/OpenSpeechMap/docs/ADR/](https://github.com/yuiseki/OpenSpeechMap/tree/main/docs/ADR)):

- [0002-lenses-as-data](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0002-lenses-as-data.md) — レンズはコードではなくデータである
- [0005-place-identity-by-osm-id](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0005-place-identity-by-osm-id.md) — kikimimiは地名grounding自体を省略しているが([0002](0002-omit-nominatim-grounding.md))、なぜ元々grounding が必要とされたかの背景
- [0006-candidates-not-verdicts](https://github.com/yuiseki/OpenSpeechMap/blob/main/docs/ADR/0006-candidates-not-verdicts.md) — 判定ではなく候補を返す、という原則。kikimimiの「verified intelligenceではない」という留保([README.md](../../README.md))と同じ思想
