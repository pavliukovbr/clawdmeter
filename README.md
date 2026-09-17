<p align="center">
  <img src="docs/widgets.gif" width="760" alt="Clawdmeter widgets in small and medium sizes">
</p>

<h1 align="center">Clawdmeter</h1>

<p align="center">
  Your Claude plan usage on the Mac desktop, with Clawd walking along the meter.<br>
  A little Clawd under your notch that works whenever Claude does, and a pocket Clawd on an old iPhone.
</p>

<p align="center">
  <a href="https://github.com/pavliukovbr/clawdmeter/releases/latest"><b>Download for Mac</b></a> · <a href="#an-old-iphone-as-a-second-screen"><b>Old iPhone app</b></a> · <a href="#windows-experimental"><b>Windows, experimental</b></a> · <a href="#ask-your-claude-to-install-it"><b>Ask your Claude to install it</b></a>
</p>

## Desktop widget

- **Session**: how much of your current 5 hour window is used and when it resets.
- **Weekly**: your weekly limit, plus model limits like Opus when your plan has them.
- **Extra usage**: spend against your monthly cap, if extra usage is turned on.
- **Today**: tokens and requests from your Claude Code sessions, with a 7 day chart.

It comes in a square and a wide size. Clawd stands on the usage bar and walks along it as your session fills up. It looks around, blinks, types faster when things get busy, sweats near a limit and naps once the limit is reached. Click Clawd for a heart and fresh numbers.

<p align="center">
  <img src="docs/moods.gif" width="640" alt="Clawd chilling, working, tired, napping and petted">
</p>

## Clawd in the notch

<p align="center">
  <img src="docs/notch.gif" width="570" alt="Clawd under the notch typing, reading, searching, building and sleeping">
</p>

Clawd hangs out right under the notch and shows what is going on:

- Types on a tiny laptop while Claude edits files or you are typing
- Reads a book while Claude reads your code, or when a PDF or ebook is in front
- Searches with a magnifying glass while Claude browses the web, or when you are in a browser
- Puts on a hard hat and hammers away while Claude runs commands
- Thinks while Claude is working out the next step, and waves when it is done
- Sleeps in a hammock when you are away or a limit is reached
- Peeks out from behind the notch every now and then

Move the pointer close and Clawd hides behind the notch so nothing underneath is blocked. It stays out of full screen apps. On Macs without a notch it hangs from the middle of the menu bar instead. You can turn it off from the menu bar.

## Clawd on your desktop

Turn on **Clawd Walks Around** and Clawd leaves the notch now and then:

- Walks out onto the menu bar next to the notch, looks around and hops down
- Lands on top of your windows, rides along when you drag them and falls when they close
- Jumps between windows and wanders toward the pointer
- Pretends to be things on your screen: a folder, a fourth window button, and every so often something in the top left corner of the menu bar
- Gets a heart when you rest the pointer on him
- Heads back into the notch when Claude gets to work, and comes out again once it is quiet

There is only ever one Clawd, so the notch stays empty while he is out. Mention the right names to Claude and you might get a surprise or two.

## Notifications

With **Notify When Claude Finishes** on, the Mac lets you know when Claude wraps up something that took more than 20 seconds, with the project name and how long it took.

## Keep Mac awake

Leaving Claude on a long task, or driving it remotely? Clawdmeter can keep the Mac from going to sleep:

- **While Claude Works** keeps it awake while Claude is busy and for ten minutes after
- **Always** keeps it awake until you turn it off
- **Keep Display On** stops the screen from sleeping too

The Mac still sleeps when the lid is closed, unless it is connected to an external display.

## An old iPhone as a second screen

Have an old iPhone in a drawer? Clawdmeter turns it into a little screen next to your computer: the big number, the bars, the countdown to the reset, and Clawd living at the bottom as a pet you can pick up, stroke and feed. When Claude stops and waits for you, the phone buzzes once and shows a big exclamation mark.

The app is for jailbroken iPhones on iOS 8 or 9, like an iPhone 4S, and installs from Cydia:

