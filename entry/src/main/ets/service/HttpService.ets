import { http } from '@kit.NetworkKit';
import { Logger } from '../common/Logger';
import { Const, MOBILE_UA } from '../common/Const';
import { JdAccount } from '../model/MonitorTask';

/** 单次 HTTP 响应封装 */
export class HttpResponse {
  ok: boolean = false;
  status: number = 0;
  body: string = '';
  /** 重定向目标（若发生 3xx） */
  location: string = '';
  errorMsg: string = '';
}

/**
 * 统一网络层
 * - 自动注入 Cookie
 * - 自动 UA
 * - 超时与异常兜底
 * - 跟随重定向（用于短链解析）
 */
export class HttpService {
  private static account: JdAccount = new JdAccount();

  /** 设置当前登录态，后续请求自动带 Cookie */
  static setAccount(acc: JdAccount): void {
    HttpService.account = acc;
  }

  /** 构造 Cookie 请求头 */
  private static buildCookie(): string {
    const acc: JdAccount = HttpService.account;
    if (!acc.logged) {
      return '';
    }
    return `pt_key=${acc.ptKey}; pt_pin=${acc.ptPin};`;
  }

  /**
   * 发起 GET 请求
   * @param url 请求地址
   * @param referer 可选来源，部分京东接口校验
   * @param withCookie 是否携带 Cookie
   */
  static async get(url: string, referer?: string, withCookie: boolean = true): Promise<HttpResponse> {
    const result: HttpResponse = new HttpResponse();
    const req: http.HttpRequest = http.createHttp();

    const headers: Record<string, string> = {
      'User-Agent': MOBILE_UA,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    };
    if (referer) {
      headers['Referer'] = referer;
    }
    if (withCookie) {
      const ck: string = HttpService.buildCookie();
      if (ck) {
        headers['Cookie'] = ck;
      }
    }

    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: Const.HTTP_TIMEOUT,
        readTimeout: Const.HTTP_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      });

      result.status = resp.responseCode;
      result.body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      result.ok = resp.responseCode >= 200 && resp.responseCode < 400;

      if (resp.responseCode >= 300 && resp.responseCode < 400) {
        // 部分实现把 Location 放在 header 里
        const loc: string | Object = resp.header?.['location'] ?? '';
        result.location = typeof loc === 'string' ? loc : '';
      }
    } catch (e) {
      result.ok = false;
      result.errorMsg = e instanceof Error ? e.message : String(e);
      Logger.error('HttpService.get failed: ' + url + ' -> ' + result.errorMsg);
    } finally {
      req.destroy();
    }

    return result;
  }

  /**
   * 跟随重定向解析短链，返回最终的 URL（最多 5 跳）
   */
  static async resolveRedirect(url: string, maxHop: number = 5): Promise<string> {
    let current: string = url;
    for (let i = 0; i < maxHop; i++) {
      const resp: HttpResponse = await HttpService.get(current, undefined, false);
      if (resp.status >= 300 && resp.status < 400 && resp.location) {
        let next: string = resp.location;
        if (next.startsWith('/')) {
          // 相对路径 -> 拼成绝对路径
          const u: URL = new URL(current);
          next = u.origin + next;
        }
        current = next;
        Logger.info('redirect hop ' + (i + 1) + ' -> ' + current);
        continue;
      }
      break;
    }
    return current;
  }

  /**
   * POST 表单请求（用于加购等写操作）
   */
  static async postForm(
    url: string,
    form: Record<string, string>,
    referer?: string
  ): Promise<HttpResponse> {
    const result: HttpResponse = new HttpResponse();
    const req: http.HttpRequest = http.createHttp();

    const headers: Record<string, string> = {
      'User-Agent': MOBILE_UA,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json, text/plain, */*'
    };
    if (referer) {
      headers['Referer'] = referer;
    }
    const ck: string = HttpService.buildCookie();
    if (ck) {
      headers['Cookie'] = ck;
    }

    const body: string = Object.keys(form)
      .map((k: string) => `${encodeURIComponent(k)}=${encodeURIComponent(form[k])}`)
      .join('&');

    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: Const.HTTP_TIMEOUT,
        readTimeout: Const.HTTP_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      });
      result.status = resp.responseCode;
      result.body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      result.ok = resp.responseCode >= 200 && resp.responseCode < 400;
    } catch (e) {
      result.ok = false;
      result.errorMsg = e instanceof Error ? e.message : String(e);
      Logger.error('HttpService.postForm failed: ' + url + ' -> ' + result.errorMsg);
    } finally {
      req.destroy();
    }

    return result;
  }
}
