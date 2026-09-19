# セッション記録:RPi実機立ち上げ(2026-09-19)

コンパクション前の引き継ぎメモ。CLAUDE.md・ADR 0009/0010が「決定事項」を
記録しているのに対し、こちらは**今どこで何をしていたか**という作業状態の
記録。次のセッションは、まずこれとCLAUDE.mdの状態一覧(6節)を読むこと。

## 進行中・未完了のアクション(最優先で確認)

**作業用Mac(Mac mini役の機体)のXcode Command Line Toolsの再インストールが
進行中(GUI操作、約55分と表示された時点でこのメモを書いている)。**
完了しているか、まず確認すること(ホスト名は`.env`参照):

```bash
ssh <作業用Mac> 'find /Library/Developer/CommandLineTools/usr/include/c++/v1 -maxdepth 1 | wc -l'
```

以前は11個(壊れた状態、`array`等の標準ヘッダが欠落)。数百〜数千に
増えていれば修復完了。完了していたら:

```bash
ssh <作業用Mac> 'eval "$(/opt/homebrew/bin/brew shellenv)" && cd ~/whisper.cpp && rm -rf build && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -j10'
```

(前回はCLT破損によりビルド失敗。SDKROOT指定でも回避できなかった——
libc++ヘッダ本体が`/Library/Developer/CommandLineTools/usr/include/c++/v1`
に無かったのが真因で、SDKバージョンの問題ではなかった。)

ビルド成功後、`~/whisper.cpp/models/download-ggml-model.sh small`で
モデルを落とし、下記の実測用サンプル(`~/kikimimi-flash-cache/test-16k.wav`
相当のものを作業用Macにも置くか、RPi実機から転送)で速度・精度を測る。
Metal backendが有効化されている(cmake configure時に
`-- Metal framework found` `-- Including METAL backend`を確認済み)ので、
RPiより大幅に速い可能性がある。

## 今日決めたこと(要点。詳細はADR参照)

1. **RPi実機のOS再構築が完了した**([ADR 0009](../documents/decisions/0009-rpi-os-trixie-cloudinit-just.md))。
   rpi-geoserver0からのバックアップをsha256で独立検証してから、
   Raspberry Pi OS Lite (64-bit) Trixie + cloud-initで書き込み。
   `rpi-imager`の`--cloudinit-userdata`系フラグがこの環境で確実に
   固まったため、最終的に`dd`直接書き込み+boot分区への手動配置に
   切り替えた。ホスト名・ユーザー・SSH鍵・Wi-Fi設定は`.env`側にのみ
   記録(個体名をリポジトリに書かない、kaga0 ADR 0006の慣習)

2. **RTL-SDR Blog V4の接続・受信確認が完了した**。`rtl_test`で認識
   (`RTLSDRBlog, Blog V4`、`Rafael Micro R828D`)。ダイポールアンテナ
   キットの大きい方の素子(23cm〜1m)を88cm程度(NHK-FM北海道85.2MHz
   の1/4波長換算)に調整、窓際へ移設してクリアな受信を確認。
   **`rtl_fm`は放送用に`-M wbfm`(広帯域+ディエンファシス)が必須**——
   `-M fm`(狭帯域)だと高域ノイズが乗る。ただしOpenSpeechMap本体の
   `record.py`は元々`-M wbfm`を正しく使っているので、これは自分の
   手動テストコマンドだけの問題だった

3. **whisper.cppモデル選定は、baseを外して`tiny` vs `small`の比較に
   絞られた**([ADR 0010](../documents/decisions/0010-whisper-model-benchmark.md))。
   RPi実機(4コア)での実測:
   - tiny: 実時間の0.38〜0.56倍(速い)。精度はそこそこ(「海語」のような
     誤りあり)
   - base: 実時間の1.22倍(遅い、不採用)
   - small: 実時間の4.77倍(著しく遅い、RPiでは非現実的)。精度は明確に
     向上(「介護の仕事は いかに面白がれるか」と文法的に正しく転記)

4. **RPiは放熱なしでは連続運用に耐えない可能性が高いことが実測で判明**。
   tinyを5回連続実行しただけで75.0℃→82.7℃まで上昇し、
   `vcgencmd get_throttled`が`0x80008`(ソフト温度制限が現在進行形で
   発動中)を示した。一方、`speechmap record`(RTL-SDR録音のみ、
   whisper.cpp無し)を3分間実行した際は69.6℃で安定——**発熱源は
   whisper.cpp推論であって、RTL-SDR録音自体ではない**ことが分かった

