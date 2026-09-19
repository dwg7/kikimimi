# kikimimi — タスクランナー
#
# just(Makeではなく)を採用した理由は kaga0 と同じ:
#   - `set dotenv-load` で .env(git管理外、RPiのホスト名等の環境固有の値。
#     .gitignore・.env.example参照)をレシピに自動で読み込める
#   - 作業のほとんどがシェルコマンドの実行(ssh/rsync/curl等)で、Makeが得意な
#     ファイル依存グラフはほぼ登場しない
# 詳細は documents/decisions/0009-rpi-os-trixie-cloudinit-just.md 参照。

set dotenv-load := true
set shell := ["bash", "-c"]

# 既定タスク: 一覧表示
default:
    @just --list

# setup: 必須ツールの確認
setup:
    #!/usr/bin/env bash
    set -e
    echo "=== kikimimi セットアップ確認 ==="
    missing=0
    for cmd in ssh curl jq; do
        command -v "$cmd" >/dev/null 2>&1 && echo "  OK $cmd" || { echo "  NG $cmd が見つかりません"; missing=1; }
    done
    for cmd in rpi-imager uv; do
        command -v "$cmd" >/dev/null 2>&1 && echo "  OK $cmd" || echo "  -- $cmd が見つかりません(任意だが推奨)"
    done
    if [ ! -f .env ]; then
        echo "  -- .env が見つかりません: cp .env.example .env で作成してください"
    else
        echo "  OK .env あり (KIKIMIMI_RPI_HOST=${KIKIMIMI_RPI_HOST:-未設定})"
    fi
    [ "$missing" -eq 0 ] || exit 1

# diagnose: 到達可能なもの(このMac、または --ssh でRPi実機)を診断
diagnose *args:
    ./scripts/diagnose.sh {{args}}

# ssh: RPi実機へログイン(.envのKIKIMIMI_RPI_HOST/KIKIMIMI_RPI_USERを使用)
ssh:
    #!/usr/bin/env bash
    set -e
    : "${KIKIMIMI_RPI_HOST:?.envにKIKIMIMI_RPI_HOSTを設定してください}"
    # mDNSは.localサフィックスが無いと解決できない(裸のホスト名では失敗する
    # ことを2026-09-19の同期テストで確認)
    ssh "${KIKIMIMI_RPI_USER:-pi}@${KIKIMIMI_RPI_HOST%.local}.local"

# backup-sdcard: 上書き前に、実機の現在の内容を丸ごとバックアップする
# (rpi-geoserver0のscripts/backup-sdcard.shを移植。2026-09-19時点で
# rpi-geoserver0側は実機未検証との申告あり、注意して使うこと)
backup-sdcard device out:
    ./scripts/backup-sdcard.sh {{device}} {{out}}

# restore-sdcard: バックアップイメージを書き戻す(環境を切り替えて戻す用)
restore-sdcard image device hostname_hint="":
    ./scripts/restore-sdcard.sh {{image}} {{device}} {{hostname_hint}}

# flash-sdcard: SDカードにOS書き込み + hostname/SSH鍵を設定(破壊的操作。
# 事前に diskutil list で確認。backup-sdcardでのバックアップも先に済ませること)
flash-sdcard device:
    ./scripts/flash-sdcard.sh {{device}}

# configure-wifi: 書き込み済みSDカードにWi-Fi設定を追加(SSID/パスワードは対話入力)
configure-wifi device:
    ./scripts/configure-wifi.sh {{device}}

# setup-macmini: Mac mini側のセットアップ(LLMエンドポイント準備 + locitorium stub)
setup-macmini:
    ./scripts/setup-macmini.sh

# sync-segments: RPiのtmpfsからセグメントをrsync pullし、新着分をtranscribe
# (Mac mini役の機体上で実行する。定期実行させる場合はcron/launchdに登録する
# 前に、まず単発で動作確認すること。 documents/decisions/0012-rsync-pull-over-tmpfs.md 参照)
sync-segments:
    ./scripts/sync-segments.sh
