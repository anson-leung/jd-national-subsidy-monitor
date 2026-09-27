import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { StorageService } from '../service/StorageService';
import { MonitorService } from '../service/MonitorService';
import { AlertService } from '../service/AlertService';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { HttpService } from '../service/HttpService';
import { JdAccount } from '../model/MonitorTask';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    Logger.info('EntryAbility onCreate');

    // 初始化存储
    StorageService.init(this.context);

    // 恢复登录态到网络层
    const acc: JdAccount = await StorageService.loadAccount();
    HttpService.setAccount(acc);
    Logger.info('登录态恢复: ' + (acc.logged ? '已登录' : '未登录'));

    // 初始化通知渠道
    await AlertService.initNotification();
  }

  async onDestroy(): Promise<void> {
    Logger.info('EntryAbility onDestroy');
    MonitorService.stop();
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    Logger.info('onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error('加载首页失败: ' + JSON.stringify(err));
        return;
      }
      Logger.info('首页加载完成');
    });
  }

  onWindowStageDestroy(): void {
    Logger.info('onWindowStageDestroy');
  }

  async onForeground(): Promise<void> {
    Logger.info('onForeground');
    // 回到前台时确保监控在跑
    MonitorService.start();
  }

  async onBackground(): Promise<void> {
    Logger.info('onBackground');
    // 申请长时任务，保证后台监控不被系统挂起
    const ok: boolean = await BackgroundTaskService.start(this.context);
    if (!ok) {
      Logger.warn('后台长时任务申请失败，后台监控可能被系统中断');
    }
  }
}
