import { KeyCode } from '@kit.InputKit';
import * as firebird from 'libfirebird_harmony.so';

const LETTER_IDS: Array<number> = [50, 49, 48, 46, 45, 44, 39, 38, 37, 35, 34, 33, 28,
  27, 26, 24, 23, 22, 17, 16, 15, 13, 12, 11, 6, 5];
const NUMBER_IDS: Array<number> = [7, 18, 70, 14, 29, 61, 25, 40, 72, 36];

export class PhysicalKeyMap {
  private pressed: Map<string, number> = new Map();
  private arrows: Map<string, number> = new Map();
  private altKeys: Set<string> = new Set();

  handle(event: KeyEvent): boolean {
    const isDown = event.type === KeyType.Down;
    const code = event.keyCode;
    const physical = `${event.deviceId}:${code}`;
    if (code === KeyCode.KEYCODE_ALT_LEFT || code === KeyCode.KEYCODE_ALT_RIGHT) {
      if (isDown) this.altKeys.add(physical); else this.altKeys.delete(physical);
      return true;
    }
    if (this.isArrow(code)) {
      if (isDown) {
        if (this.arrows.has(physical)) return true;
        this.arrows.set(physical, code);
      } else {
        this.arrows.delete(physical);
      }
      this.submitArrowState();
      return true;
    }
    if (!isDown) {
      const prior = this.pressed.get(physical);
      if (prior !== undefined) {
        firebird.setKeyState(prior, false);
        this.pressed.delete(physical);
        return true;
      }
      return false;
    }
    if (this.pressed.has(physical)) return true;
    const keyId = this.translate(code, this.altKeys.size > 0, event.keyText);
    if (keyId < 0) return false;
    this.pressed.set(physical, keyId);
    firebird.setKeyState(keyId, true);
    return true;
  }

  releaseAll(): void {
    this.pressed.forEach((keyId: number): void => { firebird.setKeyState(keyId, false); });
    this.pressed.clear();
    this.arrows.clear();
    this.altKeys.clear();
    firebird.releaseAllInputs();
  }

  private isArrow(code: number): boolean {
    return code === KeyCode.KEYCODE_DPAD_UP || code === KeyCode.KEYCODE_DPAD_DOWN ||
      code === KeyCode.KEYCODE_DPAD_LEFT || code === KeyCode.KEYCODE_DPAD_RIGHT;
  }

  private submitArrowState(): void {
    const active = Array.from(this.arrows.values()).pop();
    if (active === undefined) firebird.setTouchpadState(0.5, 0.5, false, false);
    else if (active === KeyCode.KEYCODE_DPAD_UP) firebird.setTouchpadState(0.5, 0.0, true, true);
    else if (active === KeyCode.KEYCODE_DPAD_DOWN) firebird.setTouchpadState(0.5, 1.0, true, true);
    else if (active === KeyCode.KEYCODE_DPAD_LEFT) firebird.setTouchpadState(0.0, 0.5, true, true);
    else firebird.setTouchpadState(1.0, 0.5, true, true);
  }

  private translate(code: number, alt: boolean, text: string): number {
    if (alt) {
      switch (code) {
        case KeyCode.KEYCODE_ESCAPE: return 9;
        case KeyCode.KEYCODE_D: return 69;
        case KeyCode.KEYCODE_M: return 71;
        case KeyCode.KEYCODE_V: return 56;
        case KeyCode.KEYCODE_E: return 30;
        case KeyCode.KEYCODE_W: return 8;
        case KeyCode.KEYCODE_F: return 66;
        case KeyCode.KEYCODE_Q: return 51;
        case KeyCode.KEYCODE_T: return 20;
        case KeyCode.KEYCODE_P: return 53;
        case KeyCode.KEYCODE_2: return 31;
        case KeyCode.KEYCODE_X: return 42;
        case KeyCode.KEYCODE_1: return 21;
        case KeyCode.KEYCODE_O: return 63;
        case KeyCode.KEYCODE_C: return 62;
        case KeyCode.KEYCODE_A: return 52;
        case KeyCode.KEYCODE_EQUALS: return 68;
        case KeyCode.KEYCODE_ENTER:
        case KeyCode.KEYCODE_NUMPAD_ENTER: return 0;
      }
    }
    const textMap: Map<string, number> = new Map([
      ['<', 30], ['|', 19], [',', 87], ['?', 8], ['>', 66], ['.', 59], ['`', 3],
      ['=', 51], ['\\', 20], ['^', 53], ['@', 31], ['[', 42], [']', 21], ['(', 60],
      [')', 58], [';', 63], ["'", 62], ['*', 52], ['/', 41], ['+', 68], ['-', 57],
      ['_', 57]
    ]);
    const fromText = textMap.get(text);
    if (fromText !== undefined) return fromText;
    if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z)
      return LETTER_IDS[code - KeyCode.KEYCODE_A];
    if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9)
      return NUMBER_IDS[code - KeyCode.KEYCODE_0];
    switch (code) {
      case KeyCode.KEYCODE_ESCAPE: return 73;
      case KeyCode.KEYCODE_MOVE_END: return 65;
      case KeyCode.KEYCODE_HOME: return 9;
      case KeyCode.KEYCODE_PAGE_UP: return 69;
      case KeyCode.KEYCODE_PAGE_DOWN: return 71;
      case KeyCode.KEYCODE_INSERT: return 56;
      case KeyCode.KEYCODE_F1: return 60;
      case KeyCode.KEYCODE_F2: return 58;
      case KeyCode.KEYCODE_F3: return 41;
      case KeyCode.KEYCODE_TAB: return 75;
      case KeyCode.KEYCODE_SHIFT_LEFT:
      case KeyCode.KEYCODE_SHIFT_RIGHT: return 85;
      case KeyCode.KEYCODE_CTRL_LEFT:
      case KeyCode.KEYCODE_CTRL_RIGHT: return 86;
      case KeyCode.KEYCODE_DEL:
      case KeyCode.KEYCODE_FORWARD_DEL: return 64;
      case KeyCode.KEYCODE_SPACE: return 4;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER: return 1;
      case KeyCode.KEYCODE_NUMPAD_MULTIPLY: return 52;
      case KeyCode.KEYCODE_NUMPAD_ADD: return 68;
      case KeyCode.KEYCODE_NUMPAD_SUBTRACT: return 57;
      default: return -1;
    }
  }
}
