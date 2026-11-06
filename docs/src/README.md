# rakuyomi

**rakuyomi** is a manga reader plugin for [KOReader](https://github.com/koreader/koreader).

> [!IMPORTANT]
>
> This is a maintained fork of rakuyomi, the continuation of [@hanatsumi](https://github.com/hanatsumi)'s original project that Tachibana Shin took over when she stopped using e-readers. Credit for both belongs to them.
>
> The upstream repositories were deleted in 2026, so this fork hosts the releases, the update channel and this guide.
>
> `rakuyomi` currently supports all [Aidoku](https://github.com/Aidoku) sources including sources written with legacy SDK or next SDK ([Aidoku Community Sources](https://github.com/Aidoku-Community/sources)...)
>
> It also supports extensions from **LNReader**, **Mangayomi** (JavaScript and Dart), and **Tachiyomi/Mihon (Keiyoushi)**, and plugin image DRM.

## Supported platforms

Releases are built for Kindle, Kobo, PocketBook, reMarkable, desktop Linux and Apple Silicon macOS.

### Android: not supported

Android needs the **Rakuyomi Bridge** companion app to load the Rust server through JNI, and that app went with the upstream account: nothing publishes `RakuyomiBridge.apk` anymore. The Android target is gone from CI for the same reason, so no `rakuyomi-android.zip` is released. Only the plugin zip was ever produced there, without the server it needs.

> [!TIP]
> If you want to run Rakuyomi as soon as you open KOReader, use this plugin: https://github.com/mgrimace/startrakuyomi.koplugin

Features:
- Added last read time for manga, chapter
- Improved UI now you can see exactly which source manga belongs to
- Added cancel download methods to avoid freezing
- Fixed back button not working properly
- Added processing menu in chapter list
- Added "continue read"
- Correct write processing to save RAM to avoid freezing KOReader
- Added cleaner to free up memory
- Improved SQLite query method to speed up all operations by `200 times` including: library access, search, chapter list (`x300 times`)
- Details manga
- Aidoku source new SDK (0.7) support

<em>Open source for Every One</em>

<p align="center">
    <img src="./images/demo.gif" width="60%" />
    <br/>
    <em><small><a href="https://seotch.wordpress.com/ubunchu/">"Ubunchu!"</a> by Hiroshi Seo is licensed under <a href="https://creativecommons.org/licenses/by-nc/3.0/">CC BY-NC 3.0</a>.</small></em>
</p>

## Installation & Usage

For detailed installation and usage instructions, please check out the [Installation](./user-guide/installation/README.md) and [Quickstart](./user-guide/quickstart.md) sections on our user guide.

Builds are published on this fork's [releases](https://github.com/BaconDroid/rakuyomi/releases), and the plugin's update check reads them.

## Cookie Sync Bot

Rakuyomi includes a Telegram bot for syncing Cloudflare cookies from your Android browser to your e-reader.

### Setup

1. Open Telegram and start the bot (or your self-hosted instance).
2. In KOReader, go to **Rakuyomi > Settings > Cookie Sync**
3. Tap **Pair Device** > enter the bot URL > send `/link CODE NAME` to the bot
4. Install [Get cookies.txt LOCALLY](https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) in Kiwi Browser
5. When a source returns 403, export cookies via the extension and paste the JSON array into the bot chat

The Rust backend automatically syncs cookies on 403 and retries. If the retry also fails, the bot sends a notification so you know to refresh cookies.

### Self-hosting

See [telegram-cookie-bot/README.md](https://github.com/BaconDroid/rakuyomi/blob/main/telegram-cookie-bot/README.md) for deployment instructions.

## Contributing

For information on how to contribute to rakuyomi, please check out the [Setting up the Environment](https://bacondroid.github.io/rakuyomi/contributing/setting-up-the-environment.html) section on our guide.
