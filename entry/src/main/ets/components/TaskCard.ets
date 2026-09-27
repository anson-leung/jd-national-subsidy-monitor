import { MonitorTask, TaskStatus } from '../model/MonitorTask';
import { formatPrice, formatAgo, Theme } from '../common/UiUtil';

/**
 * 任务卡片组件
 * 展示商品图、标题、当前价 / 目标价、库存状态、最后检查时间
 */
@Component
export struct TaskCard {
  @Prop task: MonitorTask;
  onTap?: (task: MonitorTask) => void;
  onToggle?: (task: MonitorTask) => void;

  private statusText(): string {
    switch (this.task.status) {
      case TaskStatus.RUNNING:
        return '监控中';
      case TaskStatus.HIT:
        return '已命中';
      case TaskStatus.PAUSED:
        return '已暂停';
      case TaskStatus.INVALID:
        return '登录失效';
      default:
        return '未知';
    }
  }

  private statusColor(): string {
    switch (this.task.status) {
      case TaskStatus.RUNNING:
        return Theme.successGreen;
      case TaskStatus.HIT:
        return Theme.brandRed;
      case TaskStatus.INVALID:
        return Theme.warnOrange;
      default:
        return Theme.textSecondary;
    }
  }

  /** 价格是否已达到目标价 */
  private priceReached(): boolean {
    return this.task.targetPrice > 0 && this.task.lastPrice > 0 && this.task.lastPrice <= this.task.targetPrice;
  }

  build() {
    Column() {
      Row() {
        // 商品图
        Image(this.task.imageUrl || $r('app.media.startIcon'))
          .width(84)
          .height(84)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.lineGray)
          .alt($r('app.media.startIcon'))

        // 商品信息
        Column() {
          Text(this.task.title || `商品 ${this.task.skuId}`)
            .fontSize(14)
            .fontColor(Theme.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .lineHeight(19)

          Blank()

          Row() {
            // 当前价
            Text(formatPrice(this.task.lastPrice))
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.priceReached() ? Theme.brandRed : Theme.textPrimary)

            Text(`目标 ${formatPrice(this.task.targetPrice)}`)
              .fontSize(12)
              .fontColor(Theme.textSecondary)
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)

          Row() {
            // 库存标签
            Text(this.task.lastInStock ? '有货' : '无货')
              .fontSize(10)
              .fontColor(this.task.lastInStock ? Theme.successGreen : Theme.textSecondary)
              .backgroundColor(this.task.lastInStock ? '#E8F9F2' : '#F0F0F0')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)

            Text(formatAgo(this.task.lastCheckTime))
              .fontSize(11)
              .fontColor(Theme.textPlaceholder)
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .layoutWeight(1)
        .height(84)
        .margin({ left: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 底部分隔与状态栏
      Row() {
        Text(this.statusText())
          .fontSize(12)
          .fontColor(this.statusColor())

        Blank()

        Text(this.task.status === TaskStatus.RUNNING ? '暂停' : '开始')
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor(Theme.pageBg)
          .onClick(() => {
            if (this.onToggle) {
              this.onToggle(this.task);
            }
          })
      }
      .width('100%')
      .margin({ top: 10 })
      .padding({ top: 10 })
      .border({ width: { top: 1 }, color: Theme.lineGray })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Theme.cardBg)
    .borderRadius(12)
    .onClick(() => {
      if (this.onTap) {
        this.onTap(this.task);
      }
    })
  }
}
