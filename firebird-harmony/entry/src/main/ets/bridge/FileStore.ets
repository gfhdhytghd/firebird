import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { resourceManager } from '@kit.LocalizationKit';

export interface StoredConfiguration {
  bootPath: string;
  flashPath: string;
  jitEnabled: boolean;
}

export interface FirebirdProfile {
  id: string;
  name: string;
}

export interface TransferFile {
  path: string;
  name: string;
}

export interface DebuggerSettings {
  gdbEnabled: boolean;
  gdbPort: number;
  remoteEnabled: boolean;
  remotePort: number;
  debugOnStart: boolean;
  debugOnWarn: boolean;
  printOnWarn: boolean;
}

export class FileStore {
  private context: common.UIAbilityContext;
  private root: string;
  private activeProfileId: string = 'default';
  private profiles: Array<FirebirdProfile> = [{ id: 'default', name: 'Default' }];

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.root = `${context.filesDir}/firebird`;
    this.ensureDirectories();
  }

  updateContext(context: common.UIAbilityContext): void {
    this.context = context;
    this.root = `${context.filesDir}/firebird`;
    this.ensureDirectories();
  }

  bootPath(): string { return `${this.profileImageDirectory()}/boot1.rom`; }
  flashPath(): string { return `${this.profileImageDirectory()}/flash.img`; }
  autosavePath(): string {
    return this.activeProfileId === 'default' ? `${this.root}/snapshots/autosave.snapshot` :
      `${this.root}/snapshots/autosave-${this.activeProfileId}.snapshot`;
  }
  snapshotDirectory(): string { return `${this.root}/snapshots`; }

  getProfiles(): Array<FirebirdProfile> { return this.profiles.slice(); }
  getActiveProfileId(): string { return this.activeProfileId; }
  getActiveProfileName(): string {
    const current = this.profiles.find((profile: FirebirdProfile): boolean =>
      profile.id === this.activeProfileId);
    return current === undefined ? 'Default' : current.name;
  }

  async loadProfiles(): Promise<void> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    const encoded = await store.get('profileList', 'default:Default') as string;
    const loaded: Array<FirebirdProfile> = [];
    encoded.split('|').forEach((entry: string): void => {
      const separator = entry.indexOf(':');
      if (separator <= 0) return;
      const id = entry.substring(0, separator).replace(/[^A-Za-z0-9_-]/g, '');
      const name = decodeURIComponent(entry.substring(separator + 1));
      if (id.length > 0 && name.length > 0)
        loaded.push({ id: id, name: name });
    });
    if (!loaded.some((profile: FirebirdProfile): boolean => profile.id === 'default'))
      loaded.unshift({ id: 'default', name: 'Default' });
    this.profiles = loaded;
    const requested = await store.get('activeProfile', 'default') as string;
    this.activeProfileId = loaded.some((profile: FirebirdProfile): boolean =>
      profile.id === requested) ? requested : 'default';
    this.ensureDirectories();
  }

  async createProfile(name: string): Promise<FirebirdProfile> {
    const trimmed = name.trim();
    if (trimmed.length === 0) throw new Error('Profile name cannot be empty');
    const profile: FirebirdProfile = {
      id: `profile-${Date.now()}`,
      name: trimmed
    };
    this.profiles.push(profile);
    this.activeProfileId = profile.id;
    this.ensureDirectories();
    await this.saveProfiles();
    return profile;
  }

  async selectProfile(id: string): Promise<void> {
    if (!this.profiles.some((profile: FirebirdProfile): boolean => profile.id === id))
      throw new Error('Profile no longer exists');
    this.activeProfileId = id;
    this.ensureDirectories();
    await this.saveProfiles();
  }

  async renameActiveProfile(name: string): Promise<void> {
    const trimmed = name.trim();
    if (trimmed.length === 0) throw new Error('Profile name cannot be empty');
    const current = this.profiles.find((profile: FirebirdProfile): boolean =>
      profile.id === this.activeProfileId);
    if (current === undefined) throw new Error('Active profile no longer exists');
    current.name = trimmed;
    await this.saveProfiles();
  }

  async deleteActiveProfile(): Promise<void> {
    if (this.activeProfileId === 'default') throw new Error('The default profile cannot be deleted');
    const removed = this.activeProfileId;
    this.profiles = this.profiles.filter((profile: FirebirdProfile): boolean => profile.id !== removed);
    this.activeProfileId = 'default';
    // Image files are deliberately retained. Removing a profile must not silently
    // destroy a user's 132 MiB flash image or snapshots.
    await this.saveProfiles();
  }

  async installBundledImagesIfPresent(): Promise<void> {
    if (this.activeProfileId !== 'default') return;
    if (!this.bootReady())
      await this.copyBundledRawFile('firebird.boot1.rom', this.bootPath(), 0x80000);
    if (!this.flashReady())
      await this.copyBundledRawFile('firebird.flash.img', this.flashPath(), 132 * 1024 * 1024);
  }

  exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  bootReady(): boolean { return this.hasSize(this.bootPath(), 0x80000); }
  flashReady(): boolean { return this.hasSize(this.flashPath(), 132 * 1024 * 1024); }
  bootCandidateReady(path: string): boolean { return this.hasSize(path, 0x80000); }
  flashCandidateReady(path: string): boolean { return this.hasSize(path, 132 * 1024 * 1024); }
  async importBoot(): Promise<string> {
    return this.importDocument(`${this.root}/images/boot-candidate.tmp`);
  }

  async importFlash(): Promise<string> {
    return this.importDocument(`${this.root}/images/flash-candidate.tmp`);
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
    return this.importDocument(destination);
  }

  async importTransferFile(): Promise<TransferFile> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const selected = await documentPicker.select();
    if (selected.length !== 1) throw new Error('No file selected');
    const uri = selected[0];
    const tail = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0];
    const decoded = decodeURIComponent(tail);
    const safeName = decoded.replace(/[^A-Za-z0-9._ -]/g, '_');
    const name = safeName.length > 0 ? safeName : `transfer-${Date.now()}.tns`;
    const directory = `${this.root}/transfers`;
    if (!this.exists(directory)) fs.mkdirSync(directory, true);
    const destination = `${directory}/${Date.now()}-${name}`;
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(source.fd, destination);
    } finally {
      fs.closeSync(source);
    }
    return { path: destination, name: name };
  }

  listSnapshots(): Array<string> {
    try {
      return fs.listFileSync(this.snapshotDirectory())
        .filter((name: string) => name.endsWith('.snapshot') &&
          name !== 'autosave.snapshot' && !name.startsWith('autosave-'))
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
    const imageId = this.activeProfileId === 'default' ? 'images' : `profiles/${this.activeProfileId}`;
    await store.put('bootId', `${imageId}/boot1.rom`);
    await store.put('flashId', `${imageId}/flash.img`);
    await store.put('jitEnabled', configuration.jitEnabled);
    await store.flush();
  }

  async loadDebuggerSettings(): Promise<DebuggerSettings> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    return {
      gdbEnabled: await store.get('gdbEnabled', false) as boolean,
      gdbPort: await store.get('gdbPort', 3333) as number,
      remoteEnabled: await store.get('remoteDebugEnabled', false) as boolean,
      remotePort: await store.get('remoteDebugPort', 3334) as number,
      debugOnStart: await store.get('debugOnStart', false) as boolean,
      debugOnWarn: await store.get('debugOnWarn', false) as boolean,
      printOnWarn: await store.get('printOnWarn', true) as boolean
    };
  }

  async saveDebuggerSettings(settings: DebuggerSettings): Promise<void> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    await store.put('gdbEnabled', settings.gdbEnabled);
    await store.put('gdbPort', settings.gdbPort);
    await store.put('remoteDebugEnabled', settings.remoteEnabled);
    await store.put('remoteDebugPort', settings.remotePort);
    await store.put('debugOnStart', settings.debugOnStart);
    await store.put('debugOnWarn', settings.debugOnWarn);
    await store.put('printOnWarn', settings.printOnWarn);
    await store.flush();
  }

  private ensureDirectories(): void {
    for (const directory of [this.root, `${this.root}/images`, `${this.root}/profiles`,
      this.profileImageDirectory(), this.snapshotDirectory()]) {
      if (!this.exists(directory)) fs.mkdirSync(directory, true);
    }
  }

  private profileImageDirectory(): string {
    return this.activeProfileId === 'default' ? `${this.root}/images` :
      `${this.root}/profiles/${this.activeProfileId}`;
  }

  private async saveProfiles(): Promise<void> {
    const store = await preferences.getPreferences(this.context, 'firebird_settings');
    const encoded = this.profiles.map((profile: FirebirdProfile): string =>
      `${profile.id}:${encodeURIComponent(profile.name)}`).join('|');
    await store.put('profileList', encoded);
    await store.put('activeProfile', this.activeProfileId);
    await store.flush();
  }

  private async copyBundledRawFile(resourceName: string, destination: string,
    expectedLength: number): Promise<void> {
    let descriptor: resourceManager.RawFileDescriptor;
    try {
      descriptor = await this.context.resourceManager.getRawFd(resourceName);
    } catch (_) {
      return; // Normal public builds deliberately contain no private images.
    }
    if (descriptor.length !== expectedLength) {
      this.context.resourceManager.closeRawFd(resourceName);
      return;
    }
    const temporary = `${destination}.tmp`;
    try {
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
          const written = fs.writeSync(output.fd, buffer, { length: read });
          if (written !== read)
            throw new Error(`Bundled resource ${resourceName} could not be written completely`);
          copied += written;
        }
        fs.renameSync(temporary, destination);
      } finally {
        fs.closeSync(output);
      }
    } catch (_) {
      // Leave the previous stable image untouched when a bundled copy fails.
    } finally {
      this.context.resourceManager.closeRawFd(resourceName);
      if (this.exists(temporary)) fs.unlinkSync(temporary);
    }
  }

  private hasSize(path: string, expectedLength: number): boolean {
    if (!this.exists(path)) return false;
    try {
      return fs.statSync(path).size === expectedLength;
    } catch (_) {
      return false;
    }
  }

  private async importDocument(destination: string): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const selected = await documentPicker.select();
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
