<p align="center">
  <img src="GatherApps/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="GatherApps icon" width="128" height="128">
</p>

<h1 align="center">GatherApps</h1>

[English](README.en.md) | [한국어](README.md) | 日本語

GatherAppsは、関連するmacOSアプリを作業単位でグループ化し、必要なときにまとめて前面に表示するSwiftUIベースのmacOSアプリです。ブラウザ、メッセンジャー、IDEなど、同じ作業で使うアプリをグループとして保存しておくと、グループをアクティブ化するだけでそれらのウインドウを前面に戻せます。

## 主な機能

- 実行中のアプリ一覧からアプリを選んでグループに追加
- アプリグループの保存と削除
- グループアイコンの自動生成
- 選択したグループのアプリウインドウをまとめてアクティブ化
- ツールバーボタンから開くフローティンググループスイッチャー
- グループ別のCommand-Tabランチャーアプリ生成
- `gatherapps://activate-group/<GROUP_UUID>` URLスキームによるグループアクティブ化

## 要件

- macOS 14.0以降
- Xcode 15以降を推奨
- アプリウインドウを安定して前面に表示するには、macOSのアクセシビリティ権限が必要になる場合があります。

## はじめに

1. Xcodeで`GatherApps.xcodeproj`を開きます。
2. `GatherApps`スキームを選択します。
3. Runを押してアプリを起動します。
4. サイドバーの`グループを作成`ボタンで新しいグループを作成します。
5. 右側の実行中アプリ一覧で`+`ボタンを押して、グループにアプリを追加します。
6. `グループをアクティブ化`を押して、グループ内のアプリウインドウを前面に表示します。

## Command-Tabランチャー

各グループは、小さなmacOS `.app`ランチャーとして生成できます。生成されたランチャーは通常のアプリと同じようにCommand-Tabスイッチャーに表示され、選択するとGatherAppsにグループのアクティブ化を依頼します。

- 生成場所: `~/Applications/GatherApps Launchers/`
- 生成方法: グループ詳細画面で`ランチャーを生成`をクリック
- 実装メモ: [docs/launcher-apps.md](docs/launcher-apps.md)

## データ保存場所

GatherAppsはグループデータと生成されたアイコンをユーザーのApplication Support領域に保存します。

- グループデータ: `~/Library/Application Support/GatherApps/groups.json`
- グループアイコン: `~/Library/Application Support/GatherApps/Icons/`
- ウインドウヘルパー診断ファイル: `~/Library/Application Support/GatherApps/window-helper-diagnostics.txt`

## プロジェクト構成

- `GatherApps/`: メインのSwiftUIアプリ
- `GatherAppsWindowHelper/`: アプリウインドウを前面に表示する補助ランタイム
- `GatherAppsLauncherRuntime/`: グループ別ランチャーアプリで使うランタイム
- `GatherAppsTests/`: ユニットテスト
- `GatherAppsUITests/`: UIテスト
- `docs/`: 追加の設計および実装ドキュメント

## テスト

XcodeのTestアクションを使うか、ターミナルで次のコマンドを実行します。

```sh
xcodebuild test -project GatherApps.xcodeproj -scheme GatherApps
```

## 注記

- 生成されたランチャーアプリは、デフォルトではローカル開発用に作成されます。配布にはコード署名とnotarization手順が必要です。
- ランチャーアプリはウインドウを直接制御しません。GatherAppsのURLスキームを呼び出し、グループのアクティブ化をメインアプリに委譲します。
