import * as firebird from 'libfirebird_harmony.so';
import { EmulatorStatus, SnapshotInfo, ValidationResult } from 'libfirebird_harmony.so';
import { DebuggerSettings, FileStore, FirebirdProfile, TransferFile } from '../bridge/FileStore';

const PANEL_BG: string = '#111315';
const CARD_BG: string = '#20242A';
const ACTIVE: string = '#5CC8D7';
const MUTED: string = '#9AA3AD';

@Component
export struct SettingsDrawer {
  @Link status: EmulatorStatus;
  @Link jitEnabled: boolean;
  @Prop fileStore: FileStore;
  onFilesChanged: () => Promise<void> = async () => {};
  onClose: () => void = () => {};
  @State private currentTab: number = 0;
  @State private snapshots: Array<string> = [];
  @State private profiles: Array<FirebirdProfile> = [];
  @State private activeProfileId: string = 'default';
  @State private profileName: string = '';
  @State private renameValue: string = '';
  @State private transferDirectory: string = '/ndless';
  @State private transferFilePath: string = '';
  @State private transferFileName: string = '';
  @State private gdbEnabled: boolean = false;
  @State private gdbPortText: string = '3333';
  @State private remoteEnabled: boolean = false;
  @State private remotePortText: string = '3334';
  @State private debugOnStart: boolean = false;
  @State private debugOnWarn: boolean = false;
  @State private printOnWarn: boolean = true;
  @State private debugCommand: string = '';
  @State private debugLog: string = '';

