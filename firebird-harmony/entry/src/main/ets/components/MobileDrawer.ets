import * as firebird from 'libfirebird_harmony.so';
import { EmulatorStatus } from 'libfirebird_harmony.so';
import { FileStore } from '../bridge/FileStore';

const PANEL_BG: string = '#111315';
const ROW_BG: string = '#1D2126';
const ACTIVE: string = '#5CC8D7';
const MUTED: string = '#9AA3AD';

@Component
export struct MobileDrawer {
  @Link status: EmulatorStatus;
  @Prop fileStore: FileStore;
  onOpenConfiguration: () => void = () => {};
  onClose: () => void = () => {};

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private async run(action: () => Promise<void>): Promise<void> {
    try { await action(); }
    catch (error) { this.toast(error instanceof Error ? error.message : JSON.stringify(error)); }
  }

  private requireImages(): void {
    if (!this.fileStore.bootReady() || !this.fileStore.flashReady())
      throw new Error('Import Boot1 and Flash in Configuration first');
  }

  @Builder
  private action(icon: string, title: string, enabled: boolean, handler: () => void) {
    Row({ space: 12 }) {
      Text(icon).fontSize(23).fontColor(enabled ? ACTIVE : '#59616A').width(34)
        .textAlign(TextAlign.Center)
      Text(title).fontSize(17).fontColor(enabled ? Color.White : '#59616A').layoutWeight(1)
    }
    .width('100%')
    .height(58)
    .padding({ left: 14, right: 14 })
    .backgroundColor(ROW_BG)
    .border({ width: { bottom: 1 }, color: '#31363D' })
    .enabled(enabled)
    .onClick(handler)
  }

  build() {
    Column() {
      Column({ space: 3 }) {
        Text('FIREBIRD').fontSize(25).fontWeight(FontWeight.Bold).fontColor(Color.White)
        Text(this.fileStore.getActiveProfileName()).fontSize(12).fontColor(ACTIVE)
      }
      .width('100%').height(116).padding({ left: 18, top: 28 })
      .alignItems(HorizontalAlign.Start).backgroundColor(PANEL_BG)

      this.action('▶', 'Start', this.fileStore.bootReady() && this.fileStore.flashReady(), () => {
        this.run(async () => { this.requireImages(); await firebird.restartCold(); this.onClose(); });
      })
      this.action('↻', 'Reset', this.status.state === 'running' || this.status.state === 'paused', () => {
        this.run(async () => { await firebird.restartCold(); this.onClose(); });
      })
      this.action('◫', 'Resume', this.fileStore.exists(this.fileStore.autosavePath()), () => {
        this.run(async () => {
          this.requireImages(); await firebird.stop();
          await firebird.start('snapshot', this.fileStore.autosavePath()); this.onClose();
        });
      })
      this.action('▣', 'Save', this.status.state === 'running' || this.status.state === 'paused', () => {
        this.run(async () => {
          await firebird.saveSnapshot(this.fileStore.autosavePath());
          this.toast('State saved'); this.onClose();
        });
      })

      Blank().height(34)

      this.action('⚙', 'Configuration', true, () => this.onOpenConfiguration())

      Blank().layoutWeight(1)

      Column({ space: 6 }) {
        Text(`Speed ${Math.round(this.status.speed * 100)}%`).fontSize(14).fontColor(Color.White)
        Text(`Firebird · ${this.status.model || 'No model'}`).fontSize(11).fontColor(MUTED)
      }
      .width('100%').padding({ left: 18, right: 18, top: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').backgroundColor(PANEL_BG)
  }
}
