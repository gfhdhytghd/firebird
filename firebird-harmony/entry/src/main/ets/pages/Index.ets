import { common } from '@kit.AbilityKit';
import * as firebird from 'libfirebird_harmony.so';
import { EmulatorStatus, ValidationResult } from 'libfirebird_harmony.so';
import { FileStore, StoredConfiguration } from '../bridge/FileStore';
import { PhysicalKeyMap } from '../bridge/PhysicalKeyMap';
import { CalculatorKeypad } from '../components/CalculatorKeypad';
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
  @State private drawerOpen: boolean = false;
  @State private landscape: boolean = false;
  @State private jitEnabled: boolean = true;
  @State private status: EmulatorStatus = EMPTY_STATUS;
  @State private viewWidth: number = 1;
  @State private viewHeight: number = 1;
  private fileStore: FileStore = new FileStore(getContext(this) as common.UIAbilityContext);
  private physicalKeys: PhysicalKeyMap = new PhysicalKeyMap();
  private drawerPointer: number = -1;
  private drawerOriginX: number = 0;
  @State private speedLimitMode: number = 1;

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
    this.physicalKeys.releaseAll();
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

  @Builder
  private drawerHandle() {
    Row() {
      Text('›').fontColor(Color.White).fontSize(24)
    }
    .width(18)
    .height('100%')
    .backgroundColor(Color.Black)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.drawerOpen = true)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && this.drawerPointer < 0 && event.changedTouches.length > 0) {
        this.drawerPointer = event.changedTouches[0].id;
        this.drawerOriginX = event.changedTouches[0].x;
      } else if (event.type === TouchType.Move && this.drawerPointer >= 0) {
        const point = this.drawerPoint(event);
        if (point !== undefined && point.x - this.drawerOriginX > 10) {
          this.drawerOpen = true;
          this.drawerPointer = -1;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.drawerPointer = -1;
      }
    })
  }

  @Builder
  private emulatorView() {
    Column() {
      Row() {
        this.drawerHandle()
        XComponent({
          id: 'firebirdLcd',
          type: XComponentType.SURFACE,
          libraryname: 'firebird_harmony'
        })
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(Color.Black)
      }
      .width('100%')
      .aspectRatio(4 / 3)

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
      if (this.landscape) {
        Row() {
          Row() {
            this.drawerHandle()
            XComponent({ id: 'firebirdLcdLandscape', type: XComponentType.SURFACE,
              libraryname: 'firebird_harmony' })
              .layoutWeight(1).height('100%').backgroundColor(Color.Black)
          }.layoutWeight(1).height('100%')
          CalculatorKeypad({
            speed: this.status.speed,
            speedLimitMode: this.speedLimitMode,
            onCycleSpeedLimit: () => this.cycleSpeedLimit()
          }).width('48%').height('100%')
        }.width('100%').height('100%').backgroundColor('#303238')
      } else {
        this.emulatorView()
      }

      if (this.drawerOpen) {
        Row() {
          SettingsDrawer({
            status: $status,
            jitEnabled: $jitEnabled,
            fileStore: this.fileStore,
            onFilesChanged: async () => { await this.configureFiles(); },
            onClose: () => { this.drawerOpen = false; }
          }).width('84%')
          Blank()
            .backgroundColor('#66000000')
            .onClick(() => this.drawerOpen = false)
        }.width('100%').height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: px2vp(this.topInsetPx) })
    .backgroundColor(Color.Black)
    .focusable(true)
    .defaultFocus(true)
    .onBlur(() => this.physicalKeys.releaseAll())
    .onKeyEvent((event: KeyEvent) => this.physicalKeys.handle(event))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
      this.viewHeight = Number(newArea.height);
      this.landscape = this.viewWidth > this.viewHeight;
    })
  }
}
