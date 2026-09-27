import { Logger } from '../common/Logger';
import { Const, MOBILE_UA } from '../common/Const';
import { JdLinkParser } from '../common/JdLinkParser';
import { ProductSnapshot, MonitorTask } from '../model/MonitorTask';
import { HttpService, HttpResponse } from './HttpService';

/**
 * 商品信息服务
 * 负责：分享链接 -> skuId -> 价格 / 库存 / 标题 / 图片
 *
 * 京东数据来源（多路兜底，单路失效不影响整体）：
 *   1. p.3.cn/prices/mgets  —— 价格（轻量、稳定）
 *   2. item-soa.jd.com/getWareBusiness —— 库存/标题/店铺
 *   3. item.m.jd.com 商品页 HTML —— 兜底解析
 */
export class ProductService {

  /** 解析分享链接，得到 skuId；短链会自动跟随重定向 */
  static async resolveSkuId(raw: string): Promise<string> {
    const direct: string | null = JdLinkParser.extractSkuId(raw);
    // 能直接拿到 skuId，且不是短链场景 -> 直接返回
    if (direct && !JdLinkParser.isShortLink(raw)) {
      return direct;
    }

    // 短链：抽取 URL 后跟随跳转
    const url: string | null = JdLinkParser.extractUrl(raw);
    if (url) {
      try {
        const finalUrl: string = await HttpService.resolveRedirect(url);
        const sku: string | null = JdLinkParser.extractSkuId(finalUrl);
        if (sku) {
          Logger.info('短链解析成功 skuId=' + sku);
          return sku;
        }
      } catch (e) {
        Logger.warn('短链解析失败: ' + (e instanceof Error ? e.message : String(e)));
      }
    }

    // 兜底：直接返回数字匹配结果
    if (direct) {
      return direct;
    }
    throw new Error('无法从链接中识别商品 ID，请确认是京东商品分享链接');
  }

  /**
   * 获取商品完整快照
   * @param skuId 商品 id
   */
  static async fetchSnapshot(skuId: string): Promise<ProductSnapshot> {
    const snap: ProductSnapshot = new ProductSnapshot();
    snap.skuId = skuId;
    snap.fetchedAt = Date.now();

    // 1. 价格（核心，失败则整体判断为失败）
    const priceOk: boolean = await ProductService.fillPrice(snap, skuId);
    // 2. 库存 + 标题 + 图片
    await ProductService.fillBusiness(snap, skuId);

    snap.ok = priceOk && snap.price > 0;
    if (!snap.ok && !snap.errorMsg) {
      snap.errorMsg = '价格获取失败（可能是 Cookie 过期或商品已下架）';
    }
    return snap;
  }

  /** 价格接口：https://p.3.cn/prices/mgets?skuIds=J_<skuId>&type=1 */
  private static async fillPrice(snap: ProductSnapshot, skuId: string): Promise<boolean> {
    const url: string = `${Const.PRICE_API}?skuIds=J_${skuId}&type=1&pdbp=0&pdtk=&pdpin=&pdbp=0`;
    const resp: HttpResponse = await HttpService.get(url, `https://item.m.jd.com/product/${skuId}.html`, false);

    if (!resp.ok || !resp.body) {
      snap.errorMsg = '价格接口无响应';
      return false;
    }
    try {
      // 返回形如：[{"id":"J_100012043978","p":"5999.00","m":"6999.00","op":"6499.00"}]
      const arr: Array<Record<string, string>> = JSON.parse(resp.body) as Array<Record<string, string>>;
      if (!arr || arr.length === 0) {
        snap.errorMsg = '价格数据为空';
        return false;
      }
      const item: Record<string, string> = arr[0];
      snap.price = ProductService.toNumber(item['p']);
      snap.originPrice = ProductService.toNumber(item['m'] ?? item['op']);

      if (snap.price <= 0) {
        // p 为 -1 表示需登录或有特殊活动价，尝试用 m/op
        snap.price = snap.originPrice;
      }
      return snap.price > 0;
    } catch (e) {
      snap.errorMsg = '价格数据解析异常';
      Logger.error('fillPrice parse error: ' + (e instanceof Error ? e.message : String(e)));
      return false;
    }
  }

