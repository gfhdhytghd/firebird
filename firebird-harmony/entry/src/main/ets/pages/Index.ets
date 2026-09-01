import { common } from '@kit.AbilityKit';
import * as firebird from 'libfirebird_harmony.so';
import { EmulatorStatus, ValidationResult } from 'libfirebird_harmony.so';
import { FileStore, StoredConfiguration } from '../bridge/FileStore';
import { PhysicalKeyMap } from '../bridge/PhysicalKeyMap';
import { CalculatorKeypad } from '../components/CalculatorKeypad';
import { MobileDrawer } from '../components/MobileDrawer';
import { SettingsDrawer } from '../components/SettingsDrawer';

const EMPTY_STATUS: EmulatorStatus = {
  state: 'stopped', error: '', speed: 0, fps: 0,
  jitRequested: true, jitProbePassed: false, jitInitialized: false,
  translatedBlocks: 0, jitExecutionEntries: 0, product: 0, model: '',
  usbLinkConnected: false, transferProgress: -1,
  debuggerActive: false, debuggerWaitingForInput: false
};

@Entry
@Component
struct Index {
  @StorageLink('firebirdTopInsetPx') private topInsetPx: number = 0;
  // Mobile Firebird navigation order: Configuration <- Drawer <- Emulator.
  @State private mobilePage: number = 0;
  @State private landscape: boolean = false;
  @State private wideLayout: boolean = false;
  @State private jitEnabled: boolean = true;
  @State private status: EmulatorStatus = EMPTY_STATUS;
  @State private viewWidth: number = 1;
  @State private viewHeight: number = 1;
  private fileStore: FileStore = new FileStore(getContext(this) as common.UIAbilityContext);
  private physicalKeys: PhysicalKeyMap = new PhysicalKeyMap();
  private drawerPointer: number = -1;
  private drawerOriginX: number = 0;
  @State private drawerProgress: number = 0;
  @State private drawerDragging: boolean = false;
  @State private speedLimitMode: number = 1;
  @State private navigationSide: string = 'left';
  @State private splitRatio: number = 0.5;
  private splitPointer: number = -1;

  async aboutToAppear(): Promise<void> {
    this.fileStore.updateContext(this.getUIContext().getHostContext() as common.UIAbilityContext);
    firebird.subscribeStatus((status: EmulatorStatus): void => { this.status = status; });
    await this.fileStore.loadProfiles();
    await this.fileStore.installBundledImagesIfPresent();
    const configuration = await this.fileStore.loadConfiguration();
    this.jitEnabled = configuration.jitEnabled;
    const debuggerSettings = await this.fileStore.loadDebuggerSettings();
    await firebird.configureDebugger({
      gdbPort: debuggerSettings.gdbEnabled ? debuggerSettings.gdbPort : 0,
      remotePort: debuggerSettings.remoteEnabled ? debuggerSettings.remotePort : 0,
      debugOnStart: debuggerSettings.debugOnStart,
      debugOnWarn: debuggerSettings.debugOnWarn,
      printOnWarn: debuggerSettings.printOnWarn
    });
    if (this.jitEnabled) await firebird.probeJit();
    AppStorage.setOrCreate<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    AppStorage.set<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    try { await this.configureFiles(); } catch (_) {}
  }

  aboutToDisappear(): void {
    this.releaseAllInputs();
  }

  onBackPress(): boolean {
    if (this.mobilePage === 2) {
      this.returnToDrawer();
      return true;
    }
    if (this.mobilePage === 1 || this.drawerProgress > 0) {
      this.closeDrawer();
      return true;
    }
    return false;
  }

  private releaseAllInputs(): void {
    this.physicalKeys.releaseAll();
    firebird.releaseAllInputs();
  }

  private showMobilePage(page: number): void {
    this.releaseAllInputs();
    this.mobilePage = page;
  }

  private drawerWidth(): number { return Math.max(1, this.viewWidth * 0.62); }

  private closeDrawer(): void {
    this.releaseAllInputs();
    this.drawerDragging = false;
    this.drawerProgress = 0;
    setTimeout(() => {
      if (this.drawerProgress === 0 && this.mobilePage === 1) this.mobilePage = 0;
    }, 230);
  }

  private openConfiguration(): void {
    this.drawerProgress = 0;
    this.showMobilePage(2);
  }

  private returnToDrawer(): void {
    this.drawerProgress = 1;
    this.showMobilePage(1);
  }

  private async configureFiles(): Promise<void> {
    const configuration: StoredConfiguration = {
      bootPath: this.fileStore.bootPath(),
      flashPath: this.fileStore.flashPath(),
      jitEnabled: this.jitEnabled
    };
    await this.fileStore.saveConfiguration(configuration);
    if (!this.fileStore.bootReady() || !this.fileStore.flashReady())
      return;
    const validation: ValidationResult = await firebird.configure(configuration);
    const current: EmulatorStatus = firebird.getStatus();
    if (validation.valid && current.state !== 'running' && current.state !== 'paused' &&
        current.state !== 'starting') {
      const autosave = this.fileStore.autosavePath();
      await firebird.start('auto', this.fileStore.exists(autosave) ? autosave : undefined);
    }
  }

