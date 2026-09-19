#!/usr/bin/env bash
# 既にOSイメージ・user-dataを書き込み済みのSDカードへ、Wi-Fi設定
# (cloud-init network-config)だけを追加で書き込む。kaga0のscripts/configure-wifi.shを
# 土台にしたもの。
#
# 有線接続を主、Wi-Fiは保険として使う想定。network-configの書式はRaspberry Pi
# 公式記事の実例に準拠: https://www.raspberrypi.com/news/cloud-init-on-raspberry-pi-os/
#
# **`ethernets: eth0:` を明示的に書いておく**こと。netplanは「書かれていない
# 設定は無効」という仕組みのため、`wifis:`だけのnetwork-configを書くと、
# 有線LANの物理リンクは確立するのにDHCPでIPを取りに行く設定自体が存在せず、
# 有線接続(方針上の主系統)が機能しなくなる。この個体(dwg7内の複数プロジェクトで
# 共用)で rpi-geoserver0 が実機で踏んで発覚した既知の落とし穴(2026-09-13、
# cross-session共有)。kaga0が先に修正済みだったものをそのまま引き継ぐ。
#
# SSIDは電波として周囲に公開されている情報なので対話プロンプトでも問題ないが、
# パスワードはこのスクリプトの実行者が直接入力するか、.env(git管理外)に
# WIFI_SSID/WIFI_PASSWORDとして書く。いずれの場合もClaude Codeの会話には
# 一切含めない(.env.example参照)。
#
# 使い方:
#   diskutil list                          # SDカードのデバイス名を確認
#   ./scripts/configure-wifi.sh /dev/diskN

set -euo pipefail

KIKIMIMI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${KIKIMIMI_ROOT}/.env" ] && source "${KIKIMIMI_ROOT}/.env"

DEVICE="${1:?使い方: configure-wifi.sh /dev/diskN (事前に 'diskutil list' で確認)}"

diskutil mountDisk "${DEVICE}" >/dev/null 2>&1 || true
BOOT_MOUNT="/Volumes/bootfs"
for _ in 1 2 3 4 5; do
    [ -d "${BOOT_MOUNT}" ] && break
    sleep 1
done
if [ ! -d "${BOOT_MOUNT}" ]; then
    echo "エラー: ${BOOT_MOUNT} が見つかりません。'diskutil list' でデバイス名を確認してください" >&2
    exit 1
fi

if [ -n "${WIFI_SSID:-}" ]; then
    echo "Wi-Fi SSID: ${WIFI_SSID} (.envから読み込み)"
else
    read -r -p "Wi-Fi SSID: " WIFI_SSID
fi
if [ -n "${WIFI_PASSWORD:-}" ]; then
    echo "Wi-Fi パスワード: .envから読み込み"
else
    read -r -s -p "Wi-Fi パスワード: " WIFI_PASSWORD
    echo
fi

WIFI_SSID="${WIFI_SSID}" WIFI_PASSWORD="${WIFI_PASSWORD}" \
    python3 - "${BOOT_MOUNT}/network-config" <<'PYEOF'
import json, os, sys

ssid = os.environ["WIFI_SSID"]
password = os.environ["WIFI_PASSWORD"]
out_path = sys.argv[1]

doc = f"""network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      optional: true
  wifis:
    renderer: NetworkManager
    wlan0:
      dhcp4: true
      regulatory-domain: "JP"
      access-points:
        {json.dumps(ssid)}:
          password: {json.dumps(password)}
      optional: true
"""
with open(out_path, "w") as f:
    f.write(doc)
PYEOF

echo "network-config を書き込みました"
sync
diskutil eject "${DEVICE}" >/dev/null 2>&1 || true
echo "SDカードを取り出しました。RPiへ挿してください"
