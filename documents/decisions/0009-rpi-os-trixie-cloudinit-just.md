# ADR 0009: RPi 4BはRaspberry Pi OS Lite (64-bit, Trixie) + cloud-init、タスクランナーは`just`

- 状態: Accepted (2026-09-17)
- 文脈タグ: ハードウェア, 運用

## 背景

RTL-SDRの到着(約30時間後)に先立ち、RPi 4B側のOSとセットアップの自動化方式を
決める必要があった。物理的なRPi 4B自体は、rpi-geoserver0が現在使っている実機
(Unit A、Ubuntu Server 64-bit稼働中)を、イメージをバックアップした上で一時的に
借りる想定。

## 決定

**Raspberry Pi OS Lite (64-bit, Trixie) + cloud-init**をOSとして採用する。
タスクランナーには`just`(Makeではなく)を採用する。

### OS選定の理由

kikimimiのRPiの役割はRTL-SDR録音とwhisper.cppでの文字起こしのみで、GUIは不要、
GeoServerのようなJVM/メモリ要件もない([CLAUDE.md](../../CLAUDE.md)2節「RPiの役割は
キャプチャ+文字起こしに徹する」)。rpi-geoserver0がUbuntu Server 64-bitを選んだ
理由([rpi-geoserver0 ADR 001](https://github.com/dwg7/rpi-geoserver0/blob/main/docs/decisions/001-ubuntu-server-not-rpi-os.md)、
機種の異なる2台を揃える・GeoServerのメモリ余裕確保)は、kikimimiには当てはまらない。

一方、**kaga0が既にRaspberry Pi OS Lite (64-bit, Trixie) + cloud-initを実地検証
済み**で、Legacy(Bookworm、custom.toml方式)からの乗り換えの経緯もADRとして
残っている(kaga0 [ADR 0008](https://github.com/hfu/kaga0/blob/main/docs/decisions/0008-legacy-bookworm-image.md)→
[0009](https://github.com/hfu/kaga0/blob/main/docs/decisions/0009-trixie-and-cloudinit.md))。
64-bitはwhisper.cppのARM NEON最適化に必要。cloud-init自体は業界標準の機構で、
RPi固有のcustom.tomlより仕様に確信を持って扱える、というkaga0の調査結果を
そのまま引き継ぐ。

### `just`採用の理由

kaga0が`Justfile`(Makeではなく)を採用しており、決め手は`.env`(dotenv)対応
だった(kaga0 [ADR 0007](https://github.com/hfu/kaga0/blob/main/docs/decisions/0007-secrets-policy.md))。
kikimimiでも、RPiのホスト名・Mac miniの接続先・SSH鍵ファイル名といった環境
固有の値を`.env`(git管理外)に逃がす設計が同様に適合する。作業のほとんどが
シェルコマンドの実行(ssh/rsync/curl等)で、Makeが得意とするファイル依存
グラフがほぼ登場しない、という点もkaga0と同じ。

## 協調

- **rpi-geoserver0**: 実機(Unit A)のイメージバックアップ/上書きの了承と、
  イメージ丸ごとの書き戻しで環境を切り替えられるかの確認、microSD導入の
  ノウハウ共有について連絡済み(2026-09-17)。OS自体は異なる(Ubuntu Server)
  ため、バックアップ/書き込みの手順・安全策の参考にする
- **kaga0**: `scripts/flash-sdcard.sh`・`Justfile`が同じOS狙いのため、
  ほぼそのまま参考にできる見込みで、改変の了承を相談中(2026-09-17)
- 3プロジェクトで知見を持ち寄れる場面であり、実績が積み上がれば
  cafebabeへの一般化(dwg7横断のRPiプロビジョニング手順)も検討価値がある

## 実装(2026-09-19)

RTL-SDR到着を控え、RPi実機(dwg7内の複数プロジェクトで共用されている個体。
個体固有のホスト名は本リポジトリには書かず`.env`のみに置く——kaga0 ADR 0006の
慣習を踏襲)のrpi-geoserver0からkikimimiへのハンドオーバーが動き出したため、
以下を用意した。

- `scripts/flash-sdcard.sh` — kaga0のスクリプトをそのまま移植(変数名の
  差し替えのみ)。書き込み前に`backup-sdcard.sh`でのバックアップ有無を
  確認するプロンプトを追加
- `scripts/configure-wifi.sh` — kaga0のスクリプトを移植。`ethernets: eth0:`
  を明示しないと有線接続が壊れる、という既知の落とし穴(この個体で
  rpi-geoserver0が実機で踏んだもの、2026-09-13共有)をそのまま引き継ぐ
- `scripts/backup-sdcard.sh`・`scripts/restore-sdcard.sh` — rpi-geoserver0の
  スクリプトをそのまま移植。**rpi-geoserver0側の申告時点(2026-09-17)で
  実機未検証**だったため、kikimimi側でも実機で試すまでは動作保証がない
  ものとして扱う
- `Justfile`に`flash-sdcard`・`configure-wifi`・`backup-sdcard`・
  `restore-sdcard`を実装(いずれも対話確認を挟む破壊的操作)
- `.env`(git管理外)に、個体を継続使用する前提でホスト名を設定。
  人間による確認待ち(値そのものはリポジトリに書かない。kaga0 ADR 0006の
  慣習を踏襲)

実際の実機切り替え(SDカードの抜き差し、デバイスパスの指定)は物理作業であり、
人間の確認を経てから実行する([CLAUDE.md](../../CLAUDE.md)4節)。

## 実機での書き込み(2026-09-19、作業用Mac上で実施)

rpi-geoserver0からのバックアップ完了報告(sha256付き)を、こちらでも
`shasum`で独立に再計算して一致を確認した上で、実際の書き込みに進んだ。
つまずいた点と対処を記録する(将来同じ作業をする際の参考、および
kaga0・rpi-geoserver0への知見の書き戻し候補)。

- **`rpi-imager` v1.8.5と v2.0.11.1でCLI引数の形が全く違う。**
  v1.8.5は`--cli [オプション] <ローカルのイメージファイル> <デバイス>`
  (URL直接指定不可、`--disable-eject`も無い)。v2.0.11.1はkaga0が
  文書化した形(URL直接指定可、`--disable-eject`あり)。`brew upgrade
  --cask raspberry-pi-imager`相当の更新で解決した
- **`--cloudinit-userdata`/`--cloudinit-networkconfig`フラグ(v2.0.11.1で
  追加されていた、書き込み時にcloud-init設定を同時投入できる便利機能)を
  使うと、この個体・この環境では`Unmounting drive...`の表示のまま
  確実に固まった。** パーティション形式(FDisk/GUID)、事前アンマウントの
  有無、`--debug`/`--log-file`の有無を変えても再現し、原因は特定できて
  いない。cloud-initフラグを使わない素のOS書き込みの方が(常にではないが)
  進む場合があった
- **Finderで、MBR形式ディスクの1パーティションだけをイジェクトしたつもり
  が、ディスク全体(`/dev/disk5`)がシステムから消える。** システムログ
  (`log show`)で`diskarbitrationd`が`ejected disk /dev/disk5`(個別
  パーティションではなく物理ディスク全体)を実行していたことを確認。
  カードリーダーの物理故障ではなく、この操作が原因だった。**教訓: 書き込み
  作業中はFinderから一切手を触れない**
- **最終的に、`rpi-imager`を経由せず`dd`で直接書き込む方式に切り替えて
  確実に完了した。** `xz`コマンドが無かったため、Python標準ライブラリの
  `lzma`モジュールで展開(`shasum`でも展開後の一致を確認)。
  `sudo dd if=<image> of=/dev/rdiskN bs=4m status=progress`で約16MB/s、
  3GB弱を187秒で書き込み完了。cloud-initのuser-data/network-configは、
  この後にboot分区(`/Volumes/bootfs`)を手動でマウントして直接コピーする
  方式に戻した(**cloud-init自体は使い続けている**。rpi-imagerのフラグを
  経由するか、書き込み後に直接ファイルを置くかという手段の違いのみ)
- 手動コピーの結果をターミナルで確認する際、`grep`のフィルタが不十分で
  Wi-FiのSSID(パスワードではない)が一瞬会話に露出した。実害は小さい
  (SSIDは電波として公開されている情報)が、フィルタパターンは事前に
  もっと厳密に検証すべきだった

## 検討した代替案

- **rpi-geoserver0に合わせてUbuntu Server 64-bitにする**: 却下。
  rpi-geoserver0がUbuntu Serverを選んだ理由(JVM/メモリ要件、機種混在)が
  kikimimiには当てはまらず、実績のあるkaga0の組み合わせに寄せる方が
  合理的
- **Makeを使う**: 却下。kaga0と同じ理由(dotenv対応、ファイル依存グラフが
  ほぼ不要)で`just`を選ぶ

## 影響

`scripts/setup-rpi.sh`等は`Justfile`からラップされる形になる予定。
`scripts/flash-sdcard.sh`相当のSDカード書き込みスクリプトは、kaga0・
rpi-geoserver0からの回答を踏まえて別途追加する。