  /** 商品业务接口：库存 / 标题 / 图片 */
  private static async fillBusiness(snap: ProductSnapshot, skuId: string): Promise<void> {
    const url: string = `${Const.ITEM_API}?skuId=${skuId}&area=1_72_2799_0`;
    const resp: HttpResponse = await HttpService.get(url, `https://item.m.jd.com/product/${skuId}.html`, true);

    if (resp.ok && resp.body) {
      try {
        const data: Record<string, unknown> = JSON.parse(resp.body) as Record<string, unknown>;

        // 商品名
        if (!snap.title) {
          const name: unknown = data['name'] ?? '';
          if (typeof name === 'string') {
            snap.title = name;
          }
        }
        // 库存
        const stockDesc: unknown = data['stockDesc'] ?? data['stockTips'] ?? '';
        if (typeof stockDesc === 'string' && stockDesc.length > 0) {
          snap.stockText = stockDesc;
          snap.inStock = !/无货|售罄|下柜/.test(stockDesc);
        }
        // 显式的库存数量字段
        const stockNum: unknown = data['stock'] ?? data['stockCount'] ?? -1;
        if (typeof stockNum === 'number' && stockNum >= 0) {
          snap.inStock = stockNum > 0;
          if (stockNum > 0 && stockNum <= 10) {
            snap.stockText = `仅剩${stockNum}件`;
          }
        }
        // 图片
        const img: unknown = data['imagePath'] ?? data['imgPath'] ?? '';
        if (typeof img === 'string' && img.length > 0) {
          snap.imageUrl = JdLinkParser.normalizeImage(img);
        }
      } catch (e) {
        Logger.warn('fillBusiness parse error: ' + (e instanceof Error ? e.message : String(e)));
      }
    }

    // 标题 / 库存仍缺失 -> 用商品页 HTML 兜底
    if (!snap.title || snap.stockText.length === 0) {
      await ProductService.fillFromHtml(snap, skuId);
    }

    // 库存字段完全拿不到时，保守认为「可售」（价格有效通常意味着在售）
    if (snap.stockText.length === 0 && snap.price > 0) {
      snap.inStock = true;
      snap.stockText = '可售';
    }
  }

  /** 用移动端商品页 HTML 兜底提取标题与库存文案 */
  private static async fillFromHtml(snap: ProductSnapshot, skuId: string): Promise<void> {
    const url: string = `${Const.ITEM_PAGE}${skuId}.html`;
    const resp: HttpResponse = await HttpService.get(url, undefined, true);
    if (!resp.ok || !resp.body) {
      return;
    }
    const html: string = resp.body;

    if (!snap.title) {
      const m: RegExpMatchArray | null =
        html.match(/<title>([^<]{2,120})<\/title>/i) ?? html.match(/"name"\s*:\s*"([^"]{2,120})"/);
      if (m) {
        snap.title = m[1].replace(/-京东.*$/, '').trim();
      }
    }
    if (!snap.imageUrl) {
      const m: RegExpMatchArray | null = html.match(/https?:\/\/img\d+\.360buyimg\.com\/[^\s"'<>]+\.(?:jpg|png|webp)/i);
      if (m) {
        snap.imageUrl = JdLinkParser.normalizeImage(m[0]);
      }
    }
    if (snap.stockText.length === 0) {
      if (/无货|该商品已售罄|暂时缺货|已下柜/.test(html)) {
        snap.inStock = false;
        snap.stockText = '无货';
      } else if (/有货|现货|库存充足/.test(html)) {
        snap.inStock = true;
        snap.stockText = '有货';
      }
    }
  }

  /**
   * 加入购物车
   * 返回是否成功加入
   */
  static async addToCart(skuId: string, num: number = 1): Promise<boolean> {
    const url: string = `${Const.CART_API}?m=add&pcount=${num}&ptype=1&pid=${skuId}`;
    const resp: HttpResponse = await HttpService.postForm(
      url,
      { pcount: String(num), ptype: '1', pid: skuId },
      `https://item.m.jd.com/product/${skuId}.html`
    );
    if (!resp.ok) {
      Logger.warn('addToCart 请求失败 status=' + resp.status);
      return false;
    }
    // 京东加购成功一般返回 JSON 含 success，或 302 跳转到购物车
    const okFlag: boolean = resp.body.includes('"success"') || resp.body.includes('success:true') ||
      resp.status === 302 || resp.body.includes('cart');
    Logger.info('addToCart result=' + okFlag);
    return okFlag;
  }

  /** 构造可在外部浏览器/京东 App 打开的结算跳转链接 */
  static buildCheckoutUrl(skuId: string): string {
    return `${Const.ITEM_PAGE}${skuId}.html?cid=&goto=cart`;
  }

  /** 构造京东 App 深链，优先唤起原生 App */
  static buildAppDeepLink(skuId: string): string {
    const target: string = encodeURIComponent(`https://item.m.jd.com/product/${skuId}.html`);
    return `${Const.JD_APP_SCHEME}?url=${target}`;
  }

  private static toNumber(v: string | undefined): number {
    if (!v) {
      return 0;
    }
    const n: number = parseFloat(v);
    return isNaN(n) || n < 0 ? 0 : n;
  }
}
