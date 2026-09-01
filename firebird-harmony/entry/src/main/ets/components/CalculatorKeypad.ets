import { CalculatorKey } from './CalculatorKey';
import { Touchpad } from './Touchpad';

interface KeyDefinition {
  id: number;
  label: string;
  secondary?: string;
  style?: string;
  weight?: number;
  span?: number;
}

const NUMBER_ROW_1: Array<KeyDefinition> = [
  { id: 85, label: 'shift', secondary: 'CAPS', style: 'function' },
  { id: -1, label: '' },
  { id: 56, label: 'var', secondary: 'sto→', style: 'function' }
];
const NUMBER_ROW_2: Array<KeyDefinition> = [
  { id: 40, label: '7', style: 'number' }, { id: 72, label: '8', style: 'number' },
  { id: 36, label: '9', style: 'number' }
];
const NUMBER_ROW_3: Array<KeyDefinition> = [
  { id: 29, label: '4', style: 'number' }, { id: 61, label: '5', style: 'number' },
  { id: 25, label: '6', style: 'number' }
];
const NUMBER_ROW_4: Array<KeyDefinition> = [
  { id: 18, label: '1', style: 'number' }, { id: 70, label: '2', style: 'number' },
  { id: 14, label: '3', style: 'number' }
];
const NUMBER_ROW_5: Array<KeyDefinition> = [
  { id: 7, label: '0', style: 'number' },
  { id: 59, label: '.', secondary: 'capture', style: 'number' },
  { id: 3, label: '(−)', secondary: 'ans', style: 'number' }
];

const ALPHA_ROW_1: Array<KeyDefinition> = [
  { id: 30, label: 'EE' }, { id: 50, label: 'A' }, { id: 49, label: 'B' },
  { id: 48, label: 'C' }, { id: 46, label: 'D' }, { id: 45, label: 'E' },
  { id: 44, label: 'F' }, { id: 39, label: 'G' }, { id: 8, label: '?!▸' }
];
const ALPHA_ROW_2: Array<KeyDefinition> = [
  { id: 19, label: 'π▸' }, { id: 38, label: 'H' }, { id: 37, label: 'I' },
  { id: 35, label: 'J' }, { id: 34, label: 'K' }, { id: 33, label: 'L' },
  { id: 28, label: 'M' }, { id: 27, label: 'N' }, { id: 66, label: '⚑' }
];
const ALPHA_ROW_3: Array<KeyDefinition> = [
  { id: 87, label: ',' }, { id: 26, label: 'O' }, { id: 24, label: 'P' },
  { id: 23, label: 'Q' }, { id: 22, label: 'R' }, { id: 17, label: 'S' },
  { id: 16, label: 'T' }, { id: 15, label: 'U' }, { id: 0, label: '↵' }
];
const ALPHA_ROW_4: Array<KeyDefinition> = [
  { id: -1, label: '' }, { id: 13, label: 'V' }, { id: 12, label: 'W' },
  { id: 11, label: 'X' }, { id: 6, label: 'Y' }, { id: 5, label: 'Z' },
  { id: 4, label: 'space', span: 2 }, { id: -2, label: '' }
];

@Component
struct KeyRow {
  @Prop keys: Array<KeyDefinition>;
  @Prop rowHeight: number;
  @Prop gap: number = 2;
  @Prop fontSize: number = 10;
  @Prop hitTop: number = 0;

  build() {
    Row({ space: this.gap }) {
      ForEach(this.keys, (key: KeyDefinition) => {
        if (key.id >= 0) {
          CalculatorKey({
            keyId: key.id,
            label: key.label,
            secondary: key.secondary ?? '',
            keyHeight: this.rowHeight,
            faceStyle: key.style ?? 'alpha',
            fontSize: this.fontSize,
            hitLeft: this.gap / 2,
            hitRight: this.gap / 2,
            hitTop: this.hitTop
          }).layoutWeight(key.weight ?? 1)
        } else {
          Blank().layoutWeight(key.weight ?? 1)
        }
      }, (key: KeyDefinition) => `${key.id}-${key.label}`)
    }
    .width('100%')
    .height(this.rowHeight)
  }
}

