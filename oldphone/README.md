# Clawdmeter for an old iPhone

Give a retired iPhone a second job: stand it on your desk and it becomes a little usage
dashboard with Clawd living on it. Big percentage, which limit it is, how long until it
resets, the session bar, a second bar when your plan has one, and the day total. Clawd
walks along the bottom of the screen, carries a laptop while Claude types, a book while
it reads, a magnifier while it searches, a hard hat while it builds, and curls up with
a few Zs when nothing is happening. When Claude asks you something, the phone buzzes
once and puts a big amber exclamation mark on the screen.

This is a real native app, Objective C and UIKit, built for armv7 with a deployment
target of iOS 8.0. It runs on an iPhone 4S, a 4, a 3GS and anything newer still stuck on
iOS 8 or 9. Clawd is drawn from coloured squares, so there is not a single image in the
bundle.

<p align="center">
  <img src="../docs/notch.gif" width="480" alt="Clawd typing, reading, searching, building and sleeping">
</p>

## What you need

**On the phone**

- A jailbreak (iOS 8 and 9 both have several, pick the one for your build).
- Cydia, which every jailbreak installs. That is enough on its own, see below. For the
  SSH way instead you need OpenSSH and uikittools from Cydia.
- The phone and the PC on the same network.

**On the Mac**

- Xcode command line tools, for `clang` and `otool`.
- `ldid`, from `brew install ldid`, for the ad hoc signature a jailbroken phone expects.
- `git` and `python3`, which macOS already has.

**On the PC**

- The Clawdmeter Windows app running, with its usage endpoint switched on. That is what
  serves `http://<pc>:47848/usage?k=<key>`. There is no login on the phone, the key in
  the address is the whole story, so keep this on your own network.

## From Cydia

The easy way, and the only one that needs nothing but the phone:

1. In Cydia open **Sources**, tap **Edit**, then **Add**.
2. Type `https://pavliukovbr.github.io/clawdmeter/cydia/` and tap **Add Source**. Cydia
   warns once that the source is not signed, which it is not. Carry on.
3. Open the source, pick **Clawdmeter** and tap **Install**. uikittools comes with it.
4. Open the app, hold a finger on the screen and type the address of the PC and the key.

To build that repository yourself, from this folder:

```sh
./package.sh
./repo.sh
```

`package.sh` builds the app if it is not there yet and wraps it in
`build/Clawdmeter_<version>_iphoneos-arm.deb`, with the bundle at
`/Applications/Clawdmeter.app`, owned by root, a postinst that runs `uicache` and a prerm
that takes the app and what you typed on the phone back off. There is no dpkg on macOS,
so it puts the archive together itself with `ar` and `tar`. The version sits on one line
at the top of the script, bump it there and nowhere else.

`repo.sh` runs `package.sh`, copies the result into `../docs/cydia/debs` and writes the
`Packages`, `Packages.gz`, `Release` and `index.html` that make a Cydia source out of a
folder. GitHub Pages serves `docs/`, so committing that folder is the whole deployment.
Nothing is signed, which is why Cydia asks.

## The two commands

Without Cydia, or to push a build straight to a phone you already have on SSH:

```sh
./build.sh
./install.sh root@192.168.1.31 192.168.1.20:47848 yourkey
```

The first one fetches the iOS 9.3 SDK into `build/` the first time it runs, patches the
stub libraries, compiles, draws the icons, signs the binary and lays out
`build/Clawdmeter.app`. Compiling asks for iOS 8.0, so clang refuses anything the 9.3
headers mark as newer, and the build fails rather than shipping a call the phone does not
have. It then prints proof: the architecture, the minimum iOS version, the entry point,
a check that every symbol it imports exists in the SDK, and the bundle size.
`./build.sh clean` throws the whole folder away, SDK included.

The second one copies the bundle to `/Applications` on the phone, fixes the owner and
the permissions, writes the settings file with your PC address and key, and runs
`uicache` so the icon shows up. Address, PC and key can also come from the `PHONE`, `PC`
and `KEY` environment variables. Nothing personal is stored in either script.

If the icon does not appear, `ssh root@yourphone killall -9 SpringBoard`.

## On the phone

Open Clawdmeter and turn the phone sideways. It works upright too, the layout just
stacks instead.

- **Drag Clawd** to pick him up. He follows your finger with his legs wiggling and
  squashes a little when he lands.
- **Stroke him** back and forth and he shows a heart.
- **Double tap the ground** to drop a snack. He walks over and eats it.
- **Tap him** for a startle.
- **Hold a finger** anywhere for a second to type a different PC address or key. What
  you type there wins over whatever the install script wrote, so a reinstall does not
  undo it.

Every one of those gives one short buzz, never a string of them.

Clawd keeps hunger, cheer and energy between 0 and 100. They drift down over hours of
real time, including while the app is closed, and feeding, petting and napping bring
them back up. Nothing bad ever happens if you forget about him for a week. He gets
sleepy, that is all.

The screen stays awake while the app is open, so this only really makes sense with the
phone plugged in.

## Notes

- The app talks plain http to your PC, which iOS 9 blocks by default, so the bundle
  carries an App Transport Security exception. It is in `Resources/Info.plist` with a
  comment saying why.
- It asks the PC for numbers about every four seconds off the main thread and keeps the
  last good answer. When the PC goes quiet it says so in a corner and dims the numbers
  instead of throwing them away.
- The Xcode that ships today cannot build for iOS 9 on its own, which is why `build.sh`
  fetches the old SDK from the theos mirror.
- On armv7 the processor switches between ARM and Thumb code as it jumps, and the linker
  that ships today gets that switch wrong, so a Thumb build dies on launch. The app is
  compiled as ARM only, and `build.sh` refuses to finish if any Thumb code slips in.
- App Transport Security only exists from iOS 9, so the exception in the bundle is dead
  weight on an iOS 8 phone and plain http works there either way.
- `Tools/shots.sh` draws every screen to a PNG at 480 by 320 points, on the Mac, for
  checking the layout without a phone in hand. It builds the same sources for Mac
  Catalyst and is never part of the phone bundle: `build.sh` compiles `Clawdmeter/*.m`
  and nothing else.