  aboutToAppear(): void {
    this.refreshProfiles(); this.refreshSnapshots(); this.loadDebuggerSettings();
  }
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
  private refreshProfiles(): void {
    this.profiles = this.fileStore.getProfiles();
    this.activeProfileId = this.fileStore.getActiveProfileId();
  }
  private refreshSnapshots(): void { this.snapshots = this.fileStore.listSnapshots(); }
  private async run(action: () => Promise<void>): Promise<void> {
    try { await action(); }
    catch (error) { this.toast(error instanceof Error ? error.message : JSON.stringify(error)); }
  }
  private requireImages(): void {
    if (!this.fileStore.bootReady() || !this.fileStore.flashReady())
      throw new Error('Import Boot1 and Flash for the selected profile first');
  }
  private async selectProfile(id: string): Promise<void> {
    if (id === this.activeProfileId) return;
    await firebird.stop();
    await this.fileStore.selectProfile(id);
    AppStorage.setOrCreate<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    AppStorage.set<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    this.refreshProfiles();
    await this.onFilesChanged();
  }
  private async createProfile(): Promise<void> {
    await firebird.stop();
    await this.fileStore.createProfile(this.profileName);
    this.profileName = '';
    AppStorage.setOrCreate<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    AppStorage.set<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    this.refreshProfiles();
    await this.onFilesChanged();
  }
  private async renameProfile(): Promise<void> {
    await this.fileStore.renameActiveProfile(this.profileName);
    this.profileName = ''; this.refreshProfiles();
  }
  private async deleteProfile(): Promise<void> {
    await firebird.stop();
    await this.fileStore.deleteActiveProfile();
    AppStorage.setOrCreate<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    AppStorage.set<string>('firebirdAutosavePath', this.fileStore.autosavePath());
    this.refreshProfiles(); await this.onFilesChanged();
  }
  private async replaceBoot(): Promise<void> {
    const candidate = await this.fileStore.importBoot();
    let committed: boolean = false;
    try {
      if (!this.fileStore.bootCandidateReady(candidate)) throw new Error('Boot1 must be exactly 512 KiB');
      if (this.fileStore.flashReady()) {
        const validation: ValidationResult = await firebird.validateFiles(candidate, this.fileStore.flashPath());
        if (!validation.valid) throw new Error(validation.error);
      }
      await firebird.stop();
      this.fileStore.commitBoot(candidate); committed = true;
      this.fileStore.invalidateAutosave(); await this.onFilesChanged(); this.toast('Boot1 imported');
    } finally { if (!committed) this.fileStore.discardCandidate(candidate); }
  }
  private async replaceFlash(): Promise<void> {
    const candidate = await this.fileStore.importFlash();
    let committed: boolean = false;
    try {
      if (!this.fileStore.flashCandidateReady(candidate)) throw new Error('CX II Flash must be exactly 132 MiB');
      if (this.fileStore.bootReady()) {
        const validation: ValidationResult = await firebird.validateFiles(this.fileStore.bootPath(), candidate);
        if (!validation.valid) throw new Error(validation.error);
      }
      await firebird.stop();
      this.fileStore.commitFlash(candidate); committed = true;
      this.fileStore.invalidateAutosave(); await this.onFilesChanged(); this.toast('Flash imported');
    } finally { if (!committed) this.fileStore.discardCandidate(candidate); }
  }
  private async saveNamedSnapshot(): Promise<void> {
    const name = `snapshot-${new Date().toISOString().replace(/[:.]/g, '-')}.snapshot`;
    await firebird.saveSnapshot(this.fileStore.snapshotPath(name));
    this.refreshSnapshots(); this.toast('Snapshot saved');
  }
  private async chooseTransferFile(): Promise<void> {
    const selected: TransferFile = await this.fileStore.importTransferFile();
    this.transferFilePath = selected.path; this.transferFileName = selected.name;
  }
  private sendTransferFile(): void {
    if (this.transferFilePath.length === 0) throw new Error('Choose a file first');
    const folder = this.transferDirectory.endsWith('/') ? this.transferDirectory.slice(0, -1) : this.transferDirectory;
    firebird.sendFile(this.transferFilePath, `${folder}/${this.transferFileName}`);
  }
  private async loadDebuggerSettings(): Promise<void> {
    const settings: DebuggerSettings = await this.fileStore.loadDebuggerSettings();
    this.gdbEnabled = settings.gdbEnabled;
    this.gdbPortText = settings.gdbPort.toString();
    this.remoteEnabled = settings.remoteEnabled;
    this.remotePortText = settings.remotePort.toString();
    this.debugOnStart = settings.debugOnStart;
    this.debugOnWarn = settings.debugOnWarn;
    this.printOnWarn = settings.printOnWarn;
    this.debugLog = firebird.getDebugLog();
  }
  private async applyDebuggerSettings(): Promise<void> {
    const gdbPort = Number(this.gdbPortText);
    const remotePort = Number(this.remotePortText);
    if (!Number.isInteger(gdbPort) || gdbPort < 1 || gdbPort > 65535 ||
        !Number.isInteger(remotePort) || remotePort < 1 || remotePort > 65535)
      throw new Error('Debugger ports must be between 1 and 65535');
    const settings: DebuggerSettings = {
      gdbEnabled: this.gdbEnabled, gdbPort: gdbPort,
      remoteEnabled: this.remoteEnabled, remotePort: remotePort,
      debugOnStart: this.debugOnStart, debugOnWarn: this.debugOnWarn,
      printOnWarn: this.printOnWarn
    };
    await firebird.stop();
    await firebird.configureDebugger({
      gdbPort: settings.gdbEnabled ? settings.gdbPort : 0,
      remotePort: settings.remoteEnabled ? settings.remotePort : 0,
      debugOnStart: settings.debugOnStart,
      debugOnWarn: settings.debugOnWarn,
      printOnWarn: settings.printOnWarn
    });
    await this.fileStore.saveDebuggerSettings(settings);
    this.toast('Debugger settings saved; start the emulator to apply listeners');
  }