1. On the Mac, open Clawdmeter in the menu bar and turn on **Screen on an Old Phone**. A code appears.
2. On the iPhone, open Cydia, go to **Sources**, tap **Edit**, then **Add**, and type `https://pavliukovbr.github.io/clawdmeter/cydia/`. The source has no signing key, so Cydia warns about that once.
3. Open the source, pick **Clawdmeter** and tap **Install**.
4. Open the app and point the camera at the code on the Mac. That is the whole setup.

The screen stays on while the app is open, so leave the phone charging. If the camera is broken, hold a finger on the screen to type the address instead. Without Cydia, `oldphone/install.sh` copies the app over SSH, and [the old phone notes](oldphone/README.md) explain how it is built.

Any other old phone works too, without an app: open the address below the code in its browser, add it to the Home Screen, and set Auto Lock to Never. The page turns itself sideways when the phone is upright.

The phone only reads a summary from your own computer on your home network. It never signs in to Claude, the computer only answers with the key that is part of the code, and nothing is served until you turn it on.

## Windows, experimental

> [!WARNING]
> The Windows version is experimental and still unstable. Expect rough edges and the odd crash. **The Mac version is the recommended one.**

Clawdmeter also runs on Windows 10 and 11, reading the Claude Code sign in from your PC. Sign in with the Claude Code command line once, since the Claude desktop app keeps its own sign in where other apps cannot read it.

- A small panel on the desktop with your session, weekly and model limits, the same meters as the Mac widget
- An icon in the notification area: click it to show or hide the panel, right click it for the settings
- Clawd hangs from the top edge of the window in front while Claude works, with a laptop, a book, a magnifier or a hard hat depending on what Claude is doing, and lets go when it is done
- The rest of the time he walks along the top edges of your windows, rides them when you drag them and falls when they close
- He lives on the taskbar near the clock instead of a notch, and climbs back there when Claude gets to work
- He pretends to be a folder, an extra window button, or the logo on the Start button
- Keep the PC awake while Claude works, open at login, and the same alert when Claude finishes

Drag the panel anywhere, it stays where you leave it. Everything can be turned off from the menu.

## Works with every plan

Clawdmeter detects your plan and adapts on its own.

- **Free**: session limit
- **Pro**: session and weekly limits
- **Max 5× and Max 20×**: session, weekly and model limits
- **Team and Enterprise**: seat limits and extra usage spend
- **API key**: tokens today and a 7 day chart

<p align="center">
  <img src="docs/plans.png" width="760" alt="Widgets for different plans">
</p>

## Install

### On your Mac

