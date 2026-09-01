#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
keypad = (ROOT / "firebird-harmony/entry/src/main/ets/components/CalculatorKeypad.ets").read_text()
calculator_key = (ROOT / "firebird-harmony/entry/src/main/ets/components/CalculatorKey.ets").read_text()
physical = (ROOT / "firebird-harmony/entry/src/main/ets/bridge/PhysicalKeyMap.ets").read_text()
file_store = (ROOT / "firebird-harmony/entry/src/main/ets/bridge/FileStore.ets").read_text()
index_page = (ROOT / "firebird-harmony/entry/src/main/ets/pages/Index.ets").read_text()
entry_ability = (ROOT / "firebird-harmony/entry/src/main/ets/entryability/EntryAbility.ets").read_text()
native_types = (ROOT / "firebird-harmony/entry/src/main/cpp/types/libfirebird_harmony/Index.d.ts").read_text()
settings_drawer = (ROOT / "firebird-harmony/entry/src/main/ets/components/SettingsDrawer.ets").read_text()
assert "Button('←')" in settings_drawer
assert ".accessibilityText('Back to menu')" in settings_drawer
assert "Button('‹ Menu')" not in settings_drawer
mobile_drawer = (ROOT / "firebird-harmony/entry/src/main/ets/components/MobileDrawer.ets").read_text()
napi_source = (ROOT / "firebird-harmony/entry/src/main/cpp/napi/napi_init.cpp").read_text()
emulator_service = (ROOT / "firebird-harmony/entry/src/main/cpp/emulator/emulator_service.cpp").read_text()
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
assert ".responseRegion({" not in calculator_key
assert "calc(100%" not in calculator_key
for hit_prop in ("hitLeft", "hitRight", "hitTop", "hitBottom"):
    assert f"@Prop {hit_prop}" in calculator_key
assert "hitLeft: this.gap / 2" in keypad and "hitRight: this.gap / 2" in keypad
assert "hitTop: this.y(10)" in keypad

assert "repeatTime" not in physical
for key_code in ("KEYCODE_HOME", "KEYCODE_MOVE_END", "KEYCODE_PAGE_UP", "KEYCODE_PAGE_DOWN",
                 "KEYCODE_INSERT", "KEYCODE_F1", "KEYCODE_F2", "KEYCODE_F3"):
    assert key_code in physical, f"missing physical keyboard mapping for {key_code}"
