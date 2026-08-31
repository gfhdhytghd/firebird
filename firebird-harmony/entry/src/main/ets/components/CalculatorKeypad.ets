import { CalculatorKey } from './CalculatorKey';
import { Touchpad } from './Touchpad';

interface KeyDefinition {
  id: number;
  label: string;
  accent?: boolean;
}

const KEYS: Array<KeyDefinition> = [
  { id: 73, label: 'esc' }, { id: 65, label: 'pad' }, { id: 75, label: 'tab' },
  { id: 9, label: 'on', accent: true }, { id: 69, label: 'doc' }, { id: 71, label: 'menu' },
  { id: 85, label: 'shift', accent: true }, { id: 56, label: 'var' }, { id: 64, label: 'del' },
  { id: 51, label: '=' }, { id: 20, label: 'trig' }, { id: 53, label: '^' },
  { id: 31, label: 'x²' }, { id: 42, label: 'eˣ' }, { id: 21, label: '10ˣ' },
  { id: 60, label: '(' }, { id: 58, label: ')' }, { id: 63, label: 'matrix' },
  { id: 62, label: 'catalog' }, { id: 52, label: '×' }, { id: 41, label: '÷' },
  { id: 40, label: '7' }, { id: 72, label: '8' }, { id: 36, label: '9' }, { id: 68, label: '+' },
  { id: 29, label: '4' }, { id: 61, label: '5' }, { id: 25, label: '6' }, { id: 57, label: '−' },
  { id: 18, label: '1' }, { id: 70, label: '2' }, { id: 14, label: '3' }, { id: 1, label: 'enter', accent: true },
  { id: 7, label: '0' }, { id: 59, label: '.' }, { id: 3, label: '(−)' }, { id: 0, label: '↵' },
  { id: 86, label: 'ctrl', accent: true }, { id: 87, label: ',' }, { id: 4, label: 'space' },
  { id: 5, label: 'Z' }, { id: 6, label: 'Y' }, { id: 11, label: 'X' }, { id: 12, label: 'W' },
  { id: 13, label: 'V' }, { id: 15, label: 'U' }, { id: 16, label: 'T' }, { id: 17, label: 'S' },
  { id: 22, label: 'R' }, { id: 23, label: 'Q' }, { id: 24, label: 'P' }, { id: 26, label: 'O' },
  { id: 27, label: 'N' }, { id: 28, label: 'M' }, { id: 33, label: 'L' }, { id: 34, label: 'K' },
  { id: 35, label: 'J' }, { id: 37, label: 'I' }, { id: 38, label: 'H' }, { id: 39, label: 'G' },
  { id: 44, label: 'F' }, { id: 45, label: 'E' }, { id: 46, label: 'D' }, { id: 48, label: 'C' },
  { id: 49, label: 'B' }, { id: 50, label: 'A' }, { id: 19, label: 'π' }, { id: 30, label: '<' },
  { id: 66, label: '>' }, { id: 8, label: '?' }
];

@Component
export struct CalculatorKeypad {
  build() {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        Column({ space: 4 }) {
          CalculatorKey({ keyId: 73, label: 'esc' })
          CalculatorKey({ keyId: 65, label: 'pad' })
          CalculatorKey({ keyId: 75, label: 'tab' })
        }.width('18%')
        Touchpad().layoutWeight(1)
        Column({ space: 4 }) {
          CalculatorKey({ keyId: 9, label: 'on', accent: true })
          CalculatorKey({ keyId: 69, label: 'doc' })
          CalculatorKey({ keyId: 71, label: 'menu' })
        }.width('18%')
      }.width('100%')

      Grid() {
        ForEach(KEYS.filter((key: KeyDefinition) => ![73, 65, 75, 9, 69, 71].includes(key.id)),
          (key: KeyDefinition) => {
            GridItem() {
              CalculatorKey({ keyId: key.id, label: key.label, accent: key.accent ?? false })
            }
          }, (key: KeyDefinition) => key.id.toString())
      }
      .columnsTemplate('repeat(8, 1fr)')
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')
    }
    .padding({ left: 6, right: 6, top: 6, bottom: 0 })
    .backgroundColor('#303238')
    .width('100%')
  }
}
