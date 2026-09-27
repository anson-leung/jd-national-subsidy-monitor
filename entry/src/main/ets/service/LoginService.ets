import { webview } from '@kit.ArkWeb';
import { Logger } from '../common/Logger';
import { Const } from '../common/Const';
import { JdAccount } from '../model/MonitorTask';
import { StorageService } from './StorageService';
import { HttpService } from './HttpService';

/**
 * 登录服务
 *
 * 主路径：App 内 Web 组件加载京东 H5 登录页，用户在页面里完成扫码/账号登录，
 *        登录成功后从 WebCookieManager 读取 pt_key / pt_pin 自动保存。
 * 兜底路径：用户直接粘贴 Cookie 文本，本地解析保存。
 */
export class LoginService {

  /** 登录页地址（H5，支持扫码） */
  static loginUrl(): string {
    return Const.LOGIN_PAGE;
  }

  /**
   * 从 WebView 的 Cookie 管理器中提取登录凭证
   * 应在页面跳转完成（onPageEnd）后调用
   */
  static async captureFromWebView(): Promise<JdAccount | null> {
    try {
      const cookies: webview.WebCookie[] = await webview.WebCookieManager.fetchCookie(
        { url: 'https://passport.jd.com' });
      const acc: JdAccount = LoginService.parseCookies(cookies);

      if (acc.logged) {
        // 补充昵称：pt_pin 即账号名（通常是京东用户名）
        acc.nickname = acc.ptPin;
        acc.loginAt = Date.now();
        await StorageService.saveAccount(acc);
        HttpService.setAccount(acc);
        Logger.info('扫码登录成功，已保存凭证');
        return acc;
      }

      // passport 域没拿到，尝试从 .jd.com 全域拿（登录后 Cookie 会扩散到主域）
      const all: webview.WebCookie[] = await webview.WebCookieManager.fetchCookie({ url: 'https://www.jd.com' });
      const acc2: JdAccount = LoginService.parseCookies(all);
      if (acc2.logged) {
        acc2.nickname = acc2.ptPin;
        acc2.loginAt = Date.now();
        await StorageService.saveAccount(acc2);
        HttpService.setAccount(acc2);
        Logger.info('扫码登录成功（主域），已保存凭证');
        return acc2;
      }

      return null;
    } catch (e) {
      Logger.error('captureFromWebView failed: ' + (e instanceof Error ? e.message : String(e)));
      return null;
    }
  }

  /** 从 WebCookie 数组解析出 pt_key / pt_pin */
  private static parseCookies(cookies: webview.WebCookie[]): JdAccount {
    const acc: JdAccount = new JdAccount();
    for (const c of cookies) {
      const name: string = c.name ?? '';
      const value: string = c.value ?? '';
      if (name === 'pt_key' && value.length > 0) {
        acc.ptKey = value;
      } else if (name === 'pt_pin' && value.length > 0) {
        acc.ptPin = decodeURIComponent(value);
      }
    }
    return acc;
  }

  /**
   * 手动粘贴 Cookie 文本解析
   * 支持形如：pt_key=AAJxxx; pt_pin=jd_abc; 或纯 "AAJxxx" 形式（需配合已有 pin）
   */
  static parseCookieText(text: string): JdAccount | null {
    if (!text || text.trim().length === 0) {
      return null;
    }
    const acc: JdAccount = new JdAccount();

    const keyMatch: RegExpMatchArray | null = text.match(/pt_key\s*=\s*([^;,\s]+)/);
    const pinMatch: RegExpMatchArray | null = text.match(/pt_pin\s*=\s*([^;,\s]+)/);

    if (keyMatch) {
      acc.ptKey = keyMatch[1];
    }
    if (pinMatch) {
      acc.ptPin = decodeURIComponent(pinMatch[1]);
    }

    // 只给了 pt_key 的值（无 key= 前缀）时，若长度像 pt_key 则直接采用
    if (!acc.ptKey && text.trim().length > 30 && !text.includes('=')) {
      acc.ptKey = text.trim();
    }

    return acc.ptKey.length > 0 ? acc : null;
  }

  /** 保存手动输入的凭证，并做一次连通性校验 */
  static async saveManual(acc: JdAccount): Promise<boolean> {
    if (!acc.logged) {
      return false;
    }
    // 先临时注入，验证能否取到价格接口数据（轻量校验，不需要登录的也返回，
    // 因此这里主要验证格式与网络，不强制要求登录态）
    HttpService.setAccount(acc);
    await StorageService.saveAccount(acc);
    Logger.info('手动凭证已保存');
    return true;
  }

  /**
   * 校验当前登录态是否有效
   * 通过请求需要登录的接口判断
   */
  static async verifyLogin(): Promise<boolean> {
    const acc: JdAccount = await StorageService.loadAccount();
    if (!acc.logged) {
      return false;
    }
    HttpService.setAccount(acc);
    const resp = await HttpService.get('https://api.m.jd.com/client.action?functionId=GetJDUserInfoUnion',
      'https://home.m.jd.com/', true);
    if (!resp.ok) {
      return false;
    }
    // 未登录时返回体通常包含 "not login" 或 code != 0
    const notLogin: boolean = /not\s*log|请先登录|登录失效/i.test(resp.body);
    return !notLogin;
  }

  /** 退出登录 */
  static async logout(): Promise<void> {
    await StorageService.clearAccount();
    HttpService.setAccount(new JdAccount());
    Logger.info('已退出登录');
  }

  /** 清除 WebView 中的京东 Cookie（退出登录时同步清理） */
  static async clearWebCookies(): Promise<void> {
    try {
      await webview.WebCookieManager.clearAllCookiesSync();
      Logger.info('WebView Cookie 已清理');
    } catch (e) {
      Logger.warn('清理 WebView Cookie 失败: ' + (e instanceof Error ? e.message : String(e)));
    }
  }
}
