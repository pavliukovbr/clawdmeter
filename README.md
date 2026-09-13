<p align="center">
  <img src="docs/widgets.gif" width="760" alt="Clawdmeter widgets in small and medium sizes">
</p>

<h1 align="center">Clawdmeter</h1>

<p align="center">
  Your Claude plan usage on the macOS desktop, with Clawd walking along the meter.<br>
  And a little Clawd under your notch that works whenever Claude does.
</p>

<p align="center">
  <a href="https://github.com/pavliukovbr/clawdmeter/releases/latest"><b>Download for Mac</b></a>
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

## Keep Mac awake

Leaving Claude on a long task, or driving it remotely? Clawdmeter can keep the Mac from going to sleep:

- **While Claude Works** keeps it awake while Claude is busy and for ten minutes after
- **Always** keeps it awake until you turn it off
- **Keep Display On** stops the screen from sleeping too

The Mac still sleeps when the lid is closed, unless it is connected to an external display.

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

Clawdmeter runs on macOS 14 Sonoma or later, on Apple silicon and Intel Macs. You need Claude Code signed in on the same Mac.

1. Download **Clawdmeter.dmg** from the [latest release](https://github.com/pavliukovbr/clawdmeter/releases/latest) and drag Clawdmeter to Applications.
2. Open it. Clawdmeter is not notarized by Apple, so macOS asks first. Go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
3. Right click the desktop, choose **Edit Widgets**, search for Clawdmeter and drag the size you like.

Clawdmeter updates itself from this repository, so this is only needed once.

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

The project is split in three folders:

- `App` is the menu bar app: reading usage, the notch scene, keep awake and updates.
- `Widget` is the WidgetKit extension.
- `Shared` has the views and models both of them use.

## How it works

Clawdmeter runs quietly in the menu bar. Every 5 minutes, after waking from sleep, and whenever you click Clawd, it:

1. Reads the sign in Claude Code already keeps in your login keychain.
2. Asks Anthropic for your current limits, the same numbers you see with `/usage`.
3. Adds up tokens from the Claude Code session logs in `~/.claude/projects`.
4. Saves a small summary for the widget and asks it to redraw.

Widgets on macOS are drawn ahead of time, so regular animations do not run in them. Clawd moves with the same clock driven rotation Apple uses for clock hands, combined into bobbing, blinking and floating z's. The notch scene uses Core Animation, so it keeps going smoothly with the app idle.

## Privacy

Clawdmeter keeps everything on your Mac.

- **Your sign in** stays in memory and is only sent to `api.anthropic.com` to ask for your limits.
- **Session logs** are read on your Mac. Only token counts, tool names and timestamps are looked at, never your prompts or code.
- **What you do** is limited to which app is in front and how long ago a key was pressed. Which keys you press is never known.
- **What is saved** is one small file in `~/Library/Application Support/Clawdmeter` with percentages, reset times and daily totals, readable only by you.
- **Updates** come from the public release list of this repository on GitHub. Nothing about you or your Mac is sent.

There is no analytics, no tracking and no account.

## Good to know

- If you have not used Claude Code for a while its sign in can expire. Run any Claude Code command and the widget catches up on the next refresh.
- The usage endpoint is the one Claude Code uses internally. It is not a public API and could change.
- Widgets on a dimmed desktop keep Clawd still, since macOS does not animate them there.
- Closed the menu bar icon by accident? Open Clawdmeter again and it comes back.

## License

MIT. Clawdmeter is a fan project and is not affiliated with Anthropic. Claude and Clawd belong to Anthropic.
