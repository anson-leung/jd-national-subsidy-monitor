import { Logger } from '../common/Logger';
import { Const } from '../common/Const';
import { MonitorTask, ProductSnapshot, TaskStatus } from '../model/MonitorTask';
import { ProductService } from './ProductService';
import { AlertService } from './AlertService';
import { HttpService } from './HttpService';
import { StorageService } from './StorageService';

/** 任务状态变更回调 */
export type TaskUpdateCallback = (task: MonitorTask, snap: ProductSnapshot) => void;
/** 命中回调 */
export type HitCallback = (task: MonitorTask, snap: ProductSnapshot) => void;

/**
 * 监控调度服务
 *
 * 设计要点：
 * - 每个任务独立计时器，互不阻塞（一个任务网络慢不影响其他任务）
 * - 失败退避：连续失败时自动延长轮询间隔，避免死循环打满请求
 * - Cookie 失效识别：命中登录失效特征立即暂停任务并提示
 * - 命中后自动降频：命中价后仍继续监控，但间隔放大，避免重复提醒
 */
export class MonitorService {
  private static timers: Map<string, number> = new Map();
  private static tasks: Map<string, MonitorTask> = new Map();
  /** 每个任务的连续失败次数，用于退避 */
  private static failCounts: Map<string, number> = new Map();
  /** 已提醒过的任务（同一状态不重复提醒） */
  private static notified: Set<string> = new Set();

  private static onUpdate: TaskUpdateCallback | null = null;
  private static onHit: HitCallback | null = null;
  private static running: boolean = false;

  /** 注册回调 */
  static setCallbacks(onUpdate: TaskUpdateCallback, onHit: HitCallback): void {
    MonitorService.onUpdate = onUpdate;
    MonitorService.onHit = onHit;
  }

  /** 载入任务并启动调度 */
  static async start(): Promise<void> {
    if (MonitorService.running) {
      Logger.info('监控已在运行中');
      return;
    }
    const list: MonitorTask[] = await StorageService.loadTasks();
    for (const t of list) {
      MonitorService.tasks.set(t.id, t);
      if (t.status === TaskStatus.RUNNING) {
        MonitorService.schedule(t.id, 0);
      }
    }
    MonitorService.running = true;
    Logger.info(`监控服务启动，共 ${list.length} 个任务`);
  }

  /** 停止全部调度 */
  static stop(): void {
    MonitorService.timers.forEach((timerId: number) => {
      clearTimeout(timerId);
    });
    MonitorService.timers.clear();
    MonitorService.running = false;
    Logger.info('监控服务已停止');
  }

