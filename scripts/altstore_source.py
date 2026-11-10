#!/usr/bin/env python3
"""AltStore のソース（altstore-source.json）を作る。

ビルドした .app の Info.plist から、バンドル ID・バージョン・権限の説明文をそのまま読み取る
（AltStore はソースに書いた内容と IPA の中身が一致しているかを確かめるため）。

使い方: altstore_source.py <Info.plist> <ipaのパス> <出力先.json> [--widgets]
環境変数: GITHUB_REPOSITORY, RELEASE_TAG（既定 latest）, GITHUB_RUN_NUMBER, GITHUB_SHA
"""
import datetime
import json
import os
import plistlib
import struct
import sys

TINT = "00E5FF"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    widgets = "--widgets" in sys.argv
    if len(args) != 3:
        print(__doc__)
        return 2
    plist_path, ipa_path, out_path = args
    with open(plist_path, "rb") as f:
        info = plistlib.load(f)

    repo = os.environ.get("GITHUB_REPOSITORY", "prak59459-create/VitureHUD")
    tag = os.environ.get("RELEASE_TAG", "latest")
    run = os.environ.get("GITHUB_RUN_NUMBER", "0")
    sha = os.environ.get("GITHUB_SHA", "")[:7]
    base = f"https://github.com/{repo}/releases/download/{tag}"
    ipa_name = os.path.basename(ipa_path)

    bundle_id = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    min_os = info.get("MinimumOSVersion", "18.0")
    size = os.path.getsize(ipa_path)
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    # AltStore は宣言と IPA の中身が一致しないとインストールを断るので、Info.plist の説明文をすべてそのまま載せる
    privacy = {k: v for k, v in sorted(info.items()) if k.endswith("UsageDescription") and isinstance(v, str)}
    # 背景モード（音声・位置・Bluetooth）は Info.plist の設定で、権限（entitlement）ではない
    entitlements: list = []

    name = "HUD Navigator"
    subtitle = "VITURE グラス向けの HUD ナビ"
    description = (
        "VITURE XR グラスに、ナビ・時計・天気・速度・物体認識・距離などを HUD として表示するアプリです。\n"
        "黒背景（グラスで透明）とカメラ背景、自由に配置できるパネル、日本語の音声操作、"
        "内蔵の物体検出（YOLOv3）と距離の推定（LiDAR／2 つのカメラ／AI）、3D スキャン、"
        "頭の動き（AirPods・Bluetooth センサー）などに対応。\n"
        "運転中は使わないでください。物体認識・危険検知は実験的な補助機能で、安全装置ではありません。"
    )
    if widgets:
        subtitle += "（ウィジェット付き）"
        description += "\n\nこの版はホーム画面・ロック画面のウィジェットとコントロールセンターのボタン付きです（AltStore の無料アカウントでは App ID を 2 つ使います）。"

    version_notes = f"ビルド #{run}（{sha}）。変更点は GitHub の Releases を参照してください。"
    # スクリーンショット：出力先にある screenshot-*.png（大きさは PNG のヘッダーから読む）
    screenshots = []
    out_dir = os.path.dirname(os.path.abspath(out_path))
    for fname in sorted(f for f in os.listdir(out_dir) if f.startswith("screenshot-") and f.endswith(".png")):
        with open(os.path.join(out_dir, fname), "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            continue
        width, height = struct.unpack(">II", head[16:24])
        screenshots.append({"imageURL": f"{base}/{fname}", "width": width, "height": height})

    app = {
        "name": name,
        "bundleIdentifier": bundle_id,
        "developerName": repo.split("/")[0],
        "subtitle": subtitle,
        "localizedDescription": description,
        "iconURL": f"{base}/icon.png",
        "tintColor": TINT,
        "category": "utilities",
        "screenshots": screenshots,
        "versions": [
            {
                "version": version,
                "buildVersion": build,
                "date": now,
                "localizedDescription": version_notes,
                "downloadURL": f"{base}/{ipa_name}",
                "size": size,
                "minOSVersion": min_os,
            }
        ],
        "appPermissions": {
            "entitlements": entitlements,
            "privacy": privacy,
        },
        # 古い AltStore 向け（1.x の形式）
        "version": version,
        "versionDate": now,
        "versionDescription": version_notes,
        "downloadURL": f"{base}/{ipa_name}",
        "size": size,
        "screenshotURLs": [s["imageURL"] for s in screenshots],
        "permissions": [],
    }

    source = {
        "name": name + ("（ウィジェット付き）" if widgets else ""),
        "identifier": "io.github.prak59459.hudnavigator.source" + (".widgets" if widgets else ""),
        "subtitle": subtitle,
        "description": description,
        "iconURL": f"{base}/icon.png",
        "website": f"https://github.com/{repo}",
        "tintColor": TINT,
        "featuredApps": [bundle_id],
        "apps": [app],
        "news": [],
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
    print(f"{out_path}: {bundle_id} {version} ({build}) {size} bytes, privacy={list(privacy)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
