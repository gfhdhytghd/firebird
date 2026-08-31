import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { resourceManager } from '@kit.LocalizationKit';

export interface StoredConfiguration {
  bootPath: string;
  flashPath: string;
  jitEnabled: boolean;
}

export class FileStore {
  private context: common.UIAbilityContext;
  private root: string;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.root = `${context.filesDir}/firebird`;
    this.ensureDirectories();
  }

  bootPath(): string { return `${this.root}/images/boot1.rom`; }
  flashPath(): string { return `${this.root}/images/flash.img`; }
  autosavePath(): string { return `${this.root}/snapshots/autosave.snapshot`; }
  snapshotDirectory(): string { return `${this.root}/snapshots`; }

  async installBundledImagesIfPresent(): Promise<void> {
    if (!this.exists(this.bootPath()))
      this.copyBundledRawFile('private/boot1.rom', this.bootPath());
    if (!this.exists(this.flashPath()))
      this.copyBundledRawFile('private/flash.img', this.flashPath());
  }

  exists(path: string): boolean {
    try {
      fs.accessSync(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  async importBoot(): Promise<string> {
    return this.importDocument(`${this.root}/images/boot-candidate.tmp`, ['.rom', '.bin', '.img']);
  }

  async importFlash(): Promise<string> {
    return this.importDocument(`${this.root}/images/flash-candidate.tmp`, ['.img', '.bin', '.flash']);
  }

  commitBoot(candidate: string): void { this.commitCandidate(candidate, this.bootPath()); }
  commitFlash(candidate: string): void { this.commitCandidate(candidate, this.flashPath()); }
  discardCandidate(candidate: string): void {
    if (this.exists(candidate)) fs.unlinkSync(candidate);
  }
  invalidateAutosave(): void {
    if (this.exists(this.autosavePath())) fs.unlinkSync(this.autosavePath());
  }

  async importSnapshot(): Promise<string> {
    const destination = `${this.snapshotDirectory()}/imported-${Date.now()}.snapshot`;
    return this.importDocument(destination, ['.snapshot', '.snap', '.gz', '.fbhs']);
  }

  listSnapshots(): Array<string> {
    try {
      return fs.listFileSync(this.snapshotDirectory())
        .filter((name: string) => name.endsWith('.snapshot') && name !== 'autosave.snapshot')
        .sort();
    } catch (_) {
      return [];
    }
  }

  snapshotPath(name: string): string {
    const safeName = name.replace(/[^A-Za-z0-9._-]/g, '_');
    return `${this.snapshotDirectory()}/${safeName}`;
  }

  deleteSnapshot(name: string): void {
    const path = this.snapshotPath(name);
    if (this.exists(path)) fs.unlinkSync(path);
  }

  renameSnapshot(oldName: string, newName: string): string {
    const oldPath = this.snapshotPath(oldName);
    const normalized = newName.endsWith('.snapshot') ? newName : `${newName}.snapshot`;
    const newPath = this.snapshotPath(normalized);
    if (oldPath === newPath) return normalized;
    if (this.exists(newPath)) throw new Error('A snapshot with that name already exists');
    fs.renameSync(oldPath, newPath);
    return normalized;
  }

  async exportSnapshot(name: string): Promise<void> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [name];
    const destinations = await documentPicker.save(options);
    if (destinations.length !== 1) throw new Error('No export destination selected');
    const source = fs.openSync(this.snapshotPath(name), fs.OpenMode.READ_ONLY);
    const destination = fs.openSync(destinations[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.copyFileSync(source.fd, destination.fd);
    } finally {
      fs.closeSync(source);
      fs.closeSync(destination);
    }
  }

  async loadConfiguration(): Promise<StoredConfiguration> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    return {
      bootPath: this.bootPath(),
      flashPath: this.flashPath(),
      jitEnabled: await store.get('jitEnabled', true) as boolean
    };
  }

  async saveConfiguration(configuration: StoredConfiguration): Promise<void> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    await store.put('bootId', 'images/boot1.rom');
    await store.put('flashId', 'images/flash.img');
    await store.put('jitEnabled', configuration.jitEnabled);
    await store.flush();
  }

  private ensureDirectories(): void {
    for (const directory of [this.root, `${this.root}/images`, this.snapshotDirectory()]) {
      if (!this.exists(directory)) fs.mkdirSync(directory);
    }
  }

  private copyBundledRawFile(resourceName: string, destination: string): void {
    let descriptor: resourceManager.RawFileDescriptor;
    try {
      descriptor = this.context.resourceManager.getRawFdSync(resourceName);
    } catch (_) {
      return; // Normal public builds deliberately contain no private images.
    }
    const temporary = `${destination}.tmp`;
    const output = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const buffer = new ArrayBuffer(1024 * 1024);
      let copied: number = 0;
      while (copied < descriptor.length) {
        const amount = Math.min(buffer.byteLength, descriptor.length - copied);
        const read = fs.readSync(descriptor.fd, buffer, {
          offset: descriptor.offset + copied,
          length: amount
        });
        if (read <= 0) throw new Error(`Bundled resource ${resourceName} is truncated`);
        fs.writeSync(output.fd, buffer, { offset: copied, length: read });
        copied += read;
      }
      fs.renameSync(temporary, destination);
    } finally {
      fs.closeSync(output);
      this.context.resourceManager.closeRawFd(resourceName);
      if (this.exists(temporary)) fs.unlinkSync(temporary);
    }
  }

  private async importDocument(destination: string, suffixes: Array<string>): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = suffixes;
    const selected = await documentPicker.select(options);
    if (selected.length !== 1) throw new Error('No file selected');

    const temporary = `${destination}.tmp`;
    const source = fs.openSync(selected[0], fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(source.fd, temporary);
      fs.renameSync(temporary, destination);
    } finally {
      fs.closeSync(source);
      if (this.exists(temporary)) fs.unlinkSync(temporary);
    }
    return destination;
  }

  private commitCandidate(candidate: string, destination: string): void {
    if (!this.exists(candidate)) throw new Error('Import candidate is missing');
    fs.renameSync(candidate, destination);
  }
}
