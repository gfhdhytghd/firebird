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
  translatedBlocks: 0, jitExecutionEntries: 0, product: 0, model: ''
};

@Entry
@Component
struct Index {
  @State private drawerOpen: boolean = false;
  @State private landscape: boolean = false;
  @State private jitEnabled: boolean = true;
  @State private status: EmulatorStatus = EMPTY_STATUS;
  private fileStore: FileStore = new FileStore(getContext(this) as common.UIAbilityContext);
  private physicalKeys: PhysicalKeyMap = new PhysicalKeyMap();

  async aboutToAppear(): Promise<void> {
    firebird.subscribeStatus((status: EmulatorStatus): void => { this.status = status; });
    await this.fileStore.installBundledImagesIfPresent();
    const configuration = await this.fileStore.loadConfiguration();
    this.jitEnabled = configuration.jitEnabled;
    if (this.jitEnabled) await firebird.probeJit();
    AppStorage.setOrCreate<string>('firebirdAutosavePath', this.fileStore.autosavePath());
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

  @Builder
  private emulatorView() {
    Column() {
      XComponent({
        id: 'firebirdLcd',
        type: XComponentType.SURFACE,
        libraryname: 'firebird_harmony'
      })
      .aspectRatio(4 / 3)
      .backgroundColor(Color.Black)
      .width('100%')

      CalculatorKeypad()
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
          XComponent({ id: 'firebirdLcdLandscape', type: XComponentType.SURFACE,
            libraryname: 'firebird_harmony' })
            .layoutWeight(1).aspectRatio(4 / 3).backgroundColor(Color.Black)
          CalculatorKeypad().width('48%').height('100%')
        }.width('100%').height('100%').backgroundColor('#303238')
      } else {
        this.emulatorView()
      }

      Row() {
        Text('›').fontColor(Color.White).fontSize(24)
      }
      .width(18)
      .height('100%')
      .backgroundColor(Color.Black)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.drawerOpen = true)

      if (this.drawerOpen) {
        Row() {
          SettingsDrawer({
            status: $status,
            jitEnabled: $jitEnabled,
            fileStore: this.fileStore,
            onFilesChanged: async () => { await this.configureFiles(); }
          }).width('84%')
          Blank()
            .backgroundColor('#66000000')
            .onClick(() => this.drawerOpen = false)
        }.width('100%').height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .focusable(true)
    .defaultFocus(true)
    .onBlur(() => this.physicalKeys.releaseAll())
    .onKeyEvent((event: KeyEvent) => this.physicalKeys.handle(event))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.landscape = Number(newArea.width) > Number(newArea.height);
    })
  }
}
