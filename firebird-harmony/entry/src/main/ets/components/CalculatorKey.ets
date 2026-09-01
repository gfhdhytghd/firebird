import * as firebird from 'libfirebird_harmony.so';

@Component
export struct CalculatorKey {
  @Prop keyId: number;
  @Prop label: string;
  @Prop secondary: string = '';
  @Prop keyHeight: number = 34;
  @Prop legendHeight: number = 0;
  @Prop legendOffset: number = 10;
  @Prop faceStyle: string = 'function';
  @Prop fontSize: number = 12;
  @Prop hitLeft: number = 0;
  @Prop hitRight: number = 0;
  @Prop hitTop: number = 0;
  @Prop hitBottom: number = 0;
  @State private pressed: boolean = false;
  private activePointers: Set<number> = new Set();

  private faceColor(): string {
    if (this.pressed) return '#718A91';
    if (this.faceStyle === 'number') return '#505256';
    if (this.faceStyle === 'alpha') return '#252A31';
    if (this.faceStyle === 'accent') return '#9ED9E5';
    if (this.faceStyle === 'on') return '#39616D';
    if (this.faceStyle === 'nav') return '#202631';
    return '#202532';
  }

  private fontColor(): string {
    return this.faceStyle === 'accent' ? '#172126' : '#FFFFFF';
  }

  private secondaryHeight(): number {
    return this.legendHeight > 0 ? this.legendHeight : Math.min(this.legendOffset, this.keyHeight * 0.5);
  }

  private release(): void {
    this.activePointers.clear();
    if (!this.pressed) return;
    this.pressed = false;
    firebird.setKeyState(this.keyId, false);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Text(this.label)
        .fontSize(this.fontSize)
        .fontColor(this.fontColor())
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .backgroundColor(this.faceColor())
        .border({ width: this.pressed ? 2 : 1, color: '#8B9599', radius: 4 })
        .height(this.keyHeight)
        .width('100%')
      if (this.secondary.length > 0) {
        Text(this.secondary)
          .fontColor('#68CCE0')
          .fontSize(Math.max(7, this.fontSize * 0.72))
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .width('100%')
          .height(this.secondaryHeight())
          .position({ x: 0, y: this.legendHeight > 0 ? 0 : -this.secondaryHeight() })
      }
    }
    .height(this.keyHeight + this.legendHeight)
    .width('100%')
    .clip(false)
    .hitTestBehavior(HitTestMode.Block)
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