@Component
struct DualKey {
  @Prop leftId: number;
  @Prop leftLabel: string;
  @Prop leftSecondary: string = '';
  @Prop rightId: number;
  @Prop rightLabel: string;
  @Prop rightSecondary: string = '';
  @Prop keyHeight: number;
  @Prop fontSize: number;

  private legendHeight(): number { return this.keyHeight / 3; }
  private faceHeight(): number { return this.keyHeight - this.legendHeight(); }

  build() {
    Row({ space: 0 }) {
      CalculatorKey({ keyId: this.leftId, label: this.leftLabel,
        secondary: this.leftSecondary, keyHeight: this.faceHeight(), legendHeight: this.legendHeight(),
        fontSize: this.fontSize })
        .width('50%')
      CalculatorKey({ keyId: this.rightId, label: this.rightLabel,
        secondary: this.rightSecondary, keyHeight: this.faceHeight(), legendHeight: this.legendHeight(),
        fontSize: this.fontSize })
        .width('50%')
    }
    .width('100%')
    .height(this.keyHeight)
  }
}

@Component
struct AlphaKeyRow {
  @Prop keys: Array<KeyDefinition>;
  @Prop rowHeight: number;
  @Prop gap: number;
  @Prop columnWidth: number;
  @Prop fontSize: number;

  private itemWidth(key: KeyDefinition): number {
    const span = key.span ?? 1;
    return this.columnWidth * span + this.gap * (span - 1);
  }

  build() {
    Row({ space: this.gap }) {
      ForEach(this.keys, (key: KeyDefinition) => {
        if (key.id >= 0) {
          CalculatorKey({
            keyId: key.id,
            label: key.label,
            keyHeight: this.rowHeight,
            faceStyle: 'alpha',
            fontSize: this.fontSize,
            hitLeft: this.gap / 2,
            hitRight: this.gap / 2
          }).width(this.itemWidth(key))
        } else {
          Blank().width(this.itemWidth(key))
        }
      }, (key: KeyDefinition) => `${key.id}-${key.label}`)
    }
    .width('100%')
    .height(this.rowHeight)
  }
}

@Component
export struct CalculatorKeypad {
  @Prop speed: number = 0;
  @Prop speedLimitMode: number = 1;
  @Prop layoutMode: string = 'full';
  onCycleSpeedLimit: () => void = () => {};
  @State private contentWidth: number = 265;
  @State private contentHeight: number = 340;
  @State private availableWidth: number = 265;
  @State private availableHeight: number = 340;

  private x(value: number): number { return this.contentWidth * value / 265; }
  private baseHeight(): number {
    if (this.layoutMode === 'navigation') return 104;
    if (this.layoutMode === 'main') return 226;
    return 340;
  }

  private y(value: number): number { return this.contentHeight * value / this.baseHeight(); }
  private font(value: number): number { return Math.max(8, this.x(value)); }
  private alphaColumnWidth(): number { return this.x((265 - 10 - 8 * 3) / 9); }

  private fit(width: number, height: number): void {
    if (width <= 0 || height <= 0) return;
    this.availableWidth = width;
    this.availableHeight = height;
    const panelRatio = 265 / this.baseHeight();
    if (width / height > panelRatio) {
      this.contentHeight = height;
      this.contentWidth = height * panelRatio;
    } else {
      this.contentWidth = width;
      this.contentHeight = width / panelRatio;
    }
  }

  private speedLimitLabel(): string {
    if (this.speedLimitMode === 2) return '200%';
    if (this.speedLimitMode === 0) return 'unlimited';
    return '100%';
  }

  private speedAreaHeight(): number {
    return Math.max(0, this.availableHeight - this.contentHeight);
  }

  private speedRowHeight(): number {
    return Math.min(36, this.speedAreaHeight());
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.layoutMode !== 'main' && this.speedAreaHeight() >= 18) {
        Row() {
          Text(`Speed ${(this.speed * 100).toFixed(0)}%  ·  Limit ${this.speedLimitLabel()}`)
            .fontColor('#DDE6E8')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
        }
        .width(this.contentWidth)
        .height(this.speedRowHeight())
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .position({
          x: (this.availableWidth - this.contentWidth) / 2,
          y: (this.speedAreaHeight() - this.speedRowHeight()) / 2
        })
        .onClick(() => this.onCycleSpeedLimit())
      }

