import { Logger } from './Logger';

/**
 * 京东分享链接 / 口令解析器
 *
 * 支持格式：
 *  1. https://item.m.jd.com/product/100012043978.html
 *  2. https://item.jd.com/100012043978.html
 *  3. https://3.cn/xxxxx        （短链，需要网络跳转解析）
 *  4. 【京东】https://3.cn/... ￥ABC123￥  （分享口令，含短链）
 *  5. 纯数字 skuId: 100012043978
 *  6. https://u.jd.com/xxxxx    （联盟短链）
 */
export class JdLinkParser {
  /** 从任意文本中提取 skuId；无法直接提取时返回 null，由调用方走短链解析 */
  static extractSkuId(raw: string): string | null {
    if (!raw) {
      return null;
    }
    const text: string = raw.trim();

    // 1) 纯数字
    if (/^\d{6,20}$/.test(text)) {
      return text;
    }

    // 2) 标准 / 移动端商品详情页  「/product/100012043978.html」或「item.jd.com/100012043978.html」
    const m1: RegExpMatchArray | null = text.match(/\/product\/(\d{6,20})\.html/);
    if (m1) {
      return m1[1];
    }
    const m2: RegExpMatchArray | null = text.match(/item\.jd\.com\/(\d{6,20})\.html/);
    if (m2) {
      return m2[1];
    }

    // 3) 带 sku 查询参数
    const m3: RegExpMatchArray | null = text.match(/[?&]sku(?:Id)?=(\d{6,20})/i);
    if (m3) {
      return m3[1];
    }

    // 4) 兜底：URL 中出现的长数字串（>=9 位），排除时间戳等干扰项优先级最低
    const m4: RegExpMatchArray | null = text.match(/(\d{9,20})/);
    if (m4) {
      Logger.warn('JdLinkParser: fallback numeric match -> ' + m4[1]);
      return m4[1];
    }

    return null;
  }

  /** 判断是否短链，需要跟随重定向 */
  static isShortLink(raw: string): boolean {
    if (!raw) {
      return false;
    }
    return /(3\.cn|u\.jd\.com|jd\.com\/[a-zA-Z0-9]{4,8}$)/.test(raw.trim());
  }

  /** 从分享口令文本中抽取第一个 http(s) 链接 */
  static extractUrl(raw: string): string | null {
    if (!raw) {
      return null;
    }
    const m: RegExpMatchArray | null = raw.match(/https?:\/\/[^\s\u4e00-\u9fa5，,。、]+/);
    return m ? m[0] : null;
  }

  /** 规范化图片地址：补全协议、替换尺寸后缀 */
  static normalizeImage(url: string): string {
    if (!url) {
      return '';
    }
    let u: string = url.trim();
    if (u.startsWith('//')) {
      u = 'https:' + u;
    }
    // 京东图片可通过 /n5/ -> /n1/ 拿到小图，降低流量
    u = u.replace(/\/n\d+\//, '/n1/');
    // 去掉 webp 后缀中的尺寸限制，保留原格式
    return u;
  }
}
