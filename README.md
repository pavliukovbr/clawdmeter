<p align="center">
  <img src="docs/widgets.gif" width="760" alt="Clawdmeter widgets in small and medium sizes">
</p>

<h1 align="center">Clawdmeter</h1>

<p align="center">
  Your Claude plan usage right on the macOS desktop, with Clawd walking along the meter.
</p>

<p align="center">
  <img src="docs/moods.gif" width="640" alt="Clawd chilling, working, tired, napping and petted">
</p>

## What it shows

- **Session**: how much of your current 5 hour window is used and when it resets.
- **Weekly**: your weekly limit, plus model limits like Opus when your plan has them.
- **Extra usage**: spend against your monthly cap, if extra usage is turned on.
- **Today**: tokens and requests from your Claude Code sessions, with a 7 day chart.

It comes in two sizes. The square one keeps it simple, the wide one lists every limit your plan has.

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

## Meet Clawd

Clawd stands on the usage bar and walks along it as your session fills up.

- Chilling while there is plenty left
- Working up a sweat when things get busy
- Tired when you get close to a limit
- Napping once the limit is reached or nothing is going on
- Click Clawd to say hi. You get a heart and fresh numbers.

## Install

You need macOS 14 or later, Xcode 26 to build, and Claude Code signed in on the same Mac.

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

```bash
open /Applications/Clawdmeter.app
```

Then right click the desktop, choose **Edit Widgets**, search for Clawdmeter and drag the size you like.

The app signs itself to run locally, so no developer account is needed. You can also open the project in Xcode and press Run.

## How it works

Clawdmeter runs quietly in the menu bar. Every 5 minutes, after waking from sleep, and whenever you click Clawd, it:

1. Reads the sign in Claude Code already keeps in your login keychain.
2. Asks Anthropic for your current limits, the same numbers you see with `/usage`.
3. Adds up tokens from the Claude Code session logs in `~/.claude/projects`.
4. Saves a small summary for the widget and asks it to redraw.

Widgets on macOS are drawn ahead of time, so regular animations do not run in them. Clawd moves using the same clock driven rotation Apple uses for clock hands, combined into bobbing, blinking and floating z's. It keeps going smoothly without waking the app.

## Privacy

- Your sign in token stays in memory and is only sent to `api.anthropic.com`.
- Token counts are calculated locally and never leave your Mac.
- The widget can only read its summary file in `~/Library/Application Support/Clawdmeter`.

## Good to know

- If you have not used Claude Code for a while its sign in can expire. Run any Claude Code command and the widget catches up on the next refresh.
- The usage endpoint is the one Claude Code uses internally. It is not a public API and could change.
- Closed the menu bar icon by accident? Open Clawdmeter again and it comes back.
- Clawdmeter starts at login so the widget stays fresh. You can turn that off from the menu bar.

## License

MIT. Clawdmeter is a fan project and is not affiliated with Anthropic. Claude and Clawd belong to Anthropic.
