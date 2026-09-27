import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { LoginService } from '../service/LoginService';
import { JdAccount } from '../model/MonitorTask';
import { Theme } from '../common/UiUtil';
import { Logger } from '../common/Logger';

/**
 * 登录页
 * 双 Tab：扫码登录（WebView）/ 手动粘贴 Cookie
 */
@Entry
@Component
struct LoginPage {
  @State activeTab: number = 0;
  @State cookieInput: string = '';
  @State loading: boolean = false;
  @State pageUrl: string = LoginService.loginUrl();
  @State statusTip: string = '正在加载京东登录页...';
  @State captured: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController();

  async onCaptured(): Promise<void> {
    if (this.captured) {
      return;
    }
    const acc: JdAccount | null = await LoginService.captureFromWebView();
    if (acc && acc.logged) {
      this.captured = true;
      this.statusTip = '登录成功，凭证已保存';
      promptAction.showToast({ message: '登录成功！', duration: 1500 });
      setTimeout(() => {
        router.back();
      }, 800);
    }
  }

  async doManualLogin(): Promise<void> {
    const acc: JdAccount | null = LoginService.parseCookieText(this.cookieInput);
    if (!acc) {
      promptAction.showToast({ message: 'Cookie 格式不正确，需包含 pt_key', duration: 2000 });
      return;
    }
    if (!acc.ptPin || acc.ptPin.length === 0) {
      promptAction.showToast({ message: '缺少 pt_pin，请粘贴完整 Cookie', duration: 2000 });
      return;
    }
    this.loading = true;
    const ok: boolean = await LoginService.saveManual(acc);
    this.loading = false;
    if (ok) {
      promptAction.showToast({ message: '保存成功，开始监控！', duration: 1500 });
      setTimeout(() => router.back(), 800);
    } else {
      promptAction.showToast({ message: '保存失败，请检查输入', duration: 2000 });
    }
  }

  @Builder
  tabBar() {
    Row() {
      Text('扫码登录')
        .fontSize(15)
        .fontColor(this.activeTab === 0 ? Theme.brandRed : Theme.textSecondary)
        .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 12 })
        .onClick(() => { this.activeTab = 0; })

      Text('粘贴 Cookie')
        .fontSize(15)
        .fontColor(this.activeTab === 1 ? Theme.brandRed : Theme.textSecondary)
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 12 })
        .onClick(() => { this.activeTab = 1; })
    }
    .width('100%')
    .backgroundColor(Theme.cardBg)
    .border({ width: { bottom: 1 }, color: Theme.lineGray })
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(Theme.textPrimary)
          .width(40)
          .onClick(() => router.back())
        Text('登录京东账号')
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

      this.tabBar()

      if (this.activeTab === 0) {
        // ============ 扫码登录 ============
        Stack() {
          Web({ src: this.pageUrl, controller: this.controller })
            .width('100%')
            .height('100%')
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .mixedMode(MixedMode.Compatible)
            .onPageEnd(() => {
              this.statusTip = '';
              // 页面每次加载完成后尝试捕获 Cookie
              this.onCaptured();
            })
            .onErrorReceive(() => {
              this.statusTip = '页面加载失败，请切换「粘贴 Cookie」方式';
            })
            .onConsole((event) => {
              return false;
            })

          if (this.statusTip.length > 0) {
            Column() {
              LoadingProgress().width(36).height(36).color(Theme.brandRed)
              Text(this.statusTip)
                .fontSize(13)
                .fontColor(Theme.textSecondary)
                .margin({ top: 12 })
              Text('提示：登录成功后会自动返回')
                .fontSize(11)
                .fontColor(Theme.textPlaceholder)
                .margin({ top: 6 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F8F8F8')
          }
        }
        .layoutWeight(1)
        .width('100%')

        // 手动捕获按钮（WebView 未能自动捕获时的兜底）
        Button('我已登录完成，提取凭证')
          .width('92%')
          .height(44)
          .fontSize(15)
          .backgroundColor(Theme.brandRed)
          .fontColor(Color.White)
          .margin({ top: 8, bottom: 12 })
          .onClick(() => this.onCaptured())
      } else {
        // ============ 粘贴 Cookie ============
        Scroll() {
          Column() {
            Text('使用说明')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .width('100%')
              .margin({ top: 16, bottom: 8 })

            Text('1. 电脑浏览器登录京东，按 F12 打开开发者工具\n' +
              '2. 切换到 Application → Cookies → jd.com\n' +
              '3. 找到 pt_key 和 pt_pin，复制其值\n' +
              '4. 按「pt_key=xxx; pt_pin=yyy」格式粘贴到下方')
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .lineHeight(21)
              .width('100%')

            TextArea({ placeholder: 'pt_key=AAJxxxxxxxxxx; pt_pin=jd_abc123;', text: this.cookieInput })
              .width('100%')
              .height(140)
              .fontSize(13)
              .backgroundColor(Theme.cardBg)
              .borderRadius(8)
              .margin({ top: 12 })
              .onChange((v: string) => { this.cookieInput = v; })

            Text('Cookie 将加密存储在本机，不会上传到任何服务器')
              .fontSize(11)
              .fontColor(Theme.textPlaceholder)
              .width('100%')
              .margin({ top: 8 })

            Button(this.loading ? '保存中...' : '保存并开始监控')
              .width('100%')
              .height(44)
              .fontSize(15)
              .backgroundColor(Theme.brandRed)
              .fontColor(Color.White)
              .margin({ top: 20 })
              .enabled(!this.loading)
              .onClick(() => this.doManualLogin())
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