  private drawerPoint(event: TouchEvent): TouchObject | undefined {
    const changed = event.changedTouches.find((point: TouchObject): boolean => point.id === this.drawerPointer);
    if (changed !== undefined) return changed;
    return event.touches.find((point: TouchObject): boolean => point.id === this.drawerPointer);
  }

  private handleDrawerSwipe(event: TouchEvent): void {
    if (event.type === TouchType.Down && this.drawerPointer < 0 && event.changedTouches.length > 0) {
      this.drawerPointer = event.changedTouches[0].id;
      this.drawerOriginX = event.changedTouches[0].x;
      this.drawerDragging = true;
      this.drawerProgress = 0;
    } else if (event.type === TouchType.Move && this.drawerPointer >= 0) {
      const point = this.drawerPoint(event);
      if (point !== undefined) {
        this.drawerProgress = Math.min(1, Math.max(0,
          (point.x - this.drawerOriginX) / this.drawerWidth()));
      }
    } else if (event.type === TouchType.Up) {
      const openDrawer = this.drawerProgress >= 0.2;
      this.drawerPointer = -1;
      this.drawerDragging = false;
      if (openDrawer) {
        this.drawerProgress = 1;
        this.showMobilePage(1);
      } else {
        this.drawerProgress = 0;
      }
    } else if (event.type === TouchType.Cancel) {
      this.drawerPointer = -1;
      this.drawerDragging = false;
      this.drawerProgress = 0;
    }
  }

  private cycleSpeedLimit(): void {
    if (this.speedLimitMode === 1) {
      this.speedLimitMode = 2;
      firebird.setSpeedLimit(2);
    } else if (this.speedLimitMode === 2) {
      this.speedLimitMode = 0;
      firebird.setSpeedLimit(0);
    } else {
      this.speedLimitMode = 1;
      firebird.setSpeedLimit(1);
    }
  }

  private speedLimitLabel(): string {
    if (this.speedLimitMode === 2) return '200%';
    if (this.speedLimitMode === 0) return 'unlimited';
    return '100%';
  }

  private splitterWidth(): number { return 20; }

  private paneWidth(): number { return Math.max(1, this.viewWidth - this.splitterWidth()); }

  private leftPaneWidth(): number { return this.paneWidth() * this.splitRatio; }

  private rightPaneWidth(): number { return this.paneWidth() * (1 - this.splitRatio); }

  private leftInstrumentWidth(): number {
    const heightRatio = 3 / 4 + (this.navigationSide === 'left' ? 104 / 265 : 0);
    return Math.min(this.leftPaneWidth(), Math.max(1, (this.viewHeight - 36) / heightRatio));
  }

  private leftInstrumentHeight(): number {
    const width = this.leftInstrumentWidth();
    return width * 3 / 4 + 36 + (this.navigationSide === 'left' ? width * 104 / 265 : 0);
  }

  private rightInstrumentWidth(): number {
    const baseHeight = this.navigationSide === 'right' ? 340 : 236;
    return Math.min(this.rightPaneWidth(), Math.max(1, this.viewHeight * 265 / baseHeight));
  }

  private rightInstrumentHeight(): number {
    const baseHeight = this.navigationSide === 'right' ? 340 : 236;
    return this.rightInstrumentWidth() * baseHeight / 265;
  }

  private splitterPoint(event: TouchEvent): TouchObject | undefined {
    const changed = event.changedTouches.find((point: TouchObject): boolean => point.id === this.splitPointer);
    if (changed !== undefined) return changed;
    return event.touches.find((point: TouchObject): boolean => point.id === this.splitPointer);
  }

  private updateSplit(point: TouchObject): void {
    const ratio = (point.windowX - this.splitterWidth() / 2) / this.paneWidth();
    this.splitRatio = Math.min(0.7, Math.max(0.3, ratio));
  }

