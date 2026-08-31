import * as firebird from 'libfirebird_harmony.so';

@Component
export struct CalculatorKey {
  @Prop keyId: number;
  @Prop label: string;
  @Prop accent: boolean = false;
  @State private pressed: boolean = false;
  private activePointers: Set<number> = new Set();

  private release(): void {
    this.activePointers.clear();
    if (!this.pressed) return;
    this.pressed = false;
    firebird.setKeyState(this.keyId, false);
  }

  build() {
    Text(this.label)
      .fontSize(this.label.length > 5 ? 9 : 12)
      .fontColor(Color.White)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pressed ? '#718A91' : (this.accent ? '#315968' : '#202327'))
      .border({ width: 1, color: '#88949A', radius: 5 })
      .height(34)
      .width('100%')
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          event.changedTouches.forEach((point: TouchObject): void => {
            this.activePointers.add(point.id);
          });
          if (!this.pressed && this.activePointers.size > 0) {
            this.pressed = true;
            firebird.setKeyState(this.keyId, true);
          }
        } else if (event.type === TouchType.Up) {
          event.changedTouches.forEach((point: TouchObject): void => {
            this.activePointers.delete(point.id);
          });
          if (this.activePointers.size === 0) this.release();
        } else if (event.type === TouchType.Cancel) {
          this.release();
        }
      })
      .onDisAppear(() => this.release())
  }
}
