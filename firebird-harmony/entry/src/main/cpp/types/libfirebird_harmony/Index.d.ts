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
  product: number;
  model: string;
}

export interface EmulatorConfiguration {
  bootPath: string;
  flashPath: string;
  jitEnabled: boolean;
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
export const inspectSnapshot: (path: string) => Promise<Record<string, string | number | boolean>>;
export const setKeyState: (keyId: number, pressed: boolean) => void;
export const setTouchpadState: (x: number, y: number, contact: boolean, down: boolean) => void;
export const releaseAllInputs: () => void;
export const getStatus: () => EmulatorStatus;
export const setSurface: (surfaceId: bigint, width: number, height: number) => void;
export const resizeSurface: (surfaceId: bigint, width: number, height: number) => void;
export const destroySurface: (surfaceId: bigint) => void;