1. Download **Clawdmeter.dmg** from the [latest release](https://github.com/pavliukovbr/clawdmeter/releases/latest).
2. Open it and drag Clawdmeter to Applications.
3. Open Clawdmeter. It is not notarized by Apple, so the first time macOS asks: go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
4. Right click the desktop, choose **Edit Widgets**, search for Clawdmeter and drag the size you like.

You need macOS 14 Sonoma or later, on Apple silicon or Intel, and Claude Code signed in on the same Mac. From then on Clawdmeter updates itself.

### On Windows, experimental

1. Download **Clawdmeter-Windows.zip** from the [latest release](https://github.com/pavliukovbr/clawdmeter/releases/latest).
2. Unzip it anywhere you like and run **Clawdmeter.exe**. Nothing to install, the app carries what it needs.
3. Windows warns about an unknown publisher the first time, since the app is not signed yet. Click **More info** and **Run anyway**.
4. Turn on **Open at login** from the icon in the notification area to have it start with the PC.

You need Windows 10 or 11 on 64 bit, and the Claude Code command line signed in on the same PC. From then on Clawdmeter updates itself. Remember the Windows version is still experimental.

### On an old iPhone

Follow [the steps above](#an-old-iphone-as-a-second-screen): add the Cydia source, install Clawdmeter, and scan the code from the Mac.

### Ask your Claude to install it

Using Claude Code? Paste this and let it do the work. It will still ask you for the few things only you can do, like clicking Open Anyway.

```text
Please install Clawdmeter for me from https://github.com/pavliukovbr/clawdmeter

Mac
1. Download Clawdmeter.dmg from the latest release, copy Clawdmeter.app into /Applications and open it.
2. If macOS blocks it, tell me to click Open Anyway in System Settings > Privacy & Security.
3. Tell me how to add the widget: right click the desktop, choose Edit Widgets and search for Clawdmeter.

Never ask for or type my passwords, and never show my Claude sign in or any token.
```

## Build it yourself

You need Xcode 26 or later. The project has no dependencies and signs itself to run locally, so no developer account is needed.

```bash
git clone https://github.com/pavliukovbr/clawdmeter.git
```

```bash
cd clawdmeter
```

```bash
xcodebuild -project Clawdmeter.xcodeproj -scheme Clawdmeter -configuration Release -derivedDataPath build
```

```bash
cp -R build/Build/Products/Release/Clawdmeter.app /Applications/
```

Or open `Clawdmeter.xcodeproj` and press Run. To make the downloadable files for a release, run `scripts/release.sh`.

For Windows you need the [.NET 9 SDK](https://dotnet.microsoft.com/download), and it builds from Windows, macOS or Linux:

```bash
dotnet publish windows/Clawdmeter/Clawdmeter.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

To make the downloadable file for a release, run `scripts/release-windows.sh`.

The project is organized in a few folders:

- `App` is the menu bar app: reading usage, the notch scene, keep awake, updates and the screen for an old phone.
- `Widget` is the Mac widget extension.
- `oldphone` is the app for jailbroken old iPhones, in Objective-C, with its Cydia packaging.
- `iPhone`, `iPhoneWidget` and `PhoneShared` hold the earlier iPhone app. It is switched off and no longer maintained.
- `Shared` has the views, models and the pairing protocol used everywhere.
- `windows` is the Windows app, written in C# with WPF and no dependencies.

## How it works

Clawdmeter runs quietly in the menu bar. Every 5 minutes, after waking from sleep, and whenever you click Clawd, it:

1. Reads the sign in Claude Code already keeps in your login keychain, or in the Windows credential manager.
2. Asks Anthropic for your current limits, the same numbers you see with `/usage`.
3. Adds up tokens from the Claude Code session logs in `~/.claude/projects`.
4. Saves a small summary for the widget and asks it to redraw.

Widgets on macOS are drawn ahead of time, so regular animations do not run in them. Clawd moves with the same clock driven rotation Apple uses for clock hands, combined into bobbing, blinking and floating z's. The notch scene uses Core Animation, so it keeps going smoothly with the app idle.

## Privacy

Clawdmeter keeps everything on your own devices.

- **Your sign in** stays in memory and is only sent to `api.anthropic.com` to ask for your limits.
- **Session logs** are read on your Mac. Only token counts, tool names, timestamps and the project folder name are looked at. Prompts are only checked for a couple of easter egg words, and nothing from them is kept.
- **Your windows** are only measured, so Clawd knows where he can stand. What is inside them is never looked at, and no screen recording permission is needed.
- **What you do** is limited to which app is in front and how long ago a key was pressed. Which keys you press is never known.
- **What is saved** is one small file in `~/Library/Application Support/Clawdmeter`, or in `%APPDATA%\Clawdmeter` on Windows, with percentages, reset times and daily totals, readable only by you.
- **The screen for an old phone** is off until you turn it on. It answers only addresses on your own network, only with the key in the address, and it sends percentages and counts, never your logs or your sign in.
- **Updates** come from the public release list of this repository on GitHub. Nothing about you or your Mac is sent.

There is no analytics, no tracking and no account.

## Good to know

- If you have not used Claude Code for a while its sign in can expire. Run any Claude Code command and the widget catches up on the next refresh.
- The usage endpoint is the one Claude Code uses internally. It is not a public API and could change.
- Widgets on a dimmed desktop keep Clawd still, since macOS does not animate them there.
- Closed the menu bar icon by accident? Open Clawdmeter again and it comes back.
- The screen for an old phone listens on port 47848. On Windows, allow it through the firewall the first time it asks.
- The Windows app is not code signed, so SmartScreen warns the first time you run it.

## License

MIT. Clawdmeter is a fan project and is not affiliated with Anthropic. Claude and Clawd belong to Anthropic.
