/**
 * 商品监控任务数据模型
 */

/** 任务状态 */
export enum TaskStatus {
  /** 监控中 */
  RUNNING = 'RUNNING',
  /** 已命中目标条件 */
  HIT = 'HIT',
  /** 已暂停 */
  PAUSED = 'PAUSED',
  /** 已失效（Cookie 过期 / 商品下架） */
  INVALID = 'INVALID'
}

/** 单个监控任务 */
export class MonitorTask {
  /** 任务唯一 id */
  id: string = '';
  /** 商品 skuId */
  skuId: string = '';
  /** 商品名称 */
  title: string = '';
  /** 商品主图 */
  imageUrl: string = '';
  /** 原始分享链接 */
  shareUrl: string = '';

  /** 目标价格（低于等于该价视为命中） */
  targetPrice: number = 0;
  /** 是否要求有货才触发 */
  requireInStock: boolean = true;

  /** 最近一次抓取的价格 */
  lastPrice: number = 0;
  /** 是否可售/有货 */
  lastInStock: boolean = false;
  /** 最近一次检查时间戳 */
  lastCheckTime: number = 0;

  /** 任务状态 */
  status: TaskStatus = TaskStatus.RUNNING;
  /** 轮询间隔（毫秒） */
  intervalMs: number = 5000;
  /** 命中后是否自动加购 */
  autoAddCart: boolean = true;
  /** 创建时间戳 */
  createdAt: number = 0;

  constructor(partial?: Partial<MonitorTask>) {
    if (partial) {
      Object.assign(this, partial);
    }
  }
}

/** 商品运行时信息（每次抓取的最新快照） */
export class ProductSnapshot {
  skuId: string = '';
  title: string = '';
  /** 当前价（京东价/活动价） */
  price: number = 0;
  /** 划线价/市场价 */
  originPrice: number = 0;
  /** 是否可售 */
  inStock: boolean = false;
  /** 库存描述文本，如「有货」「仅剩2件」 */
  stockText: string = '';
  /** 商品图 */
  imageUrl: string = '';
  /** 抓取时间 */
  fetchedAt: number = 0;
  /** 抓取是否成功 */
  ok: boolean = false;
  /** 失败原因 */
  errorMsg: string = '';
}

/** 用户登录态 */
export class JdAccount {
  /** Cookie: pt_key */
  ptKey: string = '';
  /** Cookie: pt_pin */
  ptPin: string = '';
  /** 昵称（用于展示） */
  nickname: string = '';
  /** 登录时间 */
  loginAt: number = 0;
  /** 是否已登录 */
  get logged(): boolean {
    return this.ptKey.length > 0 && this.ptPin.length > 0;
  }
}
