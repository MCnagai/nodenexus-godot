# NodeNexus – Godot browser-first starter

Godot 4.7.2 / GDScript のブラウザ向けスターターです。Unity のコードは移植していません。

スマホから Codex に変更を指示し、PR ごとにビルドしたゲームを Android Chrome で確認する環境を構築しています。

**初回は API トークンと許可メールを GitHub Secrets に保存する 2 件の操作が必要です。Pages / Access の構築は Actions が自動化します。未実施のデプロイ・Android 実機確認を完了とは扱いません。**

セットアップと日常操作、受け入れテストは [スマホ向け手順](docs/mobile-setup.md) を参照してください。

## 自動化される処理

- PR 作成・更新、`master` への push で Headless テストと Web ビルド。
- Desktop / mobile エミュレーションの Chromium で赤 → 緑 → 赤の操作確認。
- Pages 用の圧縮・サイズ検査とコミット情報の付与。エンジンはブラウザにキャッシュし、ロード失敗時は再試行を表示。
- Secrets 登録後、Pages・メール認証・自分のメールだけを許可する Access を構築し、保護を確認してから `pr-<番号>` ごとの URL にデプロイ。
- 実際のデプロイ URL の認証要求を確認し、Actions Summary と GitHub Deployments に URL を表示。

認証設定不足や Access が未保護の場合は deploy job が失敗し、公開前に止まります。ログイン期間は 7 日間で、許可メールの制限は維持します。フォーク PR にはデプロイ権限を与えません。

## 環境内の操作

```sh
./tools/check-web.sh
npm ci --ignore-scripts
npx playwright install chromium
npm run test:web
python3 tools/serve-web.py --port 8000
```

管理されたクラウド環境ではネットワーク権限付きで実行してください。`tools/godot.sh` が用意済みランタイムを有効化し、Godot 4.7.2 を確認します。ほかの環境では同じエンジンと Web テンプレートを用意します。

四角形の初期色は受け入れテスト用の赤です。ブラウザテストの証跡は `build/evidence/`、配信用ファイルは `build/web/`、コミット情報は `/build-info.json` に生成されます。Android 実機での確認は別途必要です。