assert "deviceId" in physical and "this.altKeys" in physical
assert "setTouchpadState(0.5, 0.5, true, false)" in physical
assert "firebirdTopInsetPx" in entry_ability and "getWindowAvoidArea" in entry_ability
assert "TYPE_SYSTEM" in entry_ability and "TYPE_CUTOUT" in entry_ability
assert "Math.max(systemTopInset, cutoutTopInset)" in entry_ability
assert "px2vp(this.topInsetPx)" in index_page
assert "setSpeedLimit(2)" in index_page and "setSpeedLimit(0)" in index_page
assert ".onClick(() => this.drawerOpen = true)" not in index_page
assert "(point.x - this.drawerOriginX) / this.drawerWidth()" in index_page
assert "this.drawerProgress >= 0.2" in index_page
up_branch = re.search(r"event\.type === TouchType\.Up\)(.*?)else if \(event\.type === TouchType\.Cancel", index_page, re.S)
move_branch = re.search(r"event\.type === TouchType\.Move.*?\{(.*?)else if \(event\.type === TouchType\.Up", index_page, re.S)
assert up_branch is not None and "this.showMobilePage(1)" in up_branch.group(1)
assert move_branch is not None and "this.showMobilePage(1)" not in move_branch.group(1)
assert ".translate({ x: -this.drawerWidth() * (1 - this.drawerProgress) })" in index_page
assert ".animation({ duration: this.drawerDragging ? 0 : 220, curve: Curve.EaseOut })" in index_page
assert ".hitTestBehavior(this.mobilePage === 1 ? HitTestMode.Default : HitTestMode.None)" in index_page
assert index_page.count(".hitTestBehavior(this.mobilePage === 1 ? HitTestMode.Default : HitTestMode.None)") == 2
back_handler = re.search(r"onBackPress\(\): boolean \{(.*?)\n  \}", index_page, re.S)
assert back_handler is not None
assert "this.mobilePage === 2" in back_handler.group(1)
assert "this.returnToDrawer()" in back_handler.group(1)
assert "this.mobilePage === 1 || this.drawerProgress > 0" in back_handler.group(1)
assert "this.closeDrawer()" in back_handler.group(1)
assert "if (this.mobilePage === 2)" in index_page
assert index_page.count("this.mobilePage === 1 || this.drawerProgress > 0") == 1
assert "private releaseAllInputs(): void" in index_page
assert "firebird.releaseAllInputs();" in index_page
assert index_page.count("this.showMobilePage(") >= 3
assert index_page.count("this.handleDrawerSwipe(event)") == 2
assert "Text('Swipe here')" not in index_page
assert "private drawerHandle()" not in index_page
assert "backgroundColor('#01000000')" not in index_page
assert index_page.count("backgroundColor('#00000000')") == 2
assert index_page.count(".hitTestBehavior(HitTestMode.Block)") >= 3
assert index_page.count(".clip(true)") == 2
assert "this.wideLayout = this.landscape || this.viewWidth >= 600" in index_page
assert "layoutMode: 'navigation'" in index_page
assert "@State private navigationSide" in index_page
assert "@State private splitRatio" in index_page
assert "this.splitRatio = Math.min(0.7, Math.max(0.3, ratio))" in index_page
assert "this.handleSplitterTouch(event)" in index_page
assert "private splitterWidth(): number { return 20; }" in index_page
assert ".hitTestBehavior(HitTestMode.Block)" in index_page
assert "showSpeed: false" in index_page
assert "onMoveNavigation: (side: string) => { this.navigationSide = side; }" in index_page
assert "private compactSpeedPanel()" in index_page
assert "@Prop layoutMode: string = 'full'" in keypad
assert "@Prop navigationSide: string = 'left'" in keypad
assert "this.isNavigationBlank(event.changedTouches[0])" in keypad
assert "localX >= 38 && localX <= 73" in keypad
assert "localX >= 192 && localX <= 227" in keypad
assert "Math.abs(point.windowX - this.navigationOriginX) >= 32" in keypad
assert "return Math.min(36, this.speedAreaHeight())" in keypad
assert "private leftInstrumentWidth()" in index_page
assert "private rightInstrumentWidth()" in index_page
assert ".aspectRatio(265 / 104)" in index_page
assert ".aspectRatio(265 / 236)" in index_page
assert "if (this.layoutMode === 'main') return 236" in keypad
assert "Blank().height(this.y(10)).backgroundColor('#3F4146')" in keypad
assert "this.mobilePage = page" in index_page
assert "this.showMobilePage(1)" in index_page and "this.showMobilePage(2)" in index_page
for action in ("Start", "Reset", "Resume", "Save", "Configuration"):
    assert f"'{action}'" in mobile_drawer, f"missing mobile drawer action {action}"
assert "this.tabButton('Config'" not in mobile_drawer
assert "setSpeedLimit: (limit: 1 | 2 | 0)" in native_types
validation_type = re.search(r"export interface ValidationResult \{(.*?)\n\}", native_types, re.S)
status_type = re.search(r"export interface EmulatorStatus \{(.*?)\n\}", native_types, re.S)
assert validation_type is not None and status_type is not None
for status_field in ("usbLinkConnected", "transferProgress", "debuggerActive",
                     "debuggerWaitingForInput"):
    assert status_field in status_type.group(1), f"missing status field {status_field}"
    assert status_field not in validation_type.group(1), f"status field leaked into validation: {status_field}"
assert "unlinkSync(destination)" not in file_store
assert "boot-candidate.tmp" in file_store and "flash-candidate.tmp" in file_store
assert "activeProfile" in file_store and "profiles/${this.activeProfileId}" in file_store
assert "name.startsWith('autosave-')" in file_store
for tab in ("Config", "Emulator", "Transfer", "Debugger"):
    assert f"this.tabButton('{tab}'" in settings_drawer
assert "const PANEL_BG: string = '#0B0D10'" in settings_drawer
assert "const NAV_BG: string = '#12161B'" in settings_drawer
scroll_position = settings_drawer.rfind("Scroll()")
bottom_tabs_position = settings_drawer.rfind("this.tabButton('Config', 0)")
assert scroll_position < bottom_tabs_position, "settings tabs must remain below the content scroll area"
assert ".align(Alignment.Top)" in settings_drawer
assert settings_drawer.count("placeholderColor(MUTED)") == 6
assert settings_drawer.count("caretColor(ACTIVE)") == 6
for native_api in ("sendFile", "exitPressToTest", "configureDebugger", "enterDebugger",
                   "sendDebuggerCommand", "getDebugLog"):
    assert f'{{"{native_api}"' in napi_source, f"missing NAPI export {native_api}"
    assert f"export const {native_api}" in native_types, f"missing native declaration {native_api}"

stop_body = re.search(r"bool EmulatorService::Stop\(std::string &error\)(.*?)\n\}",
                      emulator_service, re.S)
assert stop_body is not None
assert "error = status_.error" not in stop_body.group(1), "stop must remain usable after a core error"

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
