# チュートリアル：1台のサーバーで複数の Basis ワールドを動かす

[English](tutorial.md)

このチュートリアルでは、小さな Linux サーバー1台で複数の Basis ワールドを動かします。
ワールドごとに名前があり、プレイヤーはその名前を入力するだけで参加できます。

```
worlds.example.com          →  ハブ    (UDP 4296)
forest.worlds.example.com   →  Forest  (UDP 4297)
city.worlds.example.com     →  City    (UDP 4298)
```

仕組みは DNS の SRV レコード（[RFC 2782](https://www.rfc-editor.org/rfc/rfc2782)）です。
ポートを付けずに名前を入力すると、Basis クライアントは `_basis._udp.<名前>` を引き、
レコードが示すホストとポートに接続します。全ワールドが1つの IP アドレスを共有し、
それぞれ別のポートで待ち受けます。

## 必要なもの

- **Linux サーバー**：Docker と compose プラグイン、それにグローバル IPv4 アドレスが必要です。
  - サーバーは軽量で、待機中のワールド1つあたり RAM 約 85 MB です。多くの事業者の最小プランで足ります。
  - イメージの初回ビルドだけ RAM 約 1.5 GB とディスク 2 GB を使います。RAM 2 GB のマシンではスワップを追加してください。
- **ドメイン**：DNS を自分で管理でき、SRV レコードに対応している必要があります。
- **ワールドの `.BEE` バンドル**：HTTPS のホストか CDN に置いたもの。ビルド時のパスワードも必要です。
- **SRV と「サーバーに保存」に対応した Basis クライアント**：上流の `experimental-branch-major-changes`
  のコミット `41789fb7d`（2026-10-27）以降でビルドしたもの。
  - それより古いクライアントも接続はできますが、行き先は `<名前>:4296`、つまり常にハブです。
  - Web ビルドは DNS 問い合わせ自体ができません。
- **自分のプレイヤー DID**（`did:key:z6Mk...`）：管理者になるために使います。

## 1. サーバーの準備

ファイアウォールで各ワールドの UDP ポートを開けます。最初のワールドが 4296 で、以降1ワールドごとに1つ増えます。
Web プレイヤーを受け入れる場合（9章）は、TCP の 80・443・4296 と各ワールドのポートも開けます。
それ以外は公開しないでください。SSH はできれば VPN（Tailscale など）経由にします。
Docker Engine と compose プラグインをインストールします。

## 2. リポジトリの取得とワールドの記述

GitHub で **Use this template** を押して自分用のコピー（履歴なし）を作り、サーバーにクローンします。

```sh
git clone https://github.com/<you>/BasisMultiWorld.git basis-worlds
cd basis-worlds
cp .env.example .env && chmod 600 .env
```

`worlds.conf` を編集します。1行に1ワールドで、スラッグ・UDP ポート・バンドル・表示名の順に書きます。
**1行目がハブです。ハブのポートは 4296 のままにしてください。**

```
hub      4296   Hub.BEE       My Hub
forest   4297   Forest.BEE    Forest Walk
city     4298   City.BEE      City at Night
```

`.env` では少なくとも次の4つを設定します。

| 設定 | 内容 |
| --- | --- |
| `CDN_BASE` | バンドルを置いた URL。末尾のスラッシュは付けません（`https://cdn.example.com/basis`） |
| `UNLOCK_PASSWORD` | バンドルのビルド時に設定したパスワード |
| `BASIS_FIRST_ADMIN` | 自分の DID。複数ある場合はカンマ区切り |
| `DNS_ZONE` | ハブの名前（`worlds.example.com`）。他のワールドはその前に `<スラッグ>.` を付けた名前になります |

`BASIS_REF` は、サーバーのビルドに使う上流 Basis のコミットを固定する設定です。このリポジトリに
Basis 本体は含まれていません。`fetch-basis.sh` が、そのコミットの
[BasisVR/Basis](https://github.com/BasisVR/Basis) から `Basis Server/` フォルダだけ（約 11 MB）を取得します。

## 3. ビルドと起動

```sh
./fetch-basis.sh          # 上流のサーバーソース → ./basis
./configure.sh            # worlds.conf と .env → docker-compose.yml と worlds/<スラッグ>/…/world.xml
sudo docker compose up -d --build
sudo docker compose ps    # 全ワールドが "healthy" になれば OK
curl -fsS localhost:10666/health   # 1つ目のワールド。以降は 10667, 10668, …
```

`configure.sh` はまず `worlds.conf` を検査します。スラッグやポートの重複、不正なポート番号、
パスワードの未設定などがあると、何も変更せずに終了します。`worlds.conf` や `.env` を編集したら
再実行し、`sudo docker compose up -d` を実行してください。

## 4. DNS

```sh
./dns-records.sh 203.0.113.10 > records.txt   # サーバーの IPv4
```

レコード一式を BIND 形式で出力します。内容は、各名前の A レコード、ワイルドカード、ワールドごとの
SRV レコードです。ファイルをインポートするか、手で入力してください。

- **Cloudflare の場合**：DNS → Records → Import and Export → Import で取り込みます。
  「Proxy imported DNS records」は**オフ**のままにしてください。プロキシはゲームの UDP 通信を通せないため、
  全レコードを「DNS only」にする必要があります。
- **ワールドごとに A レコードもある理由**：ある名前の下に SRV レコードがあると、その名前には
  ワイルドカードが効かなくなります。専用の A レコードがないと、SRV の解決に失敗したクライアントは
  ハブに落ちるのではなく、アドレスを何も得られません。

確認方法：

```sh
dig +short SRV _basis._udp.forest.worlds.example.com   # → 0 0 4297 vm1.worlds.example.com.
dig +short A forest.worlds.example.com                 # → サーバーの IPv4
```

## 5. 参加する

クライアントで、ポートを付けずに `worlds.example.com` に接続します。管理者としてハブに入れれば成功です。
続けて `forest.worlds.example.com` も試してみてください。

## 6. ワールド間のポータル

ポータルは、別のワールドへ移動させる扉を持った小さなプロップです。
[`examples/ServerPortal.cs`](../examples/ServerPortal.cs) はプロップ内で動作確認済みの版です。
クリエイターガイドの `ServerPortal` の例は、プロップ内では動きません。扉の `host` に行き先ワールドの名前を入れ、
`port` は **4296** のままにします。こうするとクライアントが SRV を引き、行き先を DNS が決めます。

プロップの作り方：

1. **ルートオブジェクト**：`BasisProp`、**`CilboxPropBasis`（ルート自身に付けます）**、`ServerPortal` を付けます。
2. **扉**：子オブジェクトに `Interactable` レイヤーのコライダーと `BasisInteractableButton` を付けます。
   `InteractRange` は 3 程度にします。既定の 1 m はデスクトップでは短すぎます。
   扉と2つの TextMeshPro ラベルをインスペクターで割り当てます。
3. **ビルド**：**保存済み**のシーンからビルドします。全プレイヤーに扉が見えるよう、SDK にある全プラットフォームを含めます。
   Unity のログに各プラットフォームで「Cilbox scripts to do: 1」と出ることを確認してください。
   0 だと扉は動きません。
4. **公開**：`.BEE` をワールドと同じ場所にアップロードします。

サーバーへの設置：

1. **管理者として、ライブラリからプロップを Networked でスポーンします。**
2. **好きな位置に動かします。**
3. **Instantiated タブで「サーバーに保存（Save to server）」を押します。** サーバーがそのワールドの
   `initialresources/` にプロップを書き込み、再起動のたびに読み込み直します。

「Load on Boot」は使わないでください。これは自分のクライアントにだけ読み込む設定です。

プレイヤーが扉を押すと行き先のアドレスが表示され、確認すると移動します。SRV で別のポートに移動する場合でも、
確認画面には常に `<名前>:4296` と表示されます。これは想定どおりの動作です。Basis 標準の「リフト」ポータルも使えますが、
サーバーを再起動すると消えます。

## 7. 任意：管理ダッシュボード

ワールドごとに [MarusansiBasisDashboard](https://github.com/nodokaha/MarusansiBasisDashboard) を付けられます。
プレイヤー一覧の表示、ワールドの読み込み、アナウンスなどができます。有効にする手順：

1. **ワールドごとに API キーを設定します。** `.env` の `HUB_API_KEY=` などに、`openssl rand -hex 32` で
   生成した値を入れます。
2. **API を有効にしてサーバーを作り直します：** `./configure.sh && sudo docker compose up -d`。ワールドは再起動します。
3. **ダッシュボードを起動します：** `sudo docker compose --profile dashboard up -d --build`。

ダッシュボードはサーバー自身の `127.0.0.1:4000` 以降で、ワールドごとに1つずつ待ち受けます。
**管理ページにはログインがなく、どのサイトからのリクエストも受け付けます。これらのポートは絶対に公開しないでください。**
SSH トンネルか、Tailscale の `tailscale serve --bg --http=4000 http://127.0.0.1:4000` と
自分の端末に限定したアクセスルールで使ってください。

## 8. 運用

- **管理者の追加**：`BASIS_FIRST_ADMIN` が効くのは各ワールドの初回起動時だけです。後から追加するには：
  ```sh
  sudo docker compose stop && sudo ./add-admin.sh did:key:z6Mk... && sudo docker compose up -d
  ```
- **デフォルトライブラリ**：管理者がクライアントの「Admin > Default library」で追加したアバターやプロップは、
  そのワールドにいる間、訪問者全員のライブラリに表示されます（誰かのアバターが勝手に変わることはありません）。
  リストはワールドごとに `worlds/<スラッグ>/defaultlibrary/` の XML ファイルとして保存されます。
  全ワールドで同じリストにするには、ファイルをコピーしてから `sudo docker compose restart` を実行します。
  リストは起動時に読み込まれます。
- **バックアップ**：残すべきものは `.env` と、`worlds/*/config`（管理者・権限）、`worlds/*/storage`
  （プレイヤーのセーブ）、`worlds/*/initialresources`（サーバーに保存したプロップ）、`worlds/*/defaultlibrary` です。
  合計で数 KB 程度です。毎日バックアップを取り（restic が便利です）、サーバーを作り直しても消えないディスクに置いてください。
- **Basis の更新**：`.env` の `BASIS_REF` を変えて、`./fetch-basis.sh && sudo docker compose up -d --build` を実行します。
- **ワールドのバンドルの差し替え**：CDN も Basis クライアントも URL 単位でキャッシュします。
  クライアントは同じ名前のファイルの更新を確認しません。新しいファイル名でアップロードして `worlds.conf` を更新するか、
  CDN をパージしたうえで、既にそのワールドを読み込んだプレイヤーには古い版が残る場合があると理解しておいてください。

## 9. 任意：Web プレイヤー

Basis はブラウザでも動きます。ブラウザは UDP を送れないため、Web プレイヤーは WebSocket で接続します。
また、`https://` のページから開けるのは `wss://` だけです。この機能を有効にすると、次のようになります。

- **各ワールドが WebSocket でも待ち受けます。**
  [Basis-TCP-Transport-Package](https://github.com/dooly123/Basis-TCP-Transport-Package) を使い、
  `fetch-basis.sh` がこれをサーバーに組み込みます。待ち受けはコンテナ内部だけです。
- **外部との窓口は [Caddy](https://caddyserver.com) のコンテナです。** ワールド名ごとに Let's Encrypt
  の証明書を取得し、名前ごとにそのワールドへ振り分けます。ブラウザは SRV レコードを引けないため、
  Web クライアントはポートなしの名前を `wss://<名前>:4296/` に変換します。Caddy は 4296（と 443）で受けて
  名前で振り分けるので、ワールド名の入力もポータルも、ブラウザでデスクトップと同じように動きます。
  他のワールドのポートでは、UDP と同様にポート番号で振り分けます。
- **ネイティブクライアントも使えます。** UDP が遮断されたネットワークでは
  `wss://forest.worlds.example.com` で接続できます。

有効にする手順：

1. **`.env` で** `WEB_PLAYERS=yes` にします（`DNS_ZONE` には実際のドメインが必要です）。
   必要なら `WEB_CLIENT_URL` に Web クライアントの置き場所（手順4）を設定します。
   すると、ブラウザで `https://forest.worlds.example.com` を開いたとき、そのワールドに参加する設定でクライアントに転送されます。
2. **ファイアウォールで TCP** の 80・443・4296 と各ワールドのポートを開けます。80 は証明書の取得用です。
3. **反映します。** `./configure.sh && sudo docker compose down && sudo docker compose up -d`
   を実行します。`down` は最初の1回だけ必要です。compose のネットワークが固定サブネットになり、
   ワールドはそこからの情報だけを信用してプレイヤーの実アドレスを知るためです。証明書は
   `sudo docker compose logs caddy | grep "certificate obtained"` で確認できます。
   Caddy は起動時にしか設定ファイルを読まないので、あとで `configure.sh` を再実行したときは
   `sudo docker compose exec -w /etc/caddy caddy caddy reload` で読み直させてください。
4. **Web クライアントを置きます。** 上流の CI がコミットごとにビルドしています。自分の `BASIS_REF` に対応する
   `compilation.yml` の実行から `Basis-Client-WebGL` アーティファクトをダウンロードします。例：
   `gh run download <run-id> -R BasisVR/Basis -n Basis-Client-WebGL -D web`。
   アーティファクトは約 90 日で消えるので、コピーを残してください。
   - **CDN か静的ホスティングに、専用の `https://` の名前で置きます**（例：`play.worlds.example.com`）。
     Basis のサーバーには置かないでください。約 120 MB あり、ゲームサーバーから遠いプレイヤーへの帯域は細いことがあります。
   - **置き場所は1つのアドレスに固定します。** ブラウザはクライアントの設定やキャッシュをサイトごとに保存します。
   - **必要なヘッダー**：`*.unityweb` に `Content-Encoding: br`、`*.wasm.unityweb` に
     `Content-Type: application/wasm`。Bunny では、条件を「Request URL」にしたエッジルールで設定します。
     「File Extension」条件は最後の拡張子しか見ないため使えません。スレッドを使わないビルドなので COOP/COEP は不要です。
5. **バンドルの置き場所で CORS を許可します。** Web クライアントは別サイトから `.BEE` を取得します。
   - `Access-Control-Allow-Origin: *`（公開バンドルならこれで問題ありません）
   - `Access-Control-Allow-Headers: Range, If-None-Match, If-Modified-Since`
   - `Access-Control-Expose-Headers: Content-Range, ETag`

   ブラウザの `OPTIONS` プリフライトには 405 ではなく 2xx を返す必要があります。設定は必ず1か所だけにしてください。
   `Access-Control-Allow-Origin` が2つ付くと（CDN と、その手前のプロキシの両方で付けた場合など）CORS が失敗します。
6. **ワールドとプロップを Web 向けにもビルドします。** SDK で WebGL プラットフォームを含めてください。
   WebGL のセクションがないバンドルはブラウザで読み込めません。

Web クライアントには WebGPU と 64 ビット WebAssembly が必要です。つまりデスクトップ版の Chrome、Edge、Firefox です（Firefox は Windows で確認済み）。
プレイヤーは `https://play.worlds.example.com/?connection=forest.worlds.example.com` で参加します。
`WEB_CLIENT_URL` を設定していれば、ワールド名を開くだけで参加できます。

## トラブルシューティング

| 症状 | 原因 |
| --- | --- |
| どのワールド名やポータルを使ってもハブに入る | クライアントが 2026-10-27 より古く SRV を引いていないか、SRV レコードがありません。`dig` で確認してください。 |
| ワールドが healthy にならない | `sudo docker compose logs --tail=50 <スラッグ>` を確認してください。 |
| `curl localhost:1066x/health` が 404 か無応答 | `configure.sh` を再実行してください。生成されるファイルは `HealthCheckHost: "*"` を設定します。既定の `localhost` はコンテナ内では使えません。 |
| 「サーバーに保存」が失敗する | `initialresources` が書き込み可能である必要があります。上流付属の compose は読み取り専用でマウントしています。 |
| まったく接続できない | ファイアウォールで UDP ポートが開いていないか、Cloudflare のプロキシがオンになっています。 |
| Web：初回だけ「Set a username before joining a server」と出る | 上流の既知の問題です。`?connection=` 付きのリンクは、プレイヤー名が決まる前に接続しようとします。一度 Servers メニューで名前を設定して参加すれば、ブラウザが覚えます。リンクに `&name=Guest` を付けても回避できます。 |
| Web：「Your browser does not support WebAssembly Memory64」と出る | 上流の Web ビルドは 64 ビットの WebAssembly です。iPhone・iPad のブラウザはすべて WebKit で動いていて、これを実行できません。Safari も同様です。デスクトップ版の Chrome、Edge、Firefox を使ってください。 |
| Web：接続はできるがワールドが表示されない | バンドルに WebGL のセクションがないか、置き場所が CORS を許可していません（ブラウザのコンソールを確認してください）。 |
| Caddy が証明書を取得できない | TCP 80 か 443 が閉じているか、その名前がこのサーバーを指していません。証明書が取得されるのは `worlds.conf` にある名前だけです。 |

## SRV 解決の動き

- **いつ引くか**：ポートなし、または既定の 4296 を指定した場合、クライアントは `_basis._udp.<名前>` を引き、
  レコードのターゲットとポートに接続します。それ以外のポートを指定すると、SRV を引かずに直接接続します。
- **レコードが複数ある場合**：priority の小さいものが優先されます。同じ priority のレコードは weight の比率で
  プレイヤーを分け合い、最大3つのターゲットまで試します。
- **レコードがない場合**：`<名前>:4296` に接続します。ワイルドカードの A レコードがあれば、
  未知の名前や解決に失敗した名前はハブに着きます。
- **キャッシュ**：結果はレコードの TTL（最大5分）の間キャッシュされます。
- **Web クライアント**：ブラウザは DNS パケットを送れないため、問い合わせは何も表示されずに失敗し、
  `<名前>:4296` に接続します。Web プレイヤーを有効にしている場合は、Caddy の名前による振り分けが SRV の代わりになります。

## クレジット

- [Basis](https://github.com/BasisVR/Basis)（BasisVR、MIT）。このリポジトリはそのサーバーをビルドするだけです。
- [MarusansiBasisDashboard](https://github.com/nodokaha/MarusansiBasisDashboard)（nodokaha）。
- [Basis-TCP-Transport-Package](https://github.com/dooly123/Basis-TCP-Transport-Package)（dooly123）。WebSocket トランスポート。
- [Caddy](https://caddyserver.com)。Web プレイヤー向けの TLS。
- [basispm-build-awesome](https://github.com/nodokaha/basispm-build-awesome)（nodokaha）。上流から直接サーバーを
  ビルドするという発想をここから得ました。
- プロップ用ポータルスクリプトの動作確認は Splat プロジェクトの Basis ツールで行いました。
