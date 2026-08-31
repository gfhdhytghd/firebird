import * as firebird from 'libfirebird_harmony.so';

@Component
export struct Touchpad {
  @State private activePointer: number = -1;
  @State private originX: number = 0;
  @State private originY: number = 0;
  @State private down: boolean = false;
  private holdTimer: number = -1;
  private widthPx: number = 1;
  private heightPx: number = 1;

  private cancelHold(): void {
    if (this.holdTimer >= 0) {
      clearTimeout(this.holdTimer);
      this.holdTimer = -1;
    }
  }

  private submit(x: number, y: number, contact: boolean, down: boolean): void {
    firebird.setTouchpadState(
      Math.max(0, Math.min(1, x / this.widthPx)),
      Math.max(0, Math.min(1, y / this.heightPx)),
      contact,
      down
    );
  }

  private release(): void {
    this.cancelHold();
    this.activePointer = -1;
    this.down = false;
    firebird.setTouchpadState(0.5, 0.5, false, false);
  }

  private findPoint(event: TouchEvent): TouchObject | undefined {
    const allPoints = event.touches.concat(event.changedTouches);
    return allPoints.find((candidate: TouchObject) => candidate.id === this.activePointer);
  }

  build() {
    Stack() {
      Text('TOUCHPAD')
        .fontColor('#82969E')
        .fontSize(10)
    }
    .width('100%')
    .height(76)
    .backgroundColor('#111315')
    .border({ width: 2, color: '#D8E0E2', radius: 12 })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.widthPx = Number(newArea.width);
      this.heightPx = Number(newArea.height);
    })
    .onTouch((event: TouchEvent) => {
      const changedPoint = event.changedTouches.length > 0 ? event.changedTouches[0] : undefined;
      const point = this.activePointer >= 0 ? this.findPoint(event) : changedPoint;
      if (event.type === TouchType.Down && this.activePointer < 0 && point) {
        this.activePointer = point.id;
        this.originX = point.x;
        this.originY = point.y;
        this.down = false;
        this.submit(point.x, point.y, true, false);
        this.holdTimer = setTimeout(() => {
          this.down = true;
          this.submit(point.x, point.y, true, true);
        }, 200);
      } else if (event.type === TouchType.Move && point && point.id === this.activePointer) {
        if (Math.abs(point.x - this.originX) > 5 || Math.abs(point.y - this.originY) > 5)
          this.cancelHold();
        this.submit(point.x, point.y, true, this.down);
      } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) &&
                 this.activePointer >= 0) {
        const quickTap = this.holdTimer >= 0;
        this.cancelHold();
        const releasedPoint = this.findPoint(event);
        if (quickTap && releasedPoint) {
          this.submit(releasedPoint.x, releasedPoint.y, true, true);
          setTimeout(() => this.release(), 100);
        } else {
          this.release();
        }
      }
    })
    .onDisAppear(() => this.release())
  }
}
