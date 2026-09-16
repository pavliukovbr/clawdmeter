# Clawdmeter for an old iPhone

Give a retired iPhone a second job: stand it on your desk and it becomes a little usage
dashboard with Clawd living on it. Big percentage, which limit it is, how long until it
resets, the session bar, a second bar when your plan has one, and the day total. Clawd
walks along the bottom of the screen, carries a laptop while Claude types, a book while
it reads, a magnifier while it searches, a hard hat while it builds, and curls up with
a few Zs when nothing is happening. When Claude asks you something, the phone buzzes
once and puts a big amber exclamation mark on the screen.

This is a real native app, Objective C and UIKit, built for armv7 and iOS 9. It runs on
an iPhone 4S, a 4, a 3GS and anything newer that is still on iOS 9. Clawd is drawn from
coloured squares, so there is not a single image in the bundle.

<p align="center">
  <img src="../docs/notch.gif" width="480" alt="Clawd typing, reading, searching, building and sleeping">
</p>

## What you need

**On the phone**

- A jailbreak (iOS 9 has several, pick the one for your build).
- OpenSSH and uikittools from Cydia, so the Mac can copy the app over and refresh the
  Home Screen.
- The phone and the PC on the same network.

**On the Mac**

- Xcode command line tools, for `clang` and `otool`.
- `ldid`, from `brew install ldid`, for the ad hoc signature a jailbroken phone expects.
- `git` and `python3`, which macOS already has.

**On the PC**

- The Clawdmeter Windows app running, with its usage endpoint switched on. That is what
  serves `http://<pc>:47848/usage?k=<key>`. There is no login on the phone, the key in
  the address is the whole story, so keep this on your own network.

## The two commands

```sh
./build.sh
./install.sh root@192.168.1.31 192.168.1.20:47848 yourkey
```

The first one fetches the iOS 9.3 SDK into `build/` the first time it runs, patches the
stub libraries, compiles, draws the icons, signs the binary and lays out
`build/Clawdmeter.app`. It then prints proof: the architecture, the minimum iOS version,
a check that every symbol it imports exists in the 9.3 SDK, and the bundle size.
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
