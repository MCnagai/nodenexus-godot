# スマホだけで使う NodeNexus 開発環境

目的は「スマホから Codex に変更を指示 → PR → 自動テスト・Web ビルド → 認証付きの PR プレビュー → Android Chrome でプレイ」です。ゲームは Godot 4.7.2 / GDScript、Compatibility レンダラー、シングルスレッド Web 出力を使用します。

## 初回だけ必要なアカウント設定

Cloudflare と GitHub の認証設定は、アカウント所有者がスマホのブラウザで行います。API トークンはチャットやリポジトリに貼らず、下記の GitHub Secrets に直接保存してください。

### 1. Cloudflare Pages プロジェクト

1. [Cloudflare](https://dash.cloudflare.com/) にログインし、Workers & Pages から **Pages の Direct Upload** プロジェクトを作成します。Workers のプロジェクトや Git 自動ビルドは選びません。ビルドは GitHub Actions が担当します。
2. プロジェクト名と Account ID を控えます。初回アップロードを求められた場合はゲームを含まない空の HTML を使用します。ゲームの初回アップロードは Access 設定後に Actions から行います。
3. 本番ブランチは Actions が `master` に揃えます。ダッシュボードでブランチ設定が見つからなくても手動操作は不要です。PR は `pr-1`、`pr-2` のような別ブランチへデプロイされます。

### 2. Cloudflare Access（公開する前に必要）

1. Zero Trust の初期登録を済ませ、チームドメイン `<team>.cloudflareaccess.com` を控えます。メールのワンタイム PIN など、スマホでログインできる認証方法を使用します。
2. Pages プロジェクトの **Settings → General → Enable access policy** を有効にします。
3. Access のアプリケーションを確認し、プレビュー用の **`*.<project>.pages.dev`** を保護します。パス指定を付けず、HTML、WASM、PCK、メタデータをすべて保護します。
4. **`<project>.pages.dev`** 本体も別の Access アプリケーションで保護します。ワイルドカードだけでは本体を保護しません。ダッシュボードの手順が必要なら [公式の Known issues](https://developers.cloudflare.com/pages/platform/known-issues/#enable-access-on-your-pagesdev-domain) に従い、本体用とプレビュー用の両方を残します。
5. それぞれの Allow ポリシーは **自分のメールアドレスだけ**を許可します。Everyone、Bypass、広いメールドメイン許可は使いません。追加のカスタムドメインはこの構成では使用しません。
6. シークレットタブで、本体と `https://pr-1.<project>.pages.dev/` を開き、Access のログインを求められることを確認します。ログイン画面に移動せず内容が見える場合は設定を修正してください。

Actions はアップロード前に、本体・PR 用 URL の `/`、`/index.wasm`、`/index.pck`、`/build-info.json` が指定チームの Access ログインにリダイレクトされることを確認します。404・403・200 や別チームへの転送は合格にしません。Access が有効になるまでデプロイは失敗します。

Access のリダイレクト検証は、許可メールの範囲までは検証できません。メール制限の確認と「ログインしてプレイできること」は下記の実機受け入れで確認します。

### 3. GitHub Secrets / Variables

[Repository Settings → Secrets and variables → Actions](https://github.com/MCnagai/nodenexus-godot/settings/secrets/actions) をスマホで開きます。

| 種類 | 名前 | 値 |
| --- | --- | --- |
| Repository secret | `CLOUDFLARE_API_TOKEN` | 対象アカウントだけに限定した **Account → Cloudflare Pages → Edit** トークン |
| Repository secret | `CLOUDFLARE_ACCOUNT_ID` | Pages プロジェクトの Account ID |
| Repository variable | `CLOUDFLARE_PAGES_PROJECT` | Pages プロジェクト名（URL 全体ではない） |
| Repository variable | `CLOUDFLARE_ACCESS_TEAM_DOMAIN` | `<team>.cloudflareaccess.com`（`https://` やパスは不要） |

GitHub Actions を有効にし、アクションの実行が許可されていることを確認します。Workflow のデプロイ job は GitHub の `deployments: write` を指定済みです。専用の GitHub PAT は不要です。

初回設定が終わったら Codex に「Cloudflare の初回設定完了」と伝えてください。トークンそのものは送らないでください。設定完了後に PR へ新しいコミットを push すれば自動実行されます。この PR の workflow がまだ既定ブランチにない場合は、既存 run の再実行だけでは古い workflow が使われることがあるため、新しい push を使用します。マージ後は Actions の Run workflow でも実行できます。

## 日常の操作

1. スマホから Codex にリポジトリを指定し、変更内容を指示します。
2. Codex が変更、Headless テスト、Web 出力、ブラウザテストを行い PR を作ります。
3. [GitHub Actions](https://github.com/MCnagai/nodenexus-godot/actions/workflows/web-preview.yml) の対象 run を開きます。
4. `build` が成功し `deploy` も成功したら、run の Summary にある **Stable PR/branch URL** を開きます。GitHub Deployments にもリンクが表示されます。
5. Android Chrome で Access にログインしてプレイします。PR 番号が違えば URL も異なり、同じ PR の更新は同じ URL に反映されます。古い内容が残る場合は再読み込みし、`/build-info.json` の commit を PR の最新 SHA と照合します。

PR はマージしなくてもプレイできます。フォーク元の PR はテストだけ実行し、認証情報を渡さずデプロイしません。手動で既定ブランチ以外を実行した場合は `manual-<commit>` の URL を使います。PR を閉じても過去の Cloudflare デプロイは自動削除しないため、Access は継続して有効にしてください。

## 最終受け入れテスト

受け入れ用の変更として四角形の初期色を赤にし、2 回目のタップで赤に戻るようにしています。ゲームの仕様追加はありません。

1. 対象 PR の `build` と `deploy` が成功していることを確認します。設定不足で失敗・スキップした deploy は完了に数えません。
2. Summary の PR プレビュー URL を Android Chrome で開きます。
3. Access のログイン後、四角形が **赤**であることを確認します。
4. 1 回タップすると緑・Taps: 1、2 回目で赤・Taps: 2 になることを確認します。
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

WebAssembly は Pages の 25 MiB/ファイル制限に合わせ gzip 圧縮し、`_headers` の `Content-Encoding: gzip` で配信します。圧縮済み出力は通常の `python -m http.server` で正しく配信できないため、専用の `serve-web.py` を使います。ブラウザテストはこの圧縮済みパッケージを検証します。

## 参考

- [Pages の CI Direct Upload](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/)
- [PR プレビューと Access](https://developers.cloudflare.com/pages/configuration/preview-deployments/)
- [本体の pages.dev も保護する](https://developers.cloudflare.com/pages/platform/known-issues/#enable-access-on-your-pagesdev-domain)
- [Pages のファイルサイズ制限](https://developers.cloudflare.com/pages/platform/limits/)
