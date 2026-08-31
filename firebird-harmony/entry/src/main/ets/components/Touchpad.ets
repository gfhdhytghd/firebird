import * as firebird from 'libfirebird_harmony.so';

@Component
export struct Touchpad {
  @Prop padHeight: number = 76;
  @State private highlightVisible: boolean = false;
  @State private highlightDown: boolean = false;
  @State private highlightX: number = 0;
  @State private highlightY: number = 0;
  @State private activePointer: number = -1;
  @State private originX: number = 0;
  @State private originY: number = 0;
  @State private down: boolean = false;
  @State private holdTimer: number = -1;
  @State private releaseTimer: number = -1;
  @State private latestX: number = 0;
  @State private latestY: number = 0;
  @State private widthVp: number = 1;
  @State private heightVp: number = 1;

  private cancelHold(): void {
    if (this.holdTimer >= 0) {
      clearTimeout(this.holdTimer);
      this.holdTimer = -1;
    }
  }

  private submit(x: number, y: number, contact: boolean, down: boolean): void {
    const clampedX = Math.max(0, Math.min(this.widthVp, x));
    const clampedY = Math.max(0, Math.min(this.heightVp, y));
    this.latestX = clampedX;
    this.latestY = clampedY;
    this.highlightX = clampedX;
    this.highlightY = clampedY;
    this.highlightVisible = contact || down;
    this.highlightDown = down;
    firebird.setTouchpadState(
      clampedX / Math.max(1, this.widthVp),
      clampedY / Math.max(1, this.heightVp),
      contact,
      down
    );
  }

  private release(): void {
    this.cancelHold();
    if (this.releaseTimer >= 0) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
    }
    this.activePointer = -1;
    this.down = false;
    this.highlightVisible = false;
    firebird.setTouchpadState(0.5, 0.5, false, false);
  }

  private findPoint(event: TouchEvent): TouchObject | undefined {
    const changed = event.changedTouches.find((candidate: TouchObject): boolean =>
      candidate.id === this.activePointer);
    if (changed !== undefined) return changed;
    const current = event.touches.find((candidate: TouchObject): boolean =>
      candidate.id === this.activePointer);
    if (current !== undefined) return current;

    // Some HarmonyOS input sources replace the pointer id between DOWN and MOVE.
    // A single remaining contact is still unambiguous; extra fingers never take
    // over an existing primary contact.
    if (event.touches.length === 1) return event.touches[0];
    if (event.touches.length === 0 && event.changedTouches.length === 1)
      return event.changedTouches[0];
    return undefined;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        Text('')
          .width('28%')
          .aspectRatio(1)
          .border({ width: 1, color: '#66757A', radius: 8 })
      }
      .width('100%')
      .height('100%')

      if (this.highlightVisible) {
        Text('')
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.highlightDown ? '#B3EDF2' : '#8298FF')
          .opacity(0.72)
          .position({ x: this.highlightX - 6, y: this.highlightY - 6 })
      }
    }
    .width('100%')
    .height(this.padHeight)
    .backgroundColor('#111315')
    .border({ width: 2, color: '#D8E0E2', radius: 12 })
    .hitTestBehavior(HitTestMode.Block)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.widthVp = Math.max(1, Number(newArea.width));
      this.heightVp = Math.max(1, Number(newArea.height));
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && this.activePointer < 0 && event.changedTouches.length > 0) {
        const point = event.changedTouches[0];
        if (this.releaseTimer >= 0) {
          clearTimeout(this.releaseTimer);
          this.releaseTimer = -1;
        }
        this.activePointer = point.id;
        this.originX = point.x;
        this.originY = point.y;
        this.down = false;
        this.submit(point.x, point.y, true, false);
        this.holdTimer = setTimeout(() => {
          this.holdTimer = -1;
          this.down = true;
          this.submit(this.latestX, this.latestY, true, true);
        }, 200);
      } else if (event.type === TouchType.Move && this.activePointer >= 0) {
        const point = this.findPoint(event);
        if (point !== undefined) {
          if (Math.abs(point.x - this.originX) > 5 || Math.abs(point.y - this.originY) > 5)
            this.cancelHold();
          this.submit(point.x, point.y, true, this.down);
        }
      } else if (event.type === TouchType.Up && this.activePointer >= 0) {
        const point = this.findPoint(event);
        if (point === undefined) return;
        const quickTap = this.holdTimer >= 0;
        this.cancelHold();
        if (quickTap) {
          this.down = true;
          this.submit(point.x, point.y, true, true);
          this.activePointer = -1;
          this.releaseTimer = setTimeout(() => {
            this.releaseTimer = -1;
            this.release();
          }, 100);
        } else {
          this.release();
        }
      } else if (event.type === TouchType.Cancel) {
        this.release();
      }
    })
    .onDisAppear(() => this.release())
  }
}
