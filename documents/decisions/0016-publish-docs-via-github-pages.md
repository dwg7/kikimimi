# ADR 0016: `openmct/`を`docs/`へ移設し、GitHub Pagesで公開する

- 状態: Accepted (2026-09-20)
- 文脈タグ: 運用, リポジトリ構成, Open MCT

## 背景

[ADR 0004](0004-single-output-path-github-pages.md)・[ADR 0006](0006-docs-reserved-for-github-pages.md)で、
Open MCTダッシュボードは`stars`と同じ方式でGitHub Pagesへプッシュし、
公開ディレクトリとして`docs/`を予約する方針を既に決めていたが、実際の
公開設定はこれまで手つかずだった。lens→series→Open MCTの実データ経路が
検証できた([ADR 0015](0015-llm-endpoint-and-real-data-pipeline.md))
ことを受け、ユーザーの明示的な依頼で公開作業に着手した。

ユーザーからは「m3xx-fleetのダッシュボードのように、GitHub Pages上では
スタティックだが、私たちからプッシュする感じで」という指示があった。
m3xx-fleetの実際の設定を`gh api repos/dwg7/m3xx-fleet/pages`で確認した
ところ、別ブランチ(gh-pages)は使わず、**`main`ブランチのルートを
そのまま配信**する設定(`source: {branch: "main", path: "/"}`)だった。
ビルドの仕組み(CI等)は無く、リポジトリの中身がそのまま配信内容になる、
という単純な構成である。

## 決定

**`openmct/`を`docs/`へリネームし(`git mv`でhistory保持)、GitHub Pagesを
`main`ブランチの`/docs`から配信する設定にする。** m3xx-fleetとの違いは、
配信対象がリポジトリルートではなく`docs/`サブディレクトリである点のみ
(kikimimiのリポジトリには`documents/`・`scripts/`・`lenses/`等、公開
ページとして見せる必要のない内容が多いため。ADR 0006で先に決めていた
通り)。ビルドステップは無く、`docs/`配下のファイルがそのまま配信される。

## 実施内容

- `git mv openmct docs`
- `.claude/launch.json`・`scripts/lens-to-openmct.sh`・
  `scripts/sync-segments.sh`の`openmct/`参照をすべて`docs/`へ更新
- `CLAUDE.md`5節のリポジトリ構成図を更新
- `gh api --method POST repos/dwg7/kikimimi/pages -f source[branch]=main
  -f source[path]=/docs`でPages設定を有効化
- ローカルの10コミット分をまとめて`origin/main`へpush(この日の
  一連の作業がこれまで一度もリモートに反映されていなかったため)

## 影響

- **`docs/data/live.json`が、そのまま一般公開される。** `speechmap
  lens`が誤って機微な内容(まだ想定していないが)を含めてしまった場合、
  それは即座に世界中から見える状態になる。[CLAUDE.md](../../CLAUDE.md)4節の
  「公開する検出結果・抜粋の内容確認」という人間の確認範囲の重要性が、
  この公開設定によって一段と現実的になった
- 60秒毎に`sync-segments.sh`が`docs/data/live.json`を更新するが、
  **その更新はローカルファイルの上書きだけで、GitHub側には自動では
  反映されない。** 実際にウェブ上の表示を更新するには、別途
  `git add/commit/push`が必要——このpush作業をどう自動化するか(あるいは
  当面は手動のままにするか)は、今回のADRのスコープ外とし、次の課題として残す
- ビルドステップが無いため、`docs/index.html`はCDNからOpen MCT本体を
  読み込む前提のまま([ADR 0008](0008-single-custom-view-not-display-layout.md))。
  ビルドレスという既存方針とも整合する

## 追記: 公開URLの実機確認と、定期push化(2026-09-20)

Pages有効化後、`https://dwg7.github.io/kikimimi/`が
`https://dwg7.unopengis.org/kikimimi/`へ301リダイレクトされ、そこで
実際にダッシュボードが表示されることをブラウザで実機確認した(パスは
正しく維持されている——ブラウザのタブ一覧表示が簡略化されて見えた
だけで、実際の`window.location.href`では確認済み)。

**ユーザーの依頼を受け、`docs/data/live.json`を30分間隔で自動push
する`scripts/publish-live-data.sh`+`scripts/install-publish-timer.sh`を
追加した。** `sync-segments.sh`の60秒サイクルとは別のタイマーにした
理由は、60秒毎にpushするとcommit履歴が意味なく肥大化するため
(「概ね最新」で十分、というのがそもそもの要件)。push前に`git fetch`+
`git merge --ff-only`を挟み、他所(このセッションの実行環境等)からの
pushとの競合を検知できるようにした。

### 発見:作業用Mac側のgitメール設定が誤った形式だった

定期push設定の準備中、作業用Macのkikimimiリポジトリの`git config
user.email`が**`hfu@users.noreply.github.com`(IDプレフィックス無し)**に
なっていることに気づいた。これはユーザーのグローバル指示
(`~/.claude/CLAUDE.md`)で明示的に禁止されている形式で、過去に
別アカウント(現在のhandygeospatial)への誤帰属が実際に起きている
(2026-09-06、dwg7/m3xx-fleet)。**自動pushを設定する前に気づけたのは
幸運だった。** リポジトリローカルの設定を`18297+hfu@users.noreply.github.com`
に修正した(グローバル設定は変更していない)。

### 発見:作業用Mac側のリポジトリがoriginから11コミット遅れていた

同じ準備中、作業用Macの`~/kikimimi`が`origin/main`から11コミット遅れており、
しかも作業ツリーに残っていた「変更」は**実際には古い内容**(直前の
`docs/`リネーム編集をscpし忘れていたことが原因)だと判明した。これまで
このセッションでの反映作業は、変更したファイルを都度`scp`する方式で
行っていたが、**この方式は「1つでもscpし忘れると気づかないまま
古い状態で動き続ける」というリスクを常に抱えていた**、ということが
今回はっきりした。

**対処**: `git reset --hard origin/main`で作業用Macをoriginと完全に一致させ、
リネーム前の残骸(`openmct/`ディレクトリ)を削除した。**今後、作業用Macへの
反映は`scp`の代わりに`git fetch && git reset --hard origin/main`(または
`git pull --ff-only`)を使う方が、更新漏れを構造的に防げる。** 今回のADR
実装だけは元々`scp`で進めていたため、この教訓を活かすのは次回以降になる。

## 検討した代替案

- **gh-pagesブランチを使う**: 却下。m3xx-fleetも使っておらず、
  ブランチを分けるとpush作業が一段複雑になる。ADR 0006で決めた
  `docs/`直下運用のほうが手数が少ない
- **リポジトリルートを配信する(m3xx-fleetと完全に同じ)**: 却下。
  kikimimiのリポジトリには`documents/`・`scripts/`等、ダッシュボードとは
  無関係な内容が多く、`docs/`サブディレクトリに絞る方が適切
  (ADR 0006からの継続判断)
