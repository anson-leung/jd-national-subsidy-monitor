import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { LoginService } from '../service/LoginService';
import { StorageService } from '../service/StorageService';
import { MonitorService } from '../service/MonitorService';
import { JdAccount } from '../model/MonitorTask';
import { Theme, formatTime } from '../common/UiUtil';

/**
 * 设置页：账号管理、登录态校验、关于信息
 */
@Entry
@Component
struct SettingsPage {
  @State logged: boolean = false;
  @State nickname: string = '';
  @State loginAt: number = 0;
  @State verifying: boolean = false;
  @State verifyResult: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    const acc: JdAccount = await StorageService.loadAccount();
    this.logged = acc.logged;
    this.nickname = acc.nickname || acc.ptPin;
    this.loginAt = acc.loginAt;
  }

  /** 校验登录态是否仍有效 */
  async verify(): Promise<void> {
    this.verifying = true;
    this.verifyResult = '';
    try {
      const ok: boolean = await LoginService.verifyLogin();
      this.verifyResult = ok ? '✅ 登录态有效' : '❌ 登录态已失效，请重新登录';
    } catch (e) {
      this.verifyResult = '⚠️ 校验失败，请检查网络';
    } finally {
      this.verifying = false;
    }
  }

  async logout(): Promise<void> {
    await LoginService.logout();
    await LoginService.clearWebCookies();
    MonitorService.stop();
    await this.load();
    this.verifyResult = '';
    promptAction.showToast({ message: '已退出登录', duration: 1500 });
  }

  @Builder
  settingRow(label: string, value: string, onClick?: () => void, danger?: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(danger ? Theme.brandRed : Theme.textPrimary)
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor(Theme.textSecondary)
      Text('›')
        .fontSize(16)
        .fontColor(Theme.textPlaceholder)
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: Theme.lineGray })
    .onClick(() => {
      if (onClick) {
        onClick();
      }
    })
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(Theme.textPrimary)
          .width(40)
          .onClick(() => router.back())
        Text('设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(40)
      }
      .width('100%')
      .height(52)
      .backgroundColor(Theme.cardBg)
      .padding({ left: 8, right: 8 })

      Scroll() {
        Column() {
          // ============ 账号 ============
          Text('账号')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .margin({ top: 16, bottom: 8, left: 4 })

          Column() {
            if (this.logged) {
              Row() {
                Column() {
                  Text(this.nickname || '已登录')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary)
                  Text(this.loginAt > 0 ? `登录于 ${formatTime(this.loginAt)}` : '')
                    .fontSize(11)
                    .fontColor(Theme.textPlaceholder)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('重新登录')
                  .fontSize(13)
                  .fontColor(Theme.brandRed)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor('#FFF0EF')
                  .onClick(() => router.pushUrl({ url: 'pages/LoginPage' }))
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
              .border({ width: { bottom: 1 }, color: Theme.lineGray })

              this.settingRow(
                this.verifying ? '校验中...' : '校验登录态',
                this.verifyResult,
                () => this.verify()
              )

              this.settingRow('退出登录', '', () => this.logout(), true)
            } else {
              Row() {
                Text('未登录')
                  .fontSize(14)
                  .fontColor(Theme.textSecondary)
                  .layoutWeight(1)
                Text('去登录')
                  .fontSize(13)
                  .fontColor(Color.White)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(14)
                  .backgroundColor(Theme.brandRed)
                  .onClick(() => router.pushUrl({ url: 'pages/LoginPage' }))
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .backgroundColor(Theme.cardBg)
          .borderRadius(10)

          // ============ 提醒 ============
          Text('提醒说明')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .margin({ top: 20, bottom: 8, left: 4 })

          Column() {
            Text('• 命中目标价时会持续振动并弹出通知，请确保系统已开启本应用的通知权限\n' +
              '• 若手机处于静音模式，振动仍会生效；建议将本应用加入电池优化白名单\n' +
              '• 后台监控依赖系统长时任务，部分省电模式可能中断监控，建议保持应用在后台运行')
              .fontSize(12.5)
              .fontColor(Theme.textSecondary)
              .lineHeight(21)
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Theme.cardBg)
          .borderRadius(10)

          // ============ 合规提示 ============
          Text('使用提示')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .margin({ top: 20, bottom: 8, left: 4 })

          Column() {
            Text('• 本应用仅用于个人比价与提醒，Cookie 加密存储于本机，不会上传\n' +
              '• 「加入购物车」与「打开京东下单」均为半自动：最终提交订单需你本人在京东完成\n' +
              '• 请合理设置检查频率，过于频繁的请求可能触发京东风控导致账号受限')
              .fontSize(12.5)
              .fontColor(Theme.textSecondary)
              .lineHeight(21)
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Theme.cardBg)
          .borderRadius(10)

          // ============ 关于 ============
          Text('关于')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .width('100%')
            .margin({ top: 20, bottom: 8, left: 4 })

          Column() {
            this.settingRow('版本', '1.0.0')
            this.settingRow('平台', 'HarmonyOS NEXT')
            this.settingRow('开发框架', 'ArkTS + ArkUI')
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .backgroundColor(Theme.cardBg)
          .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
