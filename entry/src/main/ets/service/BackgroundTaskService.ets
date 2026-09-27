import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';

/**
 * 后台长时任务管理
 *
 * 鸿蒙对后台应用有严格的资源管控，普通应用的定时器在进入后台后会被挂起。
 * 使用 backgroundTaskManager 申请「数据传输」类型的长时任务，
 * 才能让监控轮询在后台持续运行。
 *
 * 注意：需要在 module.json5 声明 ohos.permission.KEEP_BACKGROUND_RUNNING。
 */
export class BackgroundTaskService {
  private static wantAgentObj: WantAgent | null = null;

  /** 申请长时任务 */
  static async start(context: common.UIAbilityContext): Promise<boolean> {
    try {
      // 构造点击通知栏回跳本应用的 WantAgent
      if (!BackgroundTaskService.wantAgentObj) {
        BackgroundTaskService.wantAgentObj = await wantAgent.getWantAgent({
          wants: [
            {
              bundleName: context.applicationInfo.name,
              abilityName: 'EntryAbility'
            }
          ],
          operationType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0,
          wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        });
      }

      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        BackgroundTaskService.wantAgentObj
      );
      Logger.info('后台长时任务已启动');
      return true;
    } catch (e) {
      Logger.error('启动后台任务失败: ' + (e instanceof Error ? e.message : String(e)));
      return false;
    }
  }

  /** 结束长时任务 */
  static async stop(context: common.UIAbilityContext): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      Logger.info('后台长时任务已停止');
    } catch (e) {
      Logger.warn('停止后台任务失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }
}
