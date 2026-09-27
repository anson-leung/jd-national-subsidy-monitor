/**
 * 全局常量与接口地址
 *
 * 说明：京东的接口地址与签名策略会不定期调整。本文件集中收敛所有端点，
 * 便于后续单点维护；若某接口失效，优先在此处替换。
 */

export class Const {
  /** 商品价格接口（返回 JSONP/JSON） */
  static readonly PRICE_API: string = 'https://p.3.cn/prices/mgets';
  /** 商品详情接口 */
  static readonly ITEM_API: string = 'https://item-soa.jd.com/getWareBusiness';
  /** 商品页面（用于抓取库存文本兜底） */
  static readonly ITEM_PAGE: string = 'https://item.m.jd.com/product/';
  /** 加入购物车 */
  static readonly CART_API: string = 'https://cart.jd.com/gate.action';
  /** 移动端购物车页 */
  static readonly CART_PAGE: string = 'https://cart.m.jd.com/';
  /** 扫码登录页 */
  static readonly LOGIN_PAGE: string = 'https://passport.jd.com/new/login.aspx';

  /** 京东 App scheme 前缀 */
  static readonly JD_APP_SCHEME: string = 'openapp.jdmobile://virtual';

  /** 默认轮询间隔（毫秒） */
  static readonly DEFAULT_INTERVAL: number = 5000;
  /** 最小轮询间隔（防止过于频繁触发风控） */
  static readonly MIN_INTERVAL: number = 3000;
  /** 单次请求超时 */
  static readonly HTTP_TIMEOUT: number = 10000;

  /** 偏好存储文件名 */
  static readonly PREF_ACCOUNT: string = 'jd_account';
  static readonly PREF_TASKS: string = 'jd_tasks';
  static readonly PREF_SETTINGS: string = 'jd_settings';

  /** 通知 id 起始值 */
  static readonly NOTIFY_BASE_ID: number = 10001;
}

/** 统一的 User-Agent（移动端，降低被风控概率） */
export const MOBILE_UA: string =
  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/116.0.0.0 Mobile Safari/537.36';
