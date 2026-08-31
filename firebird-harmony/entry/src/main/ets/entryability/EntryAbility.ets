import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x4642, 'Firebird', 'EntryAbility created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#000000',
        navigationBarColor: '#303238',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      });
    });
    windowStage.loadContent('pages/Index');
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('firebirdBackground', true);
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('firebirdBackground', false);
  }
}