  /** 新增任务 */
  static async addTask(task: MonitorTask): Promise<void> {
    if (!task.id) {
      task.id = `t_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    }
    task.createdAt = Date.now();
    task.status = TaskStatus.RUNNING;
    MonitorService.tasks.set(task.id, task);
    await MonitorService.persist();
    MonitorService.schedule(task.id, 0);
  }

  /** 删除任务 */
  static async removeTask(id: string): Promise<void> {
    MonitorService.clearTimer(id);
    MonitorService.tasks.delete(id);
    MonitorService.failCounts.delete(id);
    MonitorService.notified.delete(id);
    await MonitorService.persist();
  }

  /** 更新任务（如修改目标价） */
  static async updateTask(task: MonitorTask): Promise<void> {
    MonitorService.tasks.set(task.id, task);
    await MonitorService.persist();
    // 目标价变化后重置提醒状态，允许重新命中提醒
    MonitorService.notified.delete(task.id);
    if (task.status === TaskStatus.RUNNING && !MonitorService.timers.has(task.id)) {
      MonitorService.schedule(task.id, 0);
    }
  }

  /** 暂停 / 恢复任务 */
  static async toggleTask(id: string): Promise<void> {
    const task: MonitorTask | undefined = MonitorService.tasks.get(id);
    if (!task) {
      return;
    }
    if (task.status === TaskStatus.RUNNING) {
      task.status = TaskStatus.PAUSED;
      MonitorService.clearTimer(id);
    } else {
      task.status = TaskStatus.RUNNING;
      MonitorService.failCounts.delete(id);
      MonitorService.schedule(id, 0);
    }
    await MonitorService.persist();
    Logger.info(`任务 ${id} 状态 -> ${task.status}`);
  }

  /** 获取全部任务（副本，防止外部直接改内部状态） */
  static getAllTasks(): MonitorTask[] {
    const out: MonitorTask[] = [];
    MonitorService.tasks.forEach((t: MonitorTask) => out.push(t));
    return out.sort((a: MonitorTask, b: MonitorTask) => b.createdAt - a.createdAt);
  }

  static getTask(id: string): MonitorTask | undefined {
    return MonitorService.tasks.get(id);
  }

  // ==================== 内部实现 ====================

  private static clearTimer(id: string): void {
    const timerId: number | undefined = MonitorService.timers.get(id);
    if (timerId !== undefined) {
      clearTimeout(timerId);
      MonitorService.timers.delete(id);
    }
  }

  /** 安排下一次检查 */
  private static schedule(id: string, delayMs: number): void {
    MonitorService.clearTimer(id);
    const task: MonitorTask | undefined = MonitorService.tasks.get(id);
    if (!task || task.status !== TaskStatus.RUNNING) {
      return;
    }
    const timerId: number = setTimeout(() => {
      MonitorService.timers.delete(id);
      MonitorService.check(id);
    }, delayMs);
    MonitorService.timers.set(id, timerId);
  }

  /** 执行一次检查 */
  private static async check(id: string): Promise<void> {
    const task: MonitorTask | undefined = MonitorService.tasks.get(id);
    if (!task || task.status !== TaskStatus.RUNNING) {
      return;
    }

    let snap: ProductSnapshot;
    try {
      snap = await ProductService.fetchSnapshot(task.skuId);
    } catch (e) {
      snap = new ProductSnapshot();
      snap.skuId = task.skuId;
      snap.ok = false;
      snap.errorMsg = e instanceof Error ? e.message : String(e);
    }

    // 首次抓取时补全商品基础信息
    if (snap.ok) {
      let metaChanged: boolean = false;
      if (!task.title && snap.title) {
        task.title = snap.title;
        metaChanged = true;
      }
      if (!task.imageUrl && snap.imageUrl) {
        task.imageUrl = snap.imageUrl;
        metaChanged = true;
      }
      if (metaChanged) {
        await MonitorService.persist();
      }
    }

    task.lastPrice = snap.price;
    task.lastInStock = snap.inStock;
    task.lastCheckTime = Date.now();

    // 失败处理：连续失败退避
    if (!snap.ok) {
      const fails: number = (MonitorService.failCounts.get(id) ?? 0) + 1;
      MonitorService.failCounts.set(id, fails);

      // Cookie 失效特征检测
      if (/(登录|验证|login)/i.test(snap.errorMsg)) {
        task.status = TaskStatus.INVALID;
        await MonitorService.persist();
        await AlertService.notify('⚠️ 登录态已失效', '请重新登录京东账号以恢复监控', Const.NOTIFY_BASE_ID);
        Logger.warn('任务 ' + id + ' 因登录失效暂停');
        return;
      }

      // 指数退避：5s -> 10s -> 20s -> 最多 60s
      const backoff: number = Math.min(task.intervalMs * Math.pow(2, Math.min(fails, 4)), 60000);
      Logger.warn(`任务 ${id} 第 ${fails} 次失败，${backoff}ms 后重试`);
      if (MonitorService.onUpdate) {
        MonitorService.onUpdate(task, snap);
      }
      MonitorService.schedule(id, backoff);
      return;
    }

    // 成功则重置失败计数
    MonitorService.failCounts.delete(id);

    // 命中判定
    const priceHit: boolean = task.targetPrice > 0 && snap.price > 0 && snap.price <= task.targetPrice;
    const stockHit: boolean = !task.requireInStock || snap.inStock;

    if (priceHit && stockHit) {
      task.status = TaskStatus.HIT;
      // 只在状态从未命中变为命中时提醒一次，避免重复轰炸
      if (!MonitorService.notified.has(id)) {
        MonitorService.notified.add(id);
        await MonitorService.handleHit(task, snap);
      }
      MonitorService.clearTimer(id);
      await MonitorService.persist();
      if (MonitorService.onUpdate) {
        MonitorService.onUpdate(task, snap);
      }
      return;
    }

    // 未命中：恢复 RUNNING（若之前是 HIT 但价格又涨回去了）
    if (task.status === TaskStatus.HIT) {
      task.status = TaskStatus.RUNNING;
      MonitorService.notified.delete(id);
    }

    await MonitorService.persist();
    if (MonitorService.onUpdate) {
      MonitorService.onUpdate(task, snap);
    }
    MonitorService.schedule(id, Math.max(task.intervalMs, Const.MIN_INTERVAL));
  }

  /** 命中后的处理：加购 + 强提醒 */
  private static async handleHit(task: MonitorTask, snap: ProductSnapshot): Promise<void> {
    Logger.info(`🎯 命中目标价！task=${task.id} price=${snap.price} target=${task.targetPrice}`);

    // 自动加购（失败不阻断提醒，加购本身可能因风控失败）
    if (task.autoAddCart) {
      try {
        const added: boolean = await ProductService.addToCart(task.skuId);
        Logger.info('自动加购结果: ' + added);
      } catch (e) {
        Logger.warn('自动加购异常: ' + (e instanceof Error ? e.message : String(e)));
      }
    }

    // 强提醒
    const notifyId: number = Const.NOTIFY_BASE_ID + Math.floor(Math.random() * 1000);
    await AlertService.alertHit(task.title || task.skuId, snap.price, task.targetPrice, notifyId, task.skuId);

    // 触发业务回调（UI 层可用于弹窗 / 自动跳转）
    if (MonitorService.onHit) {
      MonitorService.onHit(task, snap);
    }
  }

  /** 持久化当前任务列表 */
  private static async persist(): Promise<void> {
    await StorageService.saveTasks(MonitorService.getAllTasks());
  }
}
