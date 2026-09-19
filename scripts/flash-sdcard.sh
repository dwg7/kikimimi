#!/usr/bin/env bash
# SDカードへ Raspberry Pi OS を書き込み、hostname・SSH公開鍵authを事前設定する。
# kaga0のscripts/flash-sdcard.sh(2026-08-29〜、Trixie+cloud-init対応)を土台に、
# kikimimi向けに変数名を差し替えたもの。ホスト名の値自体はハードコードせず、
# .envのKIKIMIMI_RPI_HOSTを使う(kaga0 ADR 0006の「個体固有のホスト名は
# リポジトリに書かない」慣習を踏襲。documents/decisions/0009参照)。
#
# OSは既定で **Raspberry Pi OS Lite (64-bit)**(Trixie, init_format=cloudinit-rpi)。
# cloud-initのuser-data形式は業界標準で、RPi固有のcustom.tomlより仕様に
# 確信を持って扱える(kaga0 ADR 0009の調査結果をそのまま引き継ぐ)。
#
# init_formatに応じてカスタマイズ方式を切り替える:
#   - cloudinit-rpi(Trixie系): boot パーティションに `user-data`(cloud-init YAML)を書く
#   - systemd(Bookworm/Legacy系): boot パーティションに `custom.toml` を書く
# (OS_IMAGE環境変数でLegacyに切り替えた場合もそのまま動くようにしてある)
#
# ⚠ 本スクリプトは指定したデバイスを破壊的に上書きする。実行前に対象デバイスを
#   必ず自分の目で確認すること(誤ってメインディスクを指定すると全データを失う)。
#   このRPi実機は複数のdwg7プロジェクトで使い回されている個体であり、上書き前に
#   scripts/backup-sdcard.shで現在の内容をバックアップしておくこと。
#
# 使い方:
#   cp .env.example .env && $EDITOR .env   # KIKIMIMI_RPI_HOST / SSH_PUBKEY_FILE を実値に
#   diskutil list                          # 対象SDカードのデバイス名を確認
#   ./scripts/flash-sdcard.sh /dev/diskN   # 確認プロンプトへ手動でyesと入力
#
# 前提: rpi-imager がインストール済み(brew install --cask raspberry-pi-imager)。
#       CLIバイナリは.appバンドル内にあるだけでPATHに無いことがある。その場合:
#       ln -sf "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" /opt/homebrew/bin/rpi-imager

set -euo pipefail

KIKIMIMI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${KIKIMIMI_ROOT}/.env" ] && source "${KIKIMIMI_ROOT}/.env"

DEVICE="${1:?使い方: flash-sdcard.sh /dev/diskN (事前に 'diskutil list' で確認)}"
HOSTNAME="${KIKIMIMI_RPI_HOST%%.local}"
OS_IMAGE="${OS_IMAGE:-Raspberry Pi OS Lite (64-bit)}"
PUBKEY_FILE="${SSH_PUBKEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
PUBKEY_FILE="${PUBKEY_FILE/#\~/${HOME}}"

: "${HOSTNAME:?KIKIMIMI_RPI_HOST が未設定。.envを用意してください(.env.example参照)}"

if ! command -v rpi-imager >/dev/null 2>&1; then
    echo "エラー: rpi-imager が見つかりません: brew install --cask raspberry-pi-imager" >&2
    echo "   (CLIが見つからない場合は上記コメントのln -sfコマンド参照)" >&2
    exit 1
fi

if [ ! -f "${PUBKEY_FILE}" ]; then
    echo "エラー: SSH公開鍵が見つかりません: ${PUBKEY_FILE}" >&2
    echo "   PUBKEY_FILE=... で別のパスを指定するか、ssh-keygen で生成してください" >&2
    exit 1
fi

echo "=== OSカタログから '${OS_IMAGE}' を解決中 ==="
OS_CATALOG_URL="https://downloads.raspberrypi.org/os_list_imagingutility_v3.json"
read -r OS_URL OS_SHA256 OS_INIT_FORMAT <<<"$(
    curl -fsSL "${OS_CATALOG_URL}" | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
def walk(items):
    for it in items:
        if it.get("name") == name:
            print(it["url"], it["extract_sha256"], it.get("init_format", "?"))
            return True
        if "subitems" in it and walk(it["subitems"]):
            return True
    return False
if not walk(data["os_list"]):
    sys.exit(1)
' "${OS_IMAGE}"
)" || { echo "エラー: OSカタログに '${OS_IMAGE}' が見つかりません" >&2; exit 1; }

echo "   -> ${OS_URL} (init_format=${OS_INIT_FORMAT})"
case "${OS_INIT_FORMAT}" in
    cloudinit-rpi|systemd) ;;
    *)
        echo "エラー: '${OS_IMAGE}' の init_format '${OS_INIT_FORMAT}' はこのスクリプトが対応していない形式です" >&2
        exit 1
        ;;
esac

echo "=== 対象デバイス確認 ==="
diskutil list "${DEVICE}"
echo
read -r -p "この実機は複数プロジェクトで共用されています。scripts/backup-sdcard.shでのバックアップは済んでいますか? (yes/no): " backed_up
if [ "${backed_up}" != "yes" ]; then
    echo "先に ./scripts/backup-sdcard.sh ${DEVICE} backups/<なにか>.img.gz を実行してください" >&2
    exit 1
