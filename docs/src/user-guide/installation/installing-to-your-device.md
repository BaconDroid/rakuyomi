# Installing to Your Device

After downloading the plugin, follow these instructions to install it on your device.

## Writing Your `settings.json`

The `settings.json` file contains basic settings that rakuyomi needs to work, including:
- **Source lists**: URLs containing information about available sources
- **Languages**: Your preferred reading languages

A recommended starter configuration is created automatically on the first plugin start, so writing this file by hand is optional. The defaults are equivalent to the snippet below — use it as a reference if you want to customise the file before that first run.

Any source that can run on [Aidoku](https://github.com/Aidoku) can also run on [rakuyomi](https://github.com/BaconDroid/rakuyomi) (except `WebView`)

```json,downloadable:settings.json
{{#include ../../../../backend/server/assets/default-settings.json}}
```

## Copying the Plugin to Your Device

1. Extract the `.zip` file containing the plugin. You should find a `rakuyomi.koplugin` folder inside.
2. Connect your e-reader to your computer.
3. Navigate to your KOReader installation folder. Common locations include:
   - **Cervantes:** `/mnt/private/koreader`
   - **Kindle:** `koreader/`
   - **Kobo:** `.adds/koreader/`
   - **PocketBook:** `applications/koreader/`

4. Locate the `plugins` folder:
![koreader folder](./images/koreader-folder.png)

5. Copy the entire `rakuyomi.koplugin` folder into the `plugins` folder:
![plugins folder](./images/plugins-folder.png)

```admonish note
Steps 6 and 7 are only needed if you customised the snippet above. Otherwise, skip ahead — rakuyomi creates the `rakuyomi` folder and a default `settings.json` automatically on first start.
```

6. Return to the KOReader folder and create a new `rakuyomi` folder:
![rakuyomi folder](./images/rakuyomi-folder.png)

7. Copy your `settings.json` file into the new `rakuyomi` folder:
![settings file](./images/settings-file.png)

## Android Devices

Not supported: the **Rakuyomi Bridge** companion app that runs the server on Android is no longer distributed, and CI does not build the Android target.

## macOS

Use the **macOS** build on Apple Silicon. KOReader runs on macOS, and the plugin talks to the bundled `server` binary like it does on Linux.

rakuyomi is now installed on your device! Ready to get started? Check out the [Quickstart Guide](../quickstart.md) to learn how to use it effectively.