      Column({ space: 0 }) {
        if (this.layoutMode !== 'main') {
          Row({ space: 0 }) {
          Column({ space: this.y(16) }) {
            CalculatorKey({ keyId: 73, label: 'esc', keyHeight: this.y(20), legendOffset: this.y(10),
              faceStyle: 'nav', fontSize: this.font(9), hitLeft: this.x(5), hitRight: this.x(17.5),
              hitTop: this.y(6) })
            CalculatorKey({ keyId: 65, label: 'pad', secondary: 'save', keyHeight: this.y(20),
              legendOffset: this.y(10),
              faceStyle: 'nav', fontSize: this.font(9), hitLeft: this.x(5), hitRight: this.x(17.5),
              hitTop: this.y(16) })
            CalculatorKey({ keyId: 75, label: 'tab', keyHeight: this.y(20), legendOffset: this.y(10),
              faceStyle: 'nav', fontSize: this.font(9), hitLeft: this.x(5), hitRight: this.x(17.5),
              hitTop: this.y(16), hitBottom: this.y(6) })
          }
          .width(this.x(33))
          .height(this.y(92))

          Blank().width(this.x(35))
          Touchpad({ padHeight: this.y(92) }).width(this.x(119))
          Blank().width(this.x(35))

          Column({ space: this.y(16) }) {
            CalculatorKey({ keyId: 9, label: '⌂ on', keyHeight: this.y(20), legendOffset: this.y(10),
              faceStyle: 'on', fontSize: this.font(8), hitLeft: this.x(17.5), hitRight: this.x(5),
              hitTop: this.y(6) })
            CalculatorKey({ keyId: 69, label: 'doc', secondary: '+page', keyHeight: this.y(20),
              legendOffset: this.y(10),
              faceStyle: 'nav', fontSize: this.font(9), hitLeft: this.x(17.5), hitRight: this.x(5),
              hitTop: this.y(16) })
            CalculatorKey({ keyId: 71, label: 'menu', secondary: '☰', keyHeight: this.y(20),
              legendOffset: this.y(10),
              faceStyle: 'nav', fontSize: this.font(9), hitLeft: this.x(17.5), hitRight: this.x(5),
              hitTop: this.y(16), hitBottom: this.y(6) })
          }
          .width(this.x(33))
          .height(this.y(92))
        }
        .padding({ left: this.x(5), right: this.x(5), top: this.y(6), bottom: this.y(6) })
        .width('100%')
        .height(this.y(104))
          .backgroundColor('#111111')
        }

        if (this.layoutMode === 'full') {
          Blank().height(this.y(10))
        }

        if (this.layoutMode !== 'navigation') {
          Row({ space: this.x(8) }) {
          Column({ space: 0 }) {
            Row() {
              CalculatorKey({ keyId: 86, label: 'ctrl', keyHeight: this.y(20),
                faceStyle: 'accent', fontSize: this.font(9), hitTop: this.y(5),
                hitRight: this.x(21) }).width(this.x(33))
              Blank()
            }.width('100%').height(this.y(20))
            DualKey({ leftId: 51, leftLabel: '=', leftSecondary: '|≠≥>',
              rightId: 20, rightLabel: 'trig', rightSecondary: '?',
              keyHeight: this.y(30), fontSize: this.font(8) })
            DualKey({ leftId: 53, leftLabel: '^', leftSecondary: 'ⁿ√x',
              rightId: 31, rightLabel: 'x²', rightSecondary: '√',
              keyHeight: this.y(30), fontSize: this.font(9) })
            DualKey({ leftId: 42, leftLabel: 'eˣ', leftSecondary: 'ln',
              rightId: 21, rightLabel: '10ˣ', rightSecondary: 'log',
              keyHeight: this.y(30), fontSize: this.font(8) })
            DualKey({ leftId: 60, leftLabel: '(', leftSecondary: '[ ]',
              rightId: 58, rightLabel: ')', rightSecondary: '{ }',
              keyHeight: this.y(30), fontSize: this.font(10) })
          }
          .width(this.x(50))
          .height(this.y(140))

          Column({ space: this.y(10) }) {
            KeyRow({ keys: NUMBER_ROW_1, rowHeight: this.y(20), gap: this.x(10), fontSize: this.font(8),
              hitTop: this.y(10) })
            KeyRow({ keys: NUMBER_ROW_2, rowHeight: this.y(20), gap: this.x(10), fontSize: this.font(10),
              hitTop: this.y(10) })
            KeyRow({ keys: NUMBER_ROW_3, rowHeight: this.y(20), gap: this.x(10), fontSize: this.font(10),
              hitTop: this.y(10) })
            KeyRow({ keys: NUMBER_ROW_4, rowHeight: this.y(20), gap: this.x(10), fontSize: this.font(10),
              hitTop: this.y(10) })
            KeyRow({ keys: NUMBER_ROW_5, rowHeight: this.y(20), gap: this.x(10), fontSize: this.font(9),
              hitTop: this.y(10) })
          }
          .layoutWeight(1)
          .height(this.y(140))

          Column({ space: 0 }) {
            Row() {
              Blank()
              CalculatorKey({ keyId: 64, label: 'del', secondary: 'clear', keyHeight: this.y(20),
                fontSize: this.font(9), hitTop: this.y(10), hitLeft: this.x(21) }).width(this.x(33))
            }.width('100%').height(this.y(20))
            DualKey({ leftId: 63, leftLabel: '▦', leftSecondary: ':=',
              rightId: 62, rightLabel: '☷', rightSecondary: '∞ β °',
              keyHeight: this.y(30), fontSize: this.font(9) })
            DualKey({ leftId: 52, leftLabel: '×', leftSecondary: '“□”',
              rightId: 41, rightLabel: '÷', rightSecondary: '÷',
              keyHeight: this.y(30), fontSize: this.font(10) })
            DualKey({ leftId: 68, leftLabel: '+', leftSecondary: '◐+',
              rightId: 57, rightLabel: '−', rightSecondary: '◐−',
              keyHeight: this.y(30), fontSize: this.font(10) })
            Blank().height(this.y(10))
            CalculatorKey({ keyId: 1, label: 'enter', secondary: '≈', keyHeight: this.y(20),
              fontSize: this.font(8), hitTop: this.y(10), hitBottom: this.y(3) })
          }
          .width(this.x(50))
          .height(this.y(140))
        }
        .padding({ left: this.x(5), right: this.x(5) })
        .width('100%')
          .height(this.y(140))

          Blank().height(this.y(6))

          Column({ space: 0 }) {
          AlphaKeyRow({ keys: ALPHA_ROW_1, rowHeight: this.y(20), gap: this.x(3),
            columnWidth: this.alphaColumnWidth(), fontSize: this.font(7) })
          AlphaKeyRow({ keys: ALPHA_ROW_2, rowHeight: this.y(20), gap: this.x(3),
            columnWidth: this.alphaColumnWidth(), fontSize: this.font(7) })
          AlphaKeyRow({ keys: ALPHA_ROW_3, rowHeight: this.y(20), gap: this.x(3),
            columnWidth: this.alphaColumnWidth(), fontSize: this.font(7) })
          AlphaKeyRow({ keys: ALPHA_ROW_4, rowHeight: this.y(20), gap: this.x(3),
            columnWidth: this.alphaColumnWidth(), fontSize: this.font(7) })
        }
        .padding({ left: this.x(5), right: this.x(5) })
        .width('100%')
          .height(this.y(80))
        }

        Blank().layoutWeight(1)
      }
      .width(this.contentWidth)
      .height(this.contentHeight)
      .backgroundColor('#3F4146')
      .position({
        x: (this.availableWidth - this.contentWidth) / 2,
        y: this.layoutMode === 'main' ?
          (this.availableHeight - this.contentHeight) / 2 : this.availableHeight - this.contentHeight
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#3F4146')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.fit(Number(newArea.width), Number(newArea.height));
    })
  }
}
