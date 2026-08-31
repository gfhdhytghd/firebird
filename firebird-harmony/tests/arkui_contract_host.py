#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
keypad = (ROOT / "firebird-harmony/entry/src/main/ets/components/CalculatorKeypad.ets").read_text()
physical = (ROOT / "firebird-harmony/entry/src/main/ets/bridge/PhysicalKeyMap.ets").read_text()
file_store = (ROOT / "firebird-harmony/entry/src/main/ets/bridge/FileStore.ets").read_text()
index_page = (ROOT / "firebird-harmony/entry/src/main/ets/pages/Index.ets").read_text()
entry_ability = (ROOT / "firebird-harmony/entry/src/main/ets/entryability/EntryAbility.ets").read_text()
native_types = (ROOT / "firebird-harmony/entry/src/main/cpp/types/libfirebird_harmony/Index.d.ts").read_text()
ids = {int(value) for value in re.findall(r"(?:id|keyId|leftId|rightId):\s*(\d+)", keypad)}

touchpad = (ROOT / "firebird-harmony/entry/src/main/ets/components/Touchpad.ets").read_text()
assert "@State private activePointer" in touchpad
assert "event.touches.length === 1" in touchpad

# Every non-empty key in keymap.h must be reachable from the native ArkUI keypad.
expected = {
    0, 1, 3, 4, 5, 6, 7, 8, 9,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
    44, 45, 46, 48, 49, 50, 51, 52, 53,
    56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
    66, 68, 69, 70, 71, 72, 73, 75, 85, 86, 87,
}
assert ids == expected, f"ArkUI keypad coverage mismatch: missing={expected - ids}, extra={ids - expected}"
assert "{ id: 4, label: 'space', span: 2 }" in keypad
assert "this.columnWidth * span + this.gap * (span - 1)" in keypad

assert "repeatTime" not in physical
for key_code in ("KEYCODE_HOME", "KEYCODE_MOVE_END", "KEYCODE_PAGE_UP", "KEYCODE_PAGE_DOWN",
                 "KEYCODE_INSERT", "KEYCODE_F1", "KEYCODE_F2", "KEYCODE_F3"):
    assert key_code in physical, f"missing physical keyboard mapping for {key_code}"
assert "deviceId" in physical and "this.altKeys" in physical
assert "setTouchpadState(0.5, 0.5, true, false)" in physical
assert "firebirdTopInsetPx" in entry_ability and "getWindowAvoidArea" in entry_ability
assert "px2vp(this.topInsetPx)" in index_page
assert "setSpeedLimit(2)" in index_page and "setSpeedLimit(0)" in index_page
assert "setSpeedLimit: (limit: 1 | 2 | 0)" in native_types
assert "unlinkSync(destination)" not in file_store
assert "boot-candidate.tmp" in file_store and "flash-candidate.tmp" in file_store

for relative in (
    "firebird-harmony/AppScope/app.json5",
    "firebird-harmony/build-profile.json5",
    "firebird-harmony/entry/build-profile.json5",
    "firebird-harmony/entry/src/main/module.json5",
):
    content = (ROOT / relative).read_text()
    assert "/home/" not in content
    assert "Downloads" not in content

print(f"validated {len(ids)} calculator keys and Harmony project path hygiene")
