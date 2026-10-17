<p align="center"><img src="Resources/icon.png" width="128" alt="Mouse Rate icon"></p>

# Mouse Rate

**See your mouse's real polling rate on a Mac.** Free and open source, by [Almost Perfect Tech](https://www.youtube.com/@AlmostPerfectReviews).

On a Mac, every polling rate website shows 60 or 120. That number is your screen's refresh rate, not your mouse. macOS receives every report your mouse sends, but it only hands the browser the newest position once per screen refresh.

Mouse Rate listens to the mouse directly, below the browser, and counts how many reports it sends each second. A 1000Hz gaming mouse shows about 1000. A Bluetooth office mouse shows about 125.

The app is the full Almost Perfect mouse test, built as a real Mac app: the same four guided steps as the website (polling rate, buttons and scroll, double-click and click speed), cheeky mode included. It ends with a report that grades your mouse from A+ to F. You can copy the results into a YouTube comment or save the report as a picture to post. Step 1 shows your real number, the back and forward side buttons work in step 2, and **Test another mouse** starts over without quitting.

## Download

1. Download **MouseRate.dmg** from the [latest release](../../releases/latest).
2. Open it and drag **Mouse Rate** into **Applications**.
3. Open Mouse Rate. The first time, macOS says it can't verify the app. That's because the app isn't signed with a paid Apple developer certificate yet. Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
4. Allow **Input Monitoring** when the app asks, then click **Reopen Mouse Rate**.
5. Move your mouse in steady circles.

Works on macOS 13 Ventura and newer, on Apple silicon and Intel Macs.

## What it does, and what it doesn't

- It counts how many reports each mouse sends per second. That's all.
- It never reads which keys you press, which buttons you click or where your cursor is.
- It saves nothing and sends nothing. There is no network code in this app, and every build checks for that automatically ([see the workflow](.github/workflows/build.yml)).
- It's a native app. There's no web page or browser engine inside it, and links to websites open in your normal browser.
- It needs Input Monitoring because macOS treats any app that listens to a mouse or keyboard directly that way. You can turn it off again in System Settings at any time.

The whole app is about 2,400 lines of Swift in [`Sources/`](Sources). The polling rate counting is in [`HIDMonitor.swift`](Sources/HIDMonitor.swift), on its own thread so the window's drawing can't slow it down.

## Build it yourself

If you'd rather not trust a download, build it from this code. You need a Mac with the Xcode Command Line Tools (`xcode-select --install`).

```
git clone https://github.com/harleymarley/mouse-rate.git
cd mouse-rate
bash scripts/build.sh
open build/MouseRate.dmg
```

Every DMG on the Releases page is built by GitHub Actions from the tagged code, in public. You can compare the SHA-256 checksum in the release with the one in the build log.

## Prefer Terminal?

The same measurement as a single Swift script lives at [mouse.almostperfecttech.com](https://mouse.almostperfecttech.com) under "Got a Mac?".

## Full mouse test

Polling rate is one of four tests on [mouse.almostperfecttech.com](https://mouse.almostperfecttech.com): polling rate, buttons and scroll, double-click and click speed.

## License

MIT. See [LICENSE](LICENSE).