  private handleSplitterTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && this.splitPointer < 0 && event.changedTouches.length > 0) {
      this.splitPointer = event.changedTouches[0].id;
      this.updateSplit(event.changedTouches[0]);
    } else if (event.type === TouchType.Move && this.splitPointer >= 0) {
      const point = this.splitterPoint(event);
      if (point !== undefined) this.updateSplit(point);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.splitPointer = -1;
    }
  }

  @Builder
  private compactSpeedPanel() {
    Row() {
      Text(`Speed ${(this.status.speed * 100).toFixed(0)}%  ·  Limit ${this.speedLimitLabel()}`)
        .fontColor('#DDE6E8')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#303238')
    .onClick(() => this.cycleSpeedLimit())
  }

  @Builder
  private emulatorView() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        XComponent({
          id: 'firebirdLcd',
          type: XComponentType.SURFACE,
          libraryname: 'firebird_harmony'
        })
        .width('100%').height('100%').backgroundColor(Color.Black)
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => this.handleDrawerSwipe(event))
      }
      .width('100%')
      .aspectRatio(4 / 3)
      .clip(true)

      CalculatorKeypad({
        speed: this.status.speed,
        speedLimitMode: this.speedLimitMode,
        onCycleSpeedLimit: () => this.cycleSpeedLimit()
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#303238')
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.wideLayout) {
        Row() {
          Column() {
            Blank().layoutWeight(1)
            Column() {
              Stack({ alignContent: Alignment.Start }) {
                XComponent({ id: 'firebirdLcdLandscape', type: XComponentType.SURFACE,
                  libraryname: 'firebird_harmony' })
                  .width('100%').height('100%').backgroundColor(Color.Black)
                Row()
                  .width('100%')
                  .height('100%')
                  .backgroundColor('#00000000')
                  .hitTestBehavior(HitTestMode.Block)
                  .onTouch((event: TouchEvent) => this.handleDrawerSwipe(event))
              }.width('100%').aspectRatio(4 / 3).clip(true)
              this.compactSpeedPanel()
              if (this.navigationSide === 'left') {
                CalculatorKeypad({
                  layoutMode: 'navigation',
                  showSpeed: false,
                  navigationSide: this.navigationSide,
                  speed: this.status.speed,
                  speedLimitMode: this.speedLimitMode,
                  onCycleSpeedLimit: () => this.cycleSpeedLimit(),
                  onMoveNavigation: (side: string) => { this.navigationSide = side; }
                }).width('100%').aspectRatio(265 / 104)
              }
            }
            .width(this.leftInstrumentWidth())
            .height(this.leftInstrumentHeight())
            Blank().layoutWeight(1)
          }.width(this.leftPaneWidth()).height('100%')
          Row() {
            Divider().vertical(true).width(2).height(44).color('#899096')
          }
          .width(this.splitterWidth())
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor('#25282D')
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => this.handleSplitterTouch(event))
          Column() {
            Blank().layoutWeight(1)
            Column() {
              if (this.navigationSide === 'right') {
                CalculatorKeypad({
                  layoutMode: 'navigation',
                  showSpeed: false,
                  navigationSide: this.navigationSide,
                  speed: this.status.speed,
                  speedLimitMode: this.speedLimitMode,
                  onCycleSpeedLimit: () => this.cycleSpeedLimit(),
                  onMoveNavigation: (side: string) => { this.navigationSide = side; }
                }).width('100%').aspectRatio(265 / 104)
              }
              CalculatorKeypad({
                layoutMode: 'main',
                speed: this.status.speed,
                speedLimitMode: this.speedLimitMode,
                onCycleSpeedLimit: () => this.cycleSpeedLimit()
              }).width('100%').aspectRatio(265 / 236)
            }
            .width(this.rightInstrumentWidth())
            .height(this.rightInstrumentHeight())
            Blank().layoutWeight(1)
          }.layoutWeight(1).height('100%')
        }.width('100%').height('100%').backgroundColor('#303238')
      } else {
        this.emulatorView()
      }

      if (this.mobilePage === 2) {
        Row() {
          SettingsDrawer({
            status: $status,
            jitEnabled: $jitEnabled,
            fileStore: this.fileStore,
            onFilesChanged: async () => { await this.configureFiles(); },
            onClose: () => { this.returnToDrawer(); }
          }).width('100%')
        }.width('100%').height('100%')
      } else {
        Row() {
          MobileDrawer({
            status: $status,
            fileStore: this.fileStore,
            onOpenConfiguration: () => { this.openConfiguration(); },
            onClose: () => { this.closeDrawer(); }
          })
            .width('62%')
            .translate({ x: -this.drawerWidth() * (1 - this.drawerProgress) })
            .animation({ duration: this.drawerDragging ? 0 : 220, curve: Curve.EaseOut })
          Blank()
            .backgroundColor('#66000000')
            .opacity(this.drawerProgress)
            .hitTestBehavior(this.mobilePage === 1 ? HitTestMode.Default : HitTestMode.None)
            .onClick(() => this.closeDrawer())
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(this.mobilePage === 1 ? HitTestMode.Default : HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: px2vp(this.topInsetPx) })
    .backgroundColor(Color.Black)
    .focusable(true)
    .defaultFocus(true)
    .onBlur(() => this.releaseAllInputs())
    .onKeyEvent((event: KeyEvent) => this.physicalKeys.handle(event))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
      this.viewHeight = Number(newArea.height);
      this.landscape = this.viewWidth > this.viewHeight;
      this.wideLayout = this.landscape || this.viewWidth >= 600;
    })
  }
}
