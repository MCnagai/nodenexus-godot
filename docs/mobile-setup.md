# スマホだけで使う NodeNexus 開発環境

目的は「スマホから Codex に変更を指示 → PR → 自動テスト・Web ビルド → 認証付きの PR プレビュー → Android Chrome でプレイ」です。ゲームは Godot 4.7.2 / GDScript、Compatibility レンダラー、シングルスレッド Web 出力を使用します。

## 初回だけ必要な操作（Secrets 2 件）

Pages、Zero Trust 組織、メール認証、Access アプリ、本体と PR プレビューの保護設定は、GitHub Actions が API で作成・確認します。ダッシュボードで Access の設定項目を手入力する必要はありません。

ユーザーが行うのは、アカウント所有者による API トークンの発行と、GitHub Secrets への次の 2 件の保存です。トークンはチャットに貼らないでください。

### 1. Cloudflare API トークンを発行

[API トークン画面](https://dash.cloudflare.com/?to=/:account/api-tokens) から **Create Token → Custom token** を選びます。

- 名前：`nodenexus-github-actions`
- 権限（すべて Account）：
  - **Cloudflare Pages → Edit**
  - **Access: Apps and Policies → Edit**
  - **Access: Organizations, Identity Providers, and Groups → Edit**
- Account Resources：NodeNexus を置くアカウント 1 件だけ。

API ドキュメントでは Edit を Write と表記する場合があります。グローバル API キーは不要です。以前の手順で Pages Edit だけのトークンを発行した場合は、Access の 2 権限も必要です。

### 2. GitHub に Secrets を 2 件保存

[New repository secret](https://github.com/MCnagai/nodenexus-godot/settings/secrets/actions/new) を開き、次の 2 件を保存してください。

| Secret の名前 | 値 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | 上で発行した API トークン |
| `CLOUDFLARE_ACCESS_EMAIL` | ゲームへのログインを許可する、自分のメールアドレス 1 件 |

Account ID と Pages プロジェクト名 `nodenexus-dev` は `.cloudflare/project.json` に設定済みです。チームドメインは API から取得するため、入力不要です。以前に設定した `CLOUDFLARE_ACCOUNT_ID` Secret、`CLOUDFLARE_PAGES_PROJECT` Variable があればそちらを優先します。`CLOUDFLARE_ACCESS_TEAM_DOMAIN` の手入力は不要になりました。

保存後、Codex に「Secrets 2 件を保存した」と伝えてください。Codex が再実行を進めます。以後の通常の変更では、この設定操作は不要です。

### 自動セットアップで行う処理

1. Pages プロジェクトを確認し、未作成なら Direct Upload として作成。
2. 既存の Zero Trust 組織を取得し、未作成なら API で作成。既存の組織全体の設定は変更しません。
3. ワンタイム PIN のメール認証を確認・追加。
4. 許可メール 1 件だけの再利用可能な Access ポリシーを作成・確認。
5. `<project>.pages.dev` と `*.<project>.pages.dev` のアプリにそのポリシーを適用。
6. 本番ブランチを `master` に揃え、未認証の HTML/WASM/PCK/メタデータ取得が Access に転送されることを確認。
7. 確認に成功してからゲームをアップロードし、実際のデプロイ URL の保護も検証。
8. アプリと許可ポリシーのログイン期間を 7 日間に設定。この構築専用の NodeNexus 組織に他のアプリがない場合は、SSO の期間も 7 日間に設定します。通常の Chrome で Cookie を保持すれば期間内のメール認証を減らせます。端末・ブラウザが変わる場合や Cookie を削除した場合は再認証が必要です。

既に別名で設定された Access アプリ、より細かいホスト・パスの例外、追加の許可ポリシーがある場合は、自動で上書き・削除せず停止します。初回作成と繰り返し実行、誤ったメール、保護の抜け道、API が期待した制限を返さない場合をオフラインテストしています。Cloudflare 実サービスへの適用は認証後に検証します。

Cloudflare が初回の Zero Trust 登録・規約同意を要求する場合は、その本人操作だけが別途必要です。自動セットアップは有料契約や請求設定の API を呼びません。

## 日常の操作

1. スマホから Codex にリポジトリを指定し、変更内容を指示します。
2. Codex が変更、Headless テスト、Web 出力、ブラウザテストを行い PR を作ります。
3. [GitHub Actions](https://github.com/MCnagai/nodenexus-godot/actions/workflows/web-preview.yml) の対象 run を開きます。
4. `build` が成功し `deploy` も成功したら、run の Summary にある **Stable PR/branch URL** を開きます。GitHub Deployments にもリンクが表示されます。
5. Android Chrome で Access にログインしてプレイします。PR 番号が違えば URL も異なり、同じ PR の更新は同じ URL に反映されます。古い内容が残る場合は再読み込みし、`/build-info.json` の commit を PR の最新 SHA と照合します。

PR はマージしなくてもプレイできます。フォーク元の PR はテストだけ実行し、認証情報を渡さずデプロイしません。手動で既定ブランチ以外を実行した場合は `manual-<commit>` の URL を使います。PR を閉じても過去の Cloudflare デプロイは自動削除しないため、Access は継続して有効にしてください。

## 最終受け入れテスト

現在のプレビューはカメラ操作のプロトタイプです。草原風の背景、グリッド、仮ノード、ミニマップを表示します。

1. 対象 PR の `build` と `deploy` が成功していることを確認します。設定不足で失敗・スキップした deploy は完了に数えません。
2. Summary の PR プレビュー URL を Android Chrome で開きます。
3. Access のログイン後、草原風の背景・グリッド・仮ノードと右下のミニマップを確認します。
4. 二本指ドラッグで移動、ピンチでズーム、同じ場所を0.5秒長押ししてから一本指ドラッグで移動することを確認します。ミニマップの表示範囲も追従します。ノード本体は長押しせず一本指でドラッグすると移動し、ミニマップのノード位置も追従します。二本目の指を置くとノード移動を終了し、カメラ操作に切り替わります。
5. 同じ URL の `/build-info.json` の commit が対象 PR の最新コミットと一致することを確認します。
6. 別のシークレットタブで、プレビュー URL と `/index.wasm`、`/index.pck` を開きます。未ログインでゲームやファイルを取得できず、Access の認証を求められることを確認します。
7. 許可していない別メールアドレスがある場合は、ログインしても拒否されることを確認します。

Android 実機を操作できるのはユーザー側です。自動テストのモバイルエミュレーションを実機合格として扱いません。実機確認結果を Codex に伝えれば、残りの問題の修正と完了判定を進められます。

## 環境内の検証コマンド

```sh
./tools/check-web.sh
npm ci --ignore-scripts
npx playwright install chromium
npm run test:web
python3 tools/serve-web.py --port 8000
```

管理されたクラウド環境では、エディタ起動・ローカル HTTP サーバー・ブラウザ・外部通信を実行するコマンドに `network.enabled: true` が必要です。既存のプロキシと TLS 検証は維持します。プリインストールされた Chromium を使う場合は `BROWSER_EXECUTABLE=/usr/bin/chromium npm run test:web` とします。

`tools/godot.sh` は `/workspace/.environment/activate.sh` があれば有効化します。ほかの環境では Godot 4.7.2 と同じバージョンの Web テンプレートを用意します。GitHub Actions は `tools/install-godot.sh` で SHA-512 照合後に両方を用意します。

WebAssembly は Pages の 25 MiB/ファイル制限に合わせ gzip 圧縮します。`assets/` 配下の指紋付きファイルとして配信し、Chrome の `DecompressionStream` で明示的に展開します。サーバーの `Content-Encoding` 上書きには依存しません。

エンジンとローダーは内容に応じた名前で、認証済みブラウザ内だけの長期キャッシュを使用します。HTML、ゲームの PCK、コミット情報はキャッシュしないため、コード変更は反映されます。ロード中はダウンロード進捗と起動状態を表示し、認証切れ、破損ファイル、タイムアウト時は再読み込みボタンを表示します。

ブラウザテストは圧縮済みパッケージで、初回起動・2 回目のキャッシュ利用・カメラの移動／ズーム・破損 gzip・認証用 HTML がゲームファイルとして返された場合を確認します。Android 実機の確認は別途必要です。

## 参考

- [Pages の CI Direct Upload](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/)
- [PR プレビューと Access](https://developers.cloudflare.com/pages/configuration/preview-deployments/)
- [本体の pages.dev も保護する](https://developers.cloudflare.com/pages/platform/known-issues/#enable-access-on-your-pagesdev-domain)
- [Pages のファイルサイズ制限](https://developers.cloudflare.com/pages/platform/limits/)

## デバッグ戦闘

右上の `+ ALLY HP 10` と `+ ENEMY HP 8` でユニットを生成できます。味方の右ポートから敵の左ポートへドラッグすると接続し、両方のHPが毎秒1ずつ減ります。逆側からドラッグしても同じ向きに接続します。HPは小数点第一位まで表示し、0になると各最大値へ戻って継続します。空白へ離すと接続をキャンセルします。一本指でポートをドラッグすると線、本体をドラッグするとユニットが動きます。