5. **この発熱の実測を受けて、アーキテクチャを見直した**: 文字起こし
   (whisper.cpp)をRPiから作業用Mac(Mac mini役)へ移す方向で合意。
   RPiの役割は「`speechmap record`のみ」に軽量化し、生成された
   セグメントファイル(60秒あたり約600KB、実測)を作業用Macへ転送、
   `speechmap transcribe`は作業用Mac側で実行する。理由:
   - RPiは軽量モデル(tiny)ですら放熱なしでスロットリングする
   - 作業用MacはApple M4・10コア・16GB RAM、かつwhisper.cppはMetal
     backendが使える見込みで、small(あるいはOpenSpeechMap本家推奨の
     medium)がRPiより実用速度で動く可能性が高い
   - 音声(圧縮すれば数十〜数百kbps)をLANで送ること自体は帯域的に
     全く問題にならない
   - **この移行はまだ実装(rsync同期の仕組み等)に着手していない。
     ADR化もまだ**。作業用MacのCLT修復・whisper.cppビルド成功後に本格着手

## ハマった落とし穴(次回同じ轍を踏まないように)

- **`timeout N speechmap record ...`で親プロセスを止めても、内部の
  `rtl_fm | ffmpeg`パイプラインが孤児化して残ることがある。** 残った
  プロセスがRTL-SDRデバイスを掴んだままになり、次の`speechmap record`
  試行が`capture exited (rc=1), restarting`を繰り返す(数秒おきに
  無限リトライ、正常な60秒セグメントができない)。対処:
  `ps aux | grep -E "rtl_fm|ffmpeg"`で確認し、該当PIDを`kill -9`
- **rpi-imager v1.8.5とv2.0.11.1でCLI引数が全く違う**(前者はローカル
  ファイルのみ・`--disable-eject`無し、後者はURL可・`--disable-eject`
  あり)。`brew upgrade`相当で解決
- **`rpi-imager --cli`の`--cloudinit-userdata`/`--cloudinit-networkconfig`
  フラグは、この環境(作業用Mac、v2.0.11.1)で`Unmounting drive...`のまま
  確実に固まった。** パーティション形式・事前アンマウント有無を変えても
  再現。原因不明。**回避策: `dd`で直接書き込み、cloud-initファイルは
  書き込み後にboot分区を手動マウントしてコピー**(cloud-init自体は
  使い続ける、rpi-imagerのフラグを経由しないだけ)
- **Finderで、MBR形式ディスクの1パーティションだけをイジェクトしたつもり
  が、ディスク全体が消える。** システムログで`diskarbitrationd`が
  `ejected disk`(個別パーティションでなく物理ディスク全体)を実行して
  いたことを確認。**教訓: 書き込み・録音作業中はFinderから一切操作しない**
- **非対話SSHセッションでは`.zshrc`等が読まれず、Homebrewが`command -v`
  で見つからないことがある。** 実際は`/opt/homebrew/bin/brew`に存在する
  ことが多いので、`command -v`の失敗だけで「未導入」と早合点しない
- **作業用MacのCommand Line Toolsは、`xcode-select --install`が
  「インストール済み」と答えても、実体のヘッダファイルが欠落している
  ことがある**(バージョン不整合ではなく破損)。`sudo rm -rf
  /Library/Developer/CommandLineTools && xcode-select --install`で
  完全に入れ直す必要があった

## アクセス経路のメモ(個体名は`.env`参照。ここでは一般的な経路のみ)

- このセッションの実行環境からRPi実機へは**直接SSHできない**
  (RPi実機の`authorized_keys`には作業用Macの鍵しか入れていない)。
  必ず`ssh <作業用Mac> 'ssh hfu@<RPiホスト>.local "..."'`の二段構成
- 作業ディレクトリ: RPi実機側`~/kikimimi-audio-test/`(録音・文字起こし
  テスト一式)、`~/OpenSpeechMap`・`~/whisper.cpp`(導入済みソフト)。
  作業用Mac側`~/kikimimi-flash-cache/`(SDカード書き込み・音声確認テスト
  一式)、`~/whisper.cpp`(ビルド中)
- リポジトリはこのセッションの実行環境→作業用Mac→RPi実機の順にrsyncで
  転送している(このセッションの実行環境の鍵がRPi実機に無いため、
  直接rsyncできない)

## 残っている論点・次にやること

- [ ] 作業用MacのCLT修復完了確認 → whisper.cppビルド → Metal有効時の
      speed/quality実測(small、可能ならmedium)
- [ ] RPi→作業用Macへのアーキテクチャ変更をADR化(まだ書いていない)
- [ ] 実際の同期の仕組み(rsyncをタイマーで回す?`speechmap
      --skip-newest`をslate側で使う?)の設計・実装
- [ ] 対象局・周波数の最終決定(現状85.2MHz NHK-FM北海道は暫定のまま、
      正式決定はしていない)
- [ ] 十勝岳関連の実ニュース音声での固有名詞転記精度の確認(今日の
      テストは一般的な会話音声のみ)
- [ ] AGENTS.md初稿、Condition Setsスパイク検証、ダッシュボード実データ
      変換スクリプト、GitHub Pages公開の仕組み——今日は着手していない
- [ ] git: CLAUDE.md・documents/decisions/README.mdの変更、および
      ADR 0009・0010・Justfile・4本のscripts/*.sh・.env.example・
      .gitignoreが**まだcommitされていない**(2026-09-19時点)。
      commitは毎回ユーザーの明示的な許可を得てから