  @Builder private sectionTitle(title: string, detail: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Color.White)
      if (detail.length > 0) Text(detail).fontSize(12).fontColor(MUTED)
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 8, bottom: 6 })
  }
  @Builder private tabButton(title: string, index: number) {
    Column({ space: 5 }) {
      Text(title).fontSize(12).fontColor(this.currentTab === index ? Color.White : MUTED)
      Divider().height(2).color(this.currentTab === index ? ACTIVE : Color.Transparent)
    }.layoutWeight(1).padding({ top: 10 }).onClick(() => this.currentTab = index)
  }
  @Builder private imageStatus(label: string, ready: boolean) {
    Row() {
      Text(label).fontColor(Color.White).layoutWeight(1)
      Text(ready ? 'Ready' : 'Missing').fontSize(12).fontColor(ready ? ACTIVE : '#FF8A80')
    }.width('100%').padding(10).backgroundColor(CARD_BG).borderRadius(5)
  }

  @Builder private configTab() {
    Column({ space: 8 }) {
      this.sectionTitle('Flash & Boot1', 'Profiles keep calculator images and autosaves separate.')
      Text(`Active profile · ${this.fileStore.getActiveProfileName()}`).fontColor(ACTIVE).fontSize(13)
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.profiles, (profile: FirebirdProfile) => {
            Button(profile.name).fontSize(12)
              .fontColor(profile.id === this.activeProfileId ? '#111315' : Color.White)
              .backgroundColor(profile.id === this.activeProfileId ? ACTIVE : CARD_BG)
              .onClick(() => this.run(async () => await this.selectProfile(profile.id)))
          }, (profile: FirebirdProfile) => profile.id)
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
      Row({ space: 6 }) {
        TextInput({ text: this.profileName, placeholder: 'New profile name' })
          .onChange((value: string) => this.profileName = value).layoutWeight(1)
        Button('Add').onClick(() => this.run(async () => await this.createProfile()))
      }.width('100%')
      Row({ space: 6 }) {
        Button('Rename active').layoutWeight(1)
          .onClick(() => this.run(async () => await this.renameProfile()))
        Button('Remove active').layoutWeight(1).enabled(this.activeProfileId !== 'default')
          .onClick(() => this.run(async () => await this.deleteProfile()))
      }.width('100%')
      this.imageStatus('Boot1 ROM', this.fileStore.bootReady())
      this.imageStatus('Flash image', this.fileStore.flashReady())
      Button('Import / Replace Boot1').width('100%').onClick(() => this.run(async () => await this.replaceBoot()))
      Button('Import / Replace Flash').width('100%').onClick(() => this.run(async () => await this.replaceFlash()))

      this.sectionTitle('Snapshot', 'Model and Boot1/Flash fingerprints are validated before load.')
      Row({ space: 6 }) {
        Button('Save').layoutWeight(1).onClick(() => this.run(async () => await this.saveNamedSnapshot()))
        Button('Import').layoutWeight(1).onClick(() => this.run(async () => {
          const path = await this.fileStore.importSnapshot();
          const info: SnapshotInfo = await firebird.inspectSnapshot(path);
          if (!info.valid) throw new Error(info.error);
          if (!info.harmonyFormat) this.toast('Desktop v3 snapshot uses this profile\'s matching images');
          await firebird.loadSnapshot(path); this.refreshSnapshots();
        }))
      }.width('100%')
      ForEach(this.snapshots, (name: string) => {
        Column({ space: 5 }) {
          Text(name).fontColor(Color.White).fontSize(11).maxLines(1)
          Row({ space: 4 }) {
            Button('Load').fontSize(11).onClick(() => this.run(async () =>
              await firebird.loadSnapshot(this.fileStore.snapshotPath(name))))
            Button('Export').fontSize(11).onClick(() => this.run(async () =>
              await this.fileStore.exportSnapshot(name)))
            Button('Delete').fontSize(11).onClick(() => {
              this.fileStore.deleteSnapshot(name); this.refreshSnapshots();
            })
          }
          Row({ space: 4 }) {
            TextInput({ text: this.renameValue, placeholder: 'Rename snapshot' })
              .onChange((value: string) => this.renameValue = value).layoutWeight(1)
            Button('Rename').fontSize(11).onClick(() => this.run(async () => {
              if (this.renameValue.length === 0) throw new Error('Enter a snapshot name');
              this.fileStore.renameSnapshot(name, this.renameValue); this.renameValue = ''; this.refreshSnapshots();
            }))
          }.width('100%')
        }.width('100%').padding(9).backgroundColor(CARD_BG).borderRadius(5).alignItems(HorizontalAlign.Start)
      }, (name: string) => name)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private emulatorTab() {
    Column({ space: 8 }) {
      this.sectionTitle('Emulator', 'Start, resume, reset, and tune the selected profile.')
      Row({ space: 5 }) {
        Button('Start').layoutWeight(1).onClick(() => this.run(async () => {
          this.requireImages(); await firebird.start('cold');
        }))
        Button('Resume').layoutWeight(1).onClick(() => this.run(async () => {
          this.requireImages(); const autosave = this.fileStore.autosavePath();
          if (!this.fileStore.exists(autosave)) throw new Error('No autosave for this profile');
          await firebird.start('snapshot', autosave);
        }))
      }.width('100%')
      Row({ space: 5 }) {
        Button('Reset').layoutWeight(1).onClick(() => this.run(async () => {
          this.requireImages(); this.fileStore.invalidateAutosave(); await firebird.restartCold();
        }))
        Button('Stop').layoutWeight(1).onClick(() => this.run(async () => await firebird.stop()))
        Button(this.status.state === 'paused' ? 'Continue' : 'Pause').layoutWeight(1).onClick(() => {
          if (this.status.state === 'paused') firebird.resume(); else firebird.pause();
        })
      }.width('100%')
      Row() {
        Text('Enable AArch64 JIT').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.jitEnabled }).onChange((enabled: boolean) => {
          this.run(async () => { this.jitEnabled = enabled; await firebird.stop(); await this.onFilesChanged(); });
        })
      }.width('100%').padding(10).backgroundColor(CARD_BG).borderRadius(5)
      this.sectionTitle('Live status', '')
      Text(`State · ${this.status.state}`).fontColor(Color.White)
      Text(`Model · ${this.status.model || 'Unknown'}`).fontColor(Color.White)
      Text(`Speed · ${(this.status.speed * 100).toFixed(0)}%    FPS · ${this.status.fps.toFixed(0)}`).fontColor(Color.White)
      Text(`JIT · ${this.status.jitExecutionEntries > 0 ? 'Running' :
        (this.status.jitInitialized ? 'Initialized' : 'Not running')}`).fontColor(Color.White)
      Text(`Translated ${this.status.translatedBlocks} · Entries ${this.status.jitExecutionEntries}`)
        .fontSize(12).fontColor(MUTED)
      if (this.status.error.length > 0) Text(this.status.error).fontColor('#FF8A80').fontSize(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private transferTab() {
    Column({ space: 8 }) {
      this.sectionTitle('File Transfer', 'Send documents to the running calculator over its emulated USB link.')
      TextInput({ text: this.transferDirectory, placeholder: '/ndless' })
        .onChange((value: string) => this.transferDirectory = value).width('100%')
      Button(this.transferFileName.length > 0 ? this.transferFileName : 'Choose file')
        .width('100%').onClick(() => this.run(async () => await this.chooseTransferFile()))
      Button('Send file').width('100%').onClick(() => this.run(async () => this.sendTransferFile()))
      Button('Leave Press-to-Test mode').width('100%').onClick(() => firebird.exitPressToTest())
      this.sectionTitle('Transfer status', '')
      Text(`USB Link · ${this.status.usbLinkConnected ? 'Connected' : 'Waiting'}`)
        .fontColor(this.status.usbLinkConnected ? ACTIVE : MUTED)
      Text(this.status.transferProgress < 0 ? 'Idle' :
        (this.status.transferProgress >= 100 ? 'Done' : `${this.status.transferProgress}%`)).fontColor(Color.White)
      Progress({ value: Math.max(0, this.status.transferProgress), total: 100,
        type: ProgressType.Linear }).width('100%').color(ACTIVE)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private debuggerTab() {
    Column({ space: 8 }) {
      this.sectionTitle('Remote GDB', 'Connect through an hdc-forwarded loopback port.')
      Row() {
        Text('Enable GDB stub').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.gdbEnabled })
          .onChange((value: boolean) => this.gdbEnabled = value)
      }.width('100%').padding(9).backgroundColor(CARD_BG).borderRadius(5)
      TextInput({ text: this.gdbPortText, placeholder: '3333' })
        .type(InputType.Number).onChange((value: string) => this.gdbPortText = value).width('100%')

      this.sectionTitle('Internal debugger', 'Use Firebird commands locally or over its remote console.')
      Row() {
        Text('Enable remote console').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remoteEnabled })
          .onChange((value: boolean) => this.remoteEnabled = value)
      }.width('100%').padding(9).backgroundColor(CARD_BG).borderRadius(5)
      TextInput({ text: this.remotePortText, placeholder: '3334' })
        .type(InputType.Number).onChange((value: string) => this.remotePortText = value).width('100%')
      Row() {
        Text('Enter debugger on startup').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.debugOnStart })
          .onChange((value: boolean) => this.debugOnStart = value)
      }.width('100%')
      Row() {
        Text('Enter on warnings / errors').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.debugOnWarn })
          .onChange((value: boolean) => this.debugOnWarn = value)
      }.width('100%')
      Row() {
        Text('Print warning messages').fontColor(Color.White).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.printOnWarn })
          .enabled(!this.debugOnWarn).onChange((value: boolean) => this.printOnWarn = value)
      }.width('100%')
      Button('Save debugger settings').width('100%')
        .onClick(() => this.run(async () => await this.applyDebuggerSettings()))

      this.sectionTitle('Debugger console', this.status.debuggerActive ?
        (this.status.debuggerWaitingForInput ? 'Waiting for command' : 'Active') : 'Not active')
      Row({ space: 5 }) {
        Button('Break').onClick(() => firebird.enterDebugger())
        Button('Refresh').onClick(() => this.debugLog = firebird.getDebugLog())
      }
      Text(this.debugLog.length > 0 ? this.debugLog : 'No debugger output yet')
        .fontSize(10).fontColor('#D8DEE9').fontFamily('monospace').width('100%')
        .padding(8).backgroundColor('#08090B')
      Row({ space: 5 }) {
        TextInput({ text: this.debugCommand, placeholder: 'Command, e.g. c' })
          .onChange((value: string) => this.debugCommand = value).layoutWeight(1)
        Button('Send').onClick(() => {
          if (this.debugCommand.length > 0) {
            firebird.sendDebuggerCommand(this.debugCommand); this.debugCommand = '';
          }
        })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Button('‹ Menu').fontSize(13).fontColor(ACTIVE).backgroundColor(Color.Transparent)
          .onClick(() => this.onClose())
        Column({ space: 1 }) {
          Text('Configuration').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text(this.fileStore.getActiveProfileName()).fontSize(11).fontColor(ACTIVE)
        }.alignItems(HorizontalAlign.End).layoutWeight(1)
      }.width('100%').padding({ left: 14, right: 8, top: 12, bottom: 6 })
      Row() {
        this.tabButton('Config', 0); this.tabButton('Emulator', 1)
        this.tabButton('Transfer', 2); this.tabButton('Debugger', 3)
      }.width('100%').backgroundColor('#171A1F')
      Scroll() {
        if (this.currentTab === 0) this.configTab()
        else if (this.currentTab === 1) this.emulatorTab()
        else if (this.currentTab === 2) this.transferTab()
        else this.debuggerTab()
      }.layoutWeight(1).width('100%').padding({ left: 14, right: 14, bottom: 18 })
    }.width('100%').height('100%').backgroundColor(PANEL_BG)
  }
}
