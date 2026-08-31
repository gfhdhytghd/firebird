export interface JitProbeResult {
  success: boolean;
  pageSize: number;
  returnValue: number;
  error: string;
}

export interface ValidationResult {
  valid: boolean;
  product: number;
  model: string;
  usbLinkConnected: boolean;
  transferProgress: number;
  debuggerActive: boolean;
  debuggerWaitingForInput: boolean;
  error: string;
}

export interface EmulatorStatus {
  state: 'stopped' | 'starting' | 'running' | 'paused' | 'error';
  error: string;
  speed: number;
  fps: number;
  jitRequested: boolean;
  jitProbePassed: boolean;
  jitInitialized: boolean;
  translatedBlocks: number;
  jitExecutionEntries: number;
  product: number;
  model: string;
}

export interface EmulatorConfiguration {
  bootPath: string;
  flashPath: string;
  jitEnabled: boolean;
}

export interface SnapshotInfo {
  valid: boolean;
  harmonyFormat: boolean;
  version: number;
  product: number;
  error: string;
}

export interface DebuggerConfiguration {
  gdbPort: number;
  remotePort: number;
  debugOnStart: boolean;
  debugOnWarn: boolean;
  printOnWarn: boolean;
}

export const probeJit: () => Promise<JitProbeResult>;
export const validateFiles: (bootPath: string, flashPath: string) => Promise<ValidationResult>;
export const configure: (configuration: EmulatorConfiguration) => Promise<ValidationResult>;
export const start: (mode: 'auto' | 'cold' | 'snapshot', snapshotPath?: string) => Promise<void>;
export const pause: () => void;
export const resume: () => void;
export const stop: () => Promise<void>;
export const restartCold: () => Promise<void>;
export const saveSnapshot: (path: string) => Promise<void>;
export const loadSnapshot: (path: string) => Promise<void>;
export const inspectSnapshot: (path: string) => Promise<SnapshotInfo>;
export const setKeyState: (keyId: number, pressed: boolean) => void;
export const setTouchpadState: (x: number, y: number, contact: boolean, down: boolean) => void;
export const releaseAllInputs: () => void;
export const setSpeedLimit: (limit: 1 | 2 | 0) => void;
export const sendFile: (sandboxPath: string, calculatorPath: string) => void;
export const exitPressToTest: () => void;
export const configureDebugger: (configuration: DebuggerConfiguration) => Promise<void>;
export const enterDebugger: () => void;
export const sendDebuggerCommand: (command: string) => void;
export const getDebugLog: () => string;
export const getStatus: () => EmulatorStatus;
export const subscribeStatus: (callback: (status: EmulatorStatus) => void) => void;
