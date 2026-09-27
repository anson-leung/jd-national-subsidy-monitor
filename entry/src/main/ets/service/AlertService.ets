import { vibrator } from '@kit.SensorServiceKit';
import { notificationManager } from '@kit.NotificationKit';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { Const } from '../common/Const';

/**
 * 强提醒服务
 * 命中监控条件时：持续振动 + 系统通知，确保用户不会错过抢购时机
 */
export class AlertService {

  /** 初始化通知渠道（应用启动时调用一次） */
  static async initNotification(): Promise<void> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        Logger.warn('通知未开启，尝试请求授权');
        await notificationManager.requestEnableNotification();
      }
      Logger.info('通知服务就绪');
    } catch (e) {
      Logger.error('initNotification failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /**
   * 触发强提醒
   * @param title 通知标题
   * @param content 通知内容
   * @param notifyId 通知 id
   */
  static async alert(title: string, content: string, notifyId: number): Promise<void> {
    // 振动与通知并行，互不阻塞
    AlertService.vibratePattern();
    await AlertService.notify(title, content, notifyId);
  }

  /**
   * 振动：使用长振动 + 节奏模式，模拟「响铃」体感
   * 优先尝试长振动（1000ms），失败降级为节奏振动
   */
  static vibratePattern(): void {
    try {
      // 20s 内禁止重复触发，避免高频轮询导致振动轰炸
      vibrator.startVibration(
        { type: 'time', duration: 1200 },
        { id: 0, usage: 'alarm' }
      ).then(() => {
        Logger.info('振动触发成功');
      }).catch((err: Error) => {
        Logger.warn('长振动失败，降级为节奏振动: ' + err.message);
        AlertService.vibrateRhythm();
      });
    } catch (e) {
      Logger.error('vibratePattern failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /** 节奏振动：三短一长，用于需要更强提示的场景 */
  static vibrateRhythm(): void {
    try {
      // 通过多次触发近似「滴滴滴—」的节奏
      const delays: number[] = [0, 300, 600, 900];
      for (let i = 0; i < delays.length; i++) {
        setTimeout(() => {
          try {
            vibrator.startVibration(
              { type: 'time', duration: i === delays.length - 1 ? 800 : 180 },
              { id: 1, usage: 'alarm' }
            ).catch((err: Error) => {
              Logger.warn('节奏振动失败: ' + err.message);
            });
          } catch (e) {
            Logger.warn('节奏振动异常');
          }
        }, delays[i]);
      }
    } catch (e) {
      Logger.error('vibrateRhythm failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /**
   * 发布系统通知
   * @param title 标题
   * @param content 内容
   * @param notifyId 唯一 id
   * @param skuId 点击通知要跳转的商品，可为空
   */
  static async notify(title: string, content: string, notifyId: number, skuId?: string): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: notifyId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: content,
            additionalText: skuId ? `商品ID: ${skuId}` : ''
          }
        },
        // 横幅 + 响铃，最大化提醒强度
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        // 允许锁屏显示
        tapDismissed: false,
        // 自动删除（用户点击后）
        autoDeleted: true
      };

      await notificationManager.publish(request);
      Logger.info('通知已发送: ' + title);
    } catch (e) {
      Logger.error('notify failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /** 停止所有振动 */
  static stopVibrate(): void {
    try {
      vibrator.stopVibration();
    } catch (e) {
      Logger.warn('stopVibrate failed');
    }
  }

  /**
   * 命中提醒（业务语义封装）
   * 生成统一格式的文案并触发提醒
   */
  static async alertHit(taskName: string, price: number, targetPrice: number, notifyId: number, skuId: string): Promise<void> {
    const title: string = `🎯 目标价命中｜¥${price.toFixed(2)}`;
    const content: string = `${taskName}\n已低于目标价 ¥${targetPrice.toFixed(2)}，请立即前往付款`;
    await AlertService.alert(title, content, notifyId);
    // 命中时额外补一次节奏振动，强化提醒
    setTimeout(() => AlertService.vibrateRhythm(), 1500);
  }
}
