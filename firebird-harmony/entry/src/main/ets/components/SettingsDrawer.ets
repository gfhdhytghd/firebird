import * as firebird from 'libfirebird_harmony.so';
import { EmulatorStatus, SnapshotInfo, ValidationResult } from 'libfirebird_harmony.so';
import { FileStore } from '../bridge/FileStore';

@Component
export struct SettingsDrawer {
  @Link status: EmulatorStatus;
  @Link jitEnabled: boolean;
  @Prop fileStore: FileStore;
  onFilesChanged: () => Promise<void> = async () => {};
  @State private snapshots: Array<string> = [];
  @State private renameValue: string = '';

  aboutToAppear(): void { this.refreshSnapshots(); }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private refreshSnapshots(): void {
    this.snapshots = this.fileStore.listSnapshots();
  }

  private async saveNamedSnapshot(): Promise<void> {
    const name = `snapshot-${new Date().toISOString().replace(/[:.]/g, '-')}.snapshot`;
    try {
      await firebird.saveSnapshot(this.fileStore.snapshotPath(name));
      this.refreshSnapshots();
      this.toast('Snapshot saved');
    } catch (error) {
      this.toast(`Snapshot failed: ${error}`);
    }
  }

  private async replaceBoot(): Promise<void> {
    const candidate = await this.fileStore.importBoot();
    let committed: boolean = false;
    try {
      if (!this.fileStore.bootCandidateReady(candidate))
        throw new Error('Boot ROM must be exactly 512 KiB');
      if (this.fileStore.flashReady()) {
        const validation: ValidationResult = await firebird.validateFiles(candidate, this.fileStore.flashPath());
        if (!validation.valid) throw new Error(validation.error);
      }
      await firebird.stop();
      this.fileStore.commitBoot(candidate);
      committed = true;
      this.fileStore.invalidateAutosave();
      await this.onFilesChanged();
      this.toast('Boot ROM replaced');
    } finally { if (!committed) this.fileStore.discardCandidate(candidate); }
  }

  private async replaceFlash(): Promise<void> {
    const candidate = await this.fileStore.importFlash();
    let committed: boolean = false;
    try {
      if (!this.fileStore.flashCandidateReady(candidate))
        throw new Error('Flash image must be exactly 132 MiB');
      if (this.fileStore.bootReady()) {
        const validation: ValidationResult = await firebird.validateFiles(this.fileStore.bootPath(), candidate);
        if (!validation.valid) throw new Error(validation.error);
      }
      await firebird.stop();
      this.fileStore.commitFlash(candidate);
      committed = true;
      this.fileStore.invalidateAutosave();
      await this.onFilesChanged();
      this.toast('Flash replaced');
    } finally { if (!committed) this.fileStore.discardCandidate(candidate); }
  }

  private async run(action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch (error) {
      if (error instanceof Error) {
        this.toast(error.message);
      } else {
        this.toast(JSON.stringify(error));
      }
    }
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('FIREBIRD').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
        Text(`State: ${this.status.state}`).fontColor(Color.White)
        Text(`Boot ROM: ${this.fileStore.bootReady() ? 'ready' : 'missing'}`)
          .fontColor(Color.White)
        Text(`Flash: ${this.fileStore.flashReady() ? 'ready' : 'missing'}`)
          .fontColor(Color.White)
        Text(`Model: ${this.status.model || 'unknown'}`).fontColor(Color.White)
        Text(`Speed: ${(this.status.speed * 100).toFixed(0)}%`).fontColor(Color.White)
        Text(`JIT probe: ${this.status.jitProbePassed ? 'passed' : 'not passed'}`).fontColor(Color.White)
        Text(`JIT: ${this.status.jitExecutionEntries > 0 ? 'running' :
          (this.status.jitInitialized ? 'initialized' : 'not running')}`).fontColor(Color.White)
        Text(`JIT blocks: ${this.status.jitExecutionEntries}`).fontColor(Color.White)

        Row() {
          Text('Enable AArch64 JIT').fontColor(Color.White).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.jitEnabled })
            .onChange(async (enabled: boolean) => {
              await this.run(async () => {
                this.jitEnabled = enabled;
                await firebird.stop();
                await this.onFilesChanged();
              });
            })
        }.width('100%')

        Button('Import / Replace Boot ROM').onClick(async () => {
          await this.run(async () => await this.replaceBoot());
        }).width('100%')
        Button('Import / Replace Flash').onClick(async () => {
          await this.run(async () => await this.replaceFlash());
        }).width('100%')
        Button('Import desktop snapshot').onClick(async () => {
          await this.run(async () => {
            const path = await this.fileStore.importSnapshot();
            const info: SnapshotInfo = await firebird.inspectSnapshot(path);
            if (!info.valid) throw new Error(info.error);
            if (!info.harmonyFormat)
              this.toast('Desktop v3 snapshot uses the currently selected matching boot and flash');
            await firebird.loadSnapshot(path);
            this.refreshSnapshots();
          });
        }).width('100%')

        Row({ space: 6 }) {
          Button('Start').onClick(() => this.run(async () => await firebird.start('auto',
            this.fileStore.exists(this.fileStore.autosavePath()) ? this.fileStore.autosavePath() : undefined)))
          Button('Stop').onClick(() => this.run(async () => await firebird.stop()))
          Button('Restart').onClick(() => this.run(async () => {
            this.fileStore.invalidateAutosave();
            await firebird.restartCold();
          }))
        }

        Button('Save named snapshot').onClick(() => this.saveNamedSnapshot()).width('100%')
        Text('Snapshots').fontColor(Color.White).fontWeight(FontWeight.Bold)
        ForEach(this.snapshots, (name: string) => {
          Column({ space: 4 }) {
            Text(name).fontColor(Color.White).fontSize(11)
            Row({ space: 4 }) {
              Button('Load').onClick(() => this.run(async () =>
                await firebird.loadSnapshot(this.fileStore.snapshotPath(name))))
              Button('Export').onClick(async () => await this.run(async () =>
                await this.fileStore.exportSnapshot(name)))
              Button('Delete').onClick(() => {
                this.fileStore.deleteSnapshot(name); this.refreshSnapshots();
              })
            }
            Row({ space: 4 }) {
              TextInput({ text: this.renameValue, placeholder: 'New snapshot name' })
                .onChange((value: string) => this.renameValue = value)
                .layoutWeight(1)
              Button('Rename').onClick(() => {
                if (this.renameValue.length > 0) {
                  this.fileStore.renameSnapshot(name, this.renameValue);
                  this.renameValue = '';
                  this.refreshSnapshots();
                }
              })
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)
        }, (name: string) => name)

        if (this.status.error.length > 0) {
          Text(this.status.error).fontColor('#FF8A80').fontSize(12)
        }
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .backgroundColor(Color.Black)
    .width('100%')
    .height('100%')
  }
}
