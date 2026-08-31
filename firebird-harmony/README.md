# Firebird for HarmonyOS NEXT

Native ArkTS/ArkUI and C++ port of Firebird for arm64 HarmonyOS NEXT phones.
It does not use Qt, QML, the Android SDK, JNI, or an Android compatibility
layer. The first supported calculator products are TI-Nspire CX II CAS
(`0x1C0` in Firebird's internal product representation) and CX II (`0x1D0`).

## Current validation status

- Source baseline: `b10f3b51a9ab8e27d2703444b5e6bd278d4c5e6e`.
- Host tests cover the W^X probe contract, Harmony snapshot wrapper, desktop v3
  snapshot recognition, all 70 non-empty calculator keys, and path hygiene.
- An arm64 unsigned HAP has completed resource, ArkTS, Native CMake/Ninja, strip,
  and package tasks against API 18. Its archive contains only the app resources,
  ArkTS bytecode, `libfirebird_harmony.so`, and the SDK C++ runtime; no calculator
  image, snapshot, signing file, or local release configuration is present.
- The ordinary Firebird headless target builds successfully after these core
  changes.
- A signed HAP and physical-device JIT/cold-boot run still require a supported
  DevEco Studio host, developer signing profile, connected HarmonyOS NEXT
  phone, and user-supplied ROM/flash files. They are not claimed as verified.

The source tree also supports command-line hvigor builds with version `5.18.6`
and API 18. The recorded unsigned Linux build used the official OpenHarmony API
18 base components plus a temporary, non-production resource-tool shim only as
a compile check; signing and device acceptance must still use the complete
HarmonyOS SDK installed by DevEco Studio.

Recorded tool environment for this port:

- OpenHarmony SDK `5.1.0.107`, Native API 18, arm64 OHOS clang on the source host;
- hvigor and Harmony plugin `5.18.6`;
- Windows 11 build host `10.0.26100.9168`, Node.js `24.19.0`, and official
  DevEco CLI `1.3.0-stable`;
- full DevEco Studio SDK, developer signing identity, connected-phone model,
  and phone system version: pending the account/device acceptance gates below.

## Build

1. Install the current stable DevEco Studio and its matching HarmonyOS SDK and
   Native SDK on a supported host.
2. Open this `firebird-harmony` directory as a project.
3. Let DevEco install hvigor `5.18.6` and the matching HarmonyOS 5.1.0/API 18
   SDK components requested by the project.
4. Select an arm64 HarmonyOS NEXT phone target. The entry module deliberately
   declares only `arm64-v8a`.
5. Add a developer signing configuration locally. Never commit the certificate,
   profile, keystore, passwords, or generated `build-profile.json5` signing
   stanza.
6. Build the `entry` HAP in Debug first. Use Release only after the JIT probe and
   cold boot have passed on the target device.

Run source-side checks on any recent Linux/macOS development host:

```sh
cmake -S firebird-harmony/tests -B firebird-harmony/build-host-tests -G Ninja
cmake --build firebird-harmony/build-host-tests
ctest --test-dir firebird-harmony/build-host-tests --output-on-failure
git submodule update --init --recursive
make -C headless -j4
```

## ROM and flash import

The app never embeds or references a developer's absolute file paths. Use the
left settings drawer to import:

- a complete 524,288-byte CX II boot ROM;
- a writable 138,412,032-byte CX II/CX II CAS flash image.

The picker result is copied to a temporary file in the application sandbox,
validated, and atomically moved into the stable `files/firebird/images`
directory. Only the two supported product identifiers are accepted. Replacing
either file stops the emulator and invalidates an incompatible autosave.

## JIT verification

JIT is enabled by default. Before Firebird starts, the native probe:

1. allocates one RW page;
2. writes `mov w0, #42; ret`;
3. flushes the instruction cache;
4. changes the page to RX;
5. executes it and verifies the return value;
6. unmaps the RX page.

The translator uses the same RW/RX helpers and never requests RWX. If the probe
or translator initialization fails while JIT is requested, startup fails with
an explicit error. The drawer reports both generated translation blocks and
entries into generated code; a passing probe alone is not presented as proof
that Firebird is running through JIT.

## Snapshots and lifecycle

Backgrounding pauses the emulator and atomically updates
`snapshots/autosave.snapshot`. A new process automatically loads a compatible
autosave; returning to the same process resumes the paused core. Restart always
performs a boot+flash cold start.

Harmony snapshots use the `FBHS` wrapper. It contains product and boot/flash
fingerprints plus a Firebird v3 payload, but no source paths. Named snapshots
can be saved, loaded, renamed, deleted, imported, and exported. Desktop v3
snapshots are accepted after structural validation and are rebound to the
current sandbox files; because v3 contains no trustworthy image fingerprint,
the user must select the matching boot/flash pair.

## Sideload and device checks

Install the signed HAP from DevEco or with the `hdc` shipped by the same SDK.
Capture `hilog` entries tagged `FirebirdCore` and `FirebirdRenderer`. Acceptance
requires two separate runs using CX II CAS and CX II flash images, with evidence
for cold boot, increasing JIT execution entries, correct LCD color/aspect,
touchpad click/movement, major keypad keys, a physical keyboard, rotation,
surface recreation, background/foreground, and process-kill autosave restore.

## Private Release packaging

An ignored local helper may inject boot/flash into a private Release HAP. It
must take paths from environment variables or an ignored `*.local.*` file,
stage them only in `entry/src/main/resources/rawfile/private`, remove the staged
copies after the build, and reject all snapshot inputs. Public source archives
and normal HAPs contain none of these files.

Before publishing, inspect both Git and the unpacked HAP. The repository ignore
policy covers calculator images, snapshots, signing material, local release
configuration, DevEco state, and build output.

## Known limitations

- No audio or network/link UI is provided.
- Only arm64 phones and CX II/CX II CAS are supported.
- The first renderer is a CPU-mapped RGBA8888 NativeWindow buffer with
  aspect-preserving nearest-neighbor scaling. EGL/OpenGL ES is intentionally
  deferred until device measurements justify it.
- Physical-device and signed-HAP results are device/toolchain-specific and must
  be recorded after a supported DevEco host and authorized phone are available.
