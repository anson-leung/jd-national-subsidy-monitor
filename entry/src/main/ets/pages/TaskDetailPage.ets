import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { MonitorService } from '../service/MonitorService';
import { ProductService } from '../service/ProductService';
import { AlertService } from '../service/AlertService';
import { MonitorTask, ProductSnapshot, TaskStatus } from '../model/MonitorTask';
import { Theme, formatPrice, formatTime, formatAgo, INTERVAL_OPTIONS, intervalLabel } from '../common/UiUtil';
import { Logger } from '../common/Logger';

/** 路由参数 */
interface DetailParams {
  taskId: string;
}

/**
 * 任务详情页
 * 展示实时数据、修改目标价、手动刷新、一键加购 / 跳转京东结算
 */
@Entry
@Component
struct TaskDetailPage {
  @State task: MonitorTask = new MonitorTask();
  @State loaded: boolean = false;
  @State refreshing: boolean = false;
  @State targetPriceStr: string = '';
  @State checking: boolean = false;

  private taskId: string = '';
  private context = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params = router.getParams() as DetailParams;
    if (params && params.taskId) {
      this.taskId = params.taskId;
      this.loadTask();
    }
  }

  loadTask(): void {
    const t: MonitorTask | undefined = MonitorService.getTask(this.taskId);
    if (t) {
      this.task = new MonitorTask(t);
      this.targetPriceStr = String(t.targetPrice);
      this.loaded = true;
    } else {
      promptAction.showToast({ message: '任务不存在', duration: 1500 });
      router.back();
    }
  }

  /** 手动刷新一次商品数据 */
  async doRefresh(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.checking = true;
    try {
      const snap: ProductSnapshot = await ProductService.fetchSnapshot(this.task.skuId);
      if (snap.ok) {
        await MonitorService.updateTask(Object.assign(new MonitorTask(this.task), {
          lastPrice: snap.price,
          lastInStock: snap.inStock,
          lastCheckTime: Date.now(),
          title: this.task.title || snap.title,
          imageUrl: this.task.imageUrl || snap.imageUrl
        }));
        this.loadTask();
        promptAction.showToast({ message: `当前价 ${formatPrice(snap.price)}`, duration: 1500 });
      } else {
        promptAction.showToast({ message: snap.errorMsg || '刷新失败', duration: 2000 });
      }
    } catch (e) {
      promptAction.showToast({ message: '刷新异常', duration: 1500 });
    } finally {
      this.refreshing = false;
      this.checking = false;
    }
  }

  /** 保存目标价修改 */
  async saveTargetPrice(v: string): Promise<void> {
    const target: number = parseFloat(v);
    if (isNaN(target) || target <= 0) {
      promptAction.showToast({ message: '目标价无效', duration: 1500 });
      return;
    }
    const updated: MonitorTask = new MonitorTask(this.task);
    updated.targetPrice = target;
    await MonitorService.updateTask(updated);
    this.task = updated;
    promptAction.showToast({ message: '目标价已更新', duration: 1500 });
  }

  /** 一键加购 */
  async addCart(): Promise<void> {
    promptAction.showToast({ message: '正在加购...', duration: 1500 });
    const ok: boolean = await ProductService.addToCart(this.task.skuId);
    if (ok) {
      promptAction.showToast({ message: '已加入购物车，正在跳转结算', duration: 2000 });
      setTimeout(() => this.openCheckout(), 600);
    } else {
      promptAction.showToast({ message: '加购失败（可能触发风控），已为你打开商品页', duration: 2500 });
      setTimeout(() => this.openItemPage(), 800);
    }
  }

  /** 跳转京东 App / 浏览器结算 */
  openCheckout(): void {
    // 优先唤起京东 App 的购物车页
    const appWant: Want = {
      bundleName: 'com.jingdong.app.mall',
      abilityName: 'com.jingdong.app.mall.MainFrameActivity'
    };
    this.context.startAbility(appWant).then(() => {
      Logger.info('已唤起京东 App');
    }).catch(() => {
      // 未安装京东 App，降级为浏览器打开商品页
      Logger.warn('京东 App 未安装，降级浏览器');
      this.openItemPage();
    });
  }

  /** 用浏览器打开商品页 */
  openItemPage(): void {
    const url: string = ProductService.buildCheckoutUrl(this.task.skuId);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    this.context.startAbility(want).then(() => {
      Logger.info('已打开商品页');
    }).catch((e: Error) => {
      promptAction.showToast({ message: '无法打开链接: ' + e.message, duration: 2000 });
    });
  }

  /** 测试提醒效果 */
  async testAlert(): Promise<void> {
    await AlertService.alert(
      '🔔 提醒测试',
      '这是命中目标价时的提醒效果，实际触发时会持续振动',
      99999,
      this.task.skuId
    );
    await MonitorService.toggleTask(this.taskId);
    this.loadTask();
  }

  async toggleTask(): Promise<void> {
    await MonitorService.toggleTask(this.taskId);
    this.loadTask();
  }

  async deleteTask(): Promise<void> {
    await MonitorService.removeTask(this.taskId);
    promptAction.showToast({ message: '任务已删除', duration: 1500 });
    router.back();
  }

  private statusText(): string {
    switch (this.task.status) {
      case TaskStatus.RUNNING: return '监控中';
      case TaskStatus.HIT: return '已命中目标价';
      case TaskStatus.PAUSED: return '已暂停';
      case TaskStatus.INVALID: return '登录态失效';
      default: return '未知';
    }
  }

  @Builder
  infoRow(label: string, value: string, valueColor?: string) {
    Row() {
      Text(label).fontSize(13).fontColor(Theme.textSecondary)
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor(valueColor ?? Theme.textPrimary)
    }
    .width('100%')
    .padding({ top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: Theme.lineGray })
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
        Text('监控详情')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('删除')
          .fontSize(14)
          .fontColor(Theme.brandRed)
          .width(40)
          .textAlign(TextAlign.End)
          .onClick(() => this.deleteTask())
      }
      .width('100%')
      .height(52)
      .backgroundColor(Theme.cardBg)
      .padding({ left: 8, right: 12 })

      if (this.loaded) {
        Scroll() {
          Column() {
            // ============ 商品卡 ============
            Column() {
              Row() {
                Image(this.task.imageUrl || $r('app.media.startIcon'))
                  .width(76)
                  .height(76)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(Theme.lineGray)
                  .alt($r('app.media.startIcon'))

                Column() {
                  Text(this.task.title || `商品 ${this.task.skuId}`)
                    .fontSize(14)
                    .fontColor(Theme.textPrimary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.statusText())
                    .fontSize(12)
                    .fontColor(this.task.status === TaskStatus.HIT ? Theme.brandRed :
                      this.task.status === TaskStatus.RUNNING ? Theme.successGreen : Theme.textSecondary)
                    .margin({ top: 6 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              // 价格对比条
              Row() {
                Column() {
                  Text('当前价')
                    .fontSize(11)
                    .fontColor(Theme.textSecondary)
                  Text(formatPrice(this.task.lastPrice))
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.textPrimary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column() {
                  Text('目标价')
                    .fontSize(11)
                    .fontColor(Theme.textSecondary)
                  Text(formatPrice(this.task.targetPrice))
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.brandRed)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .margin({ top: 16 })
              .padding({ top: 14, bottom: 14 })
              .border({ width: { top: 1 }, color: Theme.lineGray })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)

            // ============ 实时数据 ============
            Column() {
              this.infoRow('商品 ID', this.task.skuId)
              this.infoRow('库存状态',
                this.task.lastInStock ? '有货' : '无货',
                this.task.lastInStock ? Theme.successGreen : Theme.textSecondary)
              this.infoRow('最后检查', `${formatTime(this.task.lastCheckTime)} (${formatAgo(this.task.lastCheckTime)})`)
              this.infoRow('检查频率', intervalLabel(this.task.intervalMs))
              this.infoRow('命中后自动加购', this.task.autoAddCart ? '已开启' : '已关闭')
            }
            .width('100%')
            .padding({ left: 12, right: 12 })
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)
            .margin({ top: 10 })

            // ============ 目标价修改 ============
            Column() {
              Text('修改目标价')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
                .width('100%')
                .margin({ bottom: 10 })

              Row() {
                Text('¥').fontSize(16).fontColor(Theme.brandRed)
                TextInput({ text: this.targetPriceStr, placeholder: '输入目标价' })
                  .type(InputType.Number)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.brandRed)
                  .backgroundColor(Color.Transparent)
                  .padding(0)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.targetPriceStr = v; })

                Button('保存')
                  .height(34)
                  .fontSize(13)
                  .backgroundColor(Theme.brandRed)
                  .fontColor(Color.White)
                  .onClick(() => this.saveTargetPrice(this.targetPriceStr))
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
              .border({ width: { bottom: 1 }, color: Theme.lineGray })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)
            .margin({ top: 10 })

            // ============ 检查频率 ============
            Column() {
              Text('检查频率')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
                .width('100%')
                .margin({ bottom: 10 })

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(INTERVAL_OPTIONS, (ms: number) => {
                  Text(intervalLabel(ms))
                    .fontSize(13)
                    .fontColor(this.task.intervalMs === ms ? Color.White : Theme.textPrimary)
                    .backgroundColor(this.task.intervalMs === ms ? Theme.brandRed : Theme.pageBg)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => { this.changeInterval(ms); })
                }, (ms: number) => String(ms))
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)
            .margin({ top: 10 })

            // ============ 操作按钮 ============
            Column() {
              Button(this.refreshing ? '刷新中...' : '立即刷新商品数据')
                .width('100%')
                .height(44)
                .fontSize(15)
                .backgroundColor(Theme.cardBg)
                .fontColor(Theme.brandRed)
                .border({ width: 1, color: Theme.brandRed })
                .enabled(!this.refreshing)
                .onClick(() => this.doRefresh())

              Button(this.task.status === TaskStatus.RUNNING ? '暂停监控' : '恢复监控')
                .width('100%')
                .height(44)
                .fontSize(15)
                .backgroundColor(Theme.cardBg)
                .fontColor(Theme.textPrimary)
                .border({ width: 1, color: Theme.lineGray })
                .margin({ top: 10 })
                .onClick(() => this.toggleTask())

              Button('测试提醒效果')
                .width('100%')
                .height(44)
                .fontSize(15)
                .backgroundColor(Theme.cardBg)
                .fontColor(Theme.textSecondary)
                .border({ width: 1, color: Theme.lineGray })
                .margin({ top: 10 })
                .onClick(() => this.testAlert())
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 100 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)

        // ============ 底部购买按钮 ============
        Row() {
          Button('加入购物车')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .backgroundColor(Theme.cardBg)
            .fontColor(Theme.brandRed)
            .border({ width: 1, color: Theme.brandRed })
            .borderRadius(23)
            .onClick(() => this.addCart())

          Button('打开京东下单')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .backgroundColor(Theme.brandRed)
            .fontColor(Color.White)
            .borderRadius(23)
            .margin({ left: 10 })
            .onClick(() => this.openCheckout())
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 16, top: 8 })
        .backgroundColor(Theme.pageBg)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }

  private async changeInterval(ms: number): Promise<void> {
    const updated: MonitorTask = new MonitorTask(this.task);
    updated.intervalMs = ms;
    await MonitorService.updateTask(updated);
    this.task = updated;
  }
}