fi
read -r -p "⚠ ${DEVICE} の内容は完全に消去されます。本当に書き込みますか? (yes/no): " confirm
if [ "${confirm}" != "yes" ]; then
    echo "中止しました"
    exit 1
fi

read -r -p "RPi用ユーザー名 [${KIKIMIMI_RPI_USER:-}]: " RPI_USER
RPI_USER="${RPI_USER:-${KIKIMIMI_RPI_USER:?ユーザー名が未入力かつKIKIMIMI_RPI_USER未設定です}}"
read -r -s -p "RPi用パスワード(公開鍵authが有効なため通常使わないが、コンソールログイン用に必要): " RPI_PASSWORD
echo

echo "=== OSイメージ書き込み: ${OS_IMAGE} -> ${DEVICE} ==="
# --disable-eject: 既定では書き込み+検証成功後にrpi-imagerがSDカードリーダーごと
# デバイスを切断してしまう(kaga0で実機確認済み)。user-data書き込みのため接続を維持させる。
rpi-imager --cli "${OS_URL}" "${DEVICE}" --sha256 "${OS_SHA256}" --disable-eject

BOOT_MOUNT="/Volumes/bootfs"
diskutil mountDisk "${DEVICE}" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do
    [ -d "${BOOT_MOUNT}" ] && break
    sleep 1
done
if [ ! -d "${BOOT_MOUNT}" ]; then
    echo "エラー: ${BOOT_MOUNT} が見つかりません。" >&2
    echo "   'diskutil list' で ${DEVICE} がまだ存在するか確認してください。" >&2
    echo "   存在しない場合はSDカードを一度抜き差ししてから再実行してください" >&2
    exit 1
fi

PUBKEY_CONTENT="$(cat "${PUBKEY_FILE}")"

if [ "${OS_INIT_FORMAT}" = "cloudinit-rpi" ]; then
    echo "=== cloud-init user-data を boot パーティションへ書き込み ==="
    # meta-dataはRaspberry Pi OSイメージ側に既定で同梱されており、そのままで良い。
    # 値はjson.dumps()でエスケープしてYAMLに埋め込む(パスワードに"や\が含まれても
    # 壊れないように)。
    HOSTNAME="${HOSTNAME}" RPI_USER="${RPI_USER}" RPI_PASSWORD="${RPI_PASSWORD}" PUBKEY_CONTENT="${PUBKEY_CONTENT}" \
        python3 - "${BOOT_MOUNT}/user-data" <<'PYEOF'
import json, os, sys

hostname = os.environ["HOSTNAME"]
user = os.environ["RPI_USER"]
password = os.environ["RPI_PASSWORD"]
pubkey = os.environ["PUBKEY_CONTENT"].strip()
out_path = sys.argv[1]

doc = f"""#cloud-config
hostname: {json.dumps(hostname)}
manage_etc_hosts: true

timezone: Asia/Tokyo
keyboard:
  model: pc105
  layout: jp

package_update: false
package_upgrade: false

ssh_pwauth: false

users:
  - name: {json.dumps(user)}
    groups: [adm, dialout, sudo, audio, video, plugdev, input, netdev, gpio, i2c, spi, render]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: {json.dumps(password)}
    ssh_authorized_keys:
      - {json.dumps(pubkey)}

# Raspberry Pi OSはSSHサーバーを既定で無効化していることがあり、
# users.ssh_authorized_keys の指定だけではサービスが起動しない場合がある
# (kaga0が実機で確認済み)。runcmdで明示的に有効化・起動する。
# Wi-Fiの国コード未設定はrfkillでwlanがソフトブロックされたままになり
# 一切スキャン/接続できなくなる(kaga0が実機で確認済み)。
runcmd:
  - systemctl enable --now ssh
  - raspi-config nonint do_wifi_country JP
"""
with open(out_path, "w") as f:
    f.write(doc)
PYEOF
else
    echo "=== custom.toml を boot パーティションへ書き込み(Legacy/Bookworm) ==="
    cat > "${BOOT_MOUNT}/custom.toml" <<EOF
config_version = 1

[system]
hostname = "${HOSTNAME}"

[user]
name = "${RPI_USER}"
password = "${RPI_PASSWORD}"
password_encrypted = false

[ssh]
enabled = true
password_authentication = false
authorized_keys = [ "${PUBKEY_CONTENT}" ]

[locale]
keymap = "jp"
timezone = "Asia/Tokyo"
EOF
fi

if [ -n "${WIFI_SSID:-}" ] && [ -n "${WIFI_PASSWORD:-}" ]; then
    echo "=== Wi-Fi設定(.envにWIFI_SSID/WIFI_PASSWORDあり)を続けて書き込み ==="
    "${KIKIMIMI_ROOT}/scripts/configure-wifi.sh" "${DEVICE}"
else
    echo "Wi-Fi未設定(.envにWIFI_SSID/WIFI_PASSWORDが無いためスキップ)。"
    echo "  有線接続を使うか、後で 'just configure-wifi ${DEVICE}' を実行してください"
    sync
    diskutil eject "${DEVICE}" >/dev/null 2>&1 || true
fi

echo "完了。SDカードを取り出してRPiに挿入し、電源投入後:"
echo "   ssh ${RPI_USER}@${HOSTNAME}.local"
