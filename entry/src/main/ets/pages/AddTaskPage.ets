import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { MonitorService } from '../service/MonitorService';
import { ProductService } from '../service/ProductService';
import { MonitorTask, ProductSnapshot } from '../model/MonitorTask';
import { Theme, formatPrice, INTERVAL_OPTIONS, intervalLabel } from '../common/UiUtil';
import { Logger } from '../common/Logger';

/**
 * 添加监控商品页
 * 流程：粘贴分享链接 → 自动解析 → 展示商品信息 → 设定目标价 → 保存
 */
@Entry
@Component
struct AddTaskPage {
  @State shareInput: string = '';
  @State parsing: boolean = false;
  @State parsed: boolean = false;

  // 解析出的商品信息
  @State skuId: string = '';
  @State title: string = '';
  @State imageUrl: string = '';
  @State currentPrice: number = 0;
  @State originPrice: number = 0;
  @State inStock: boolean = false;
  @State stockText: string = '';

  // 用户设置
  @State targetPriceStr: string = '';
  @State requireInStock: boolean = true;
  @State autoAddCart: boolean = true;
  @State intervalIdx: number = 1;
  @State errorMsg: string = '';

  async pasteFromClipboard(): Promise<void> {
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      const text: string = data.getPrimaryText();
      if (text && text.length > 0) {
        this.shareInput = text.trim();
        this.doParse();
      } else {
        promptAction.showToast({ message: '剪贴板为空', duration: 1500 });
      }
    } catch (e) {
      promptAction.showToast({ message: '读取剪贴板失败', duration: 1500 });
    }
  }

  async doParse(): Promise<void> {
    const raw: string = this.shareInput.trim();
    if (raw.length === 0) {
      promptAction.showToast({ message: '请先粘贴商品分享链接', duration: 1500 });
      return;
    }
    this.parsing = true;
    this.parsed = false;
    this.errorMsg = '';

    try {
      // 1. 解析 skuId（支持短链跟随跳转）
      const sku: string = await ProductService.resolveSkuId(raw);
      this.skuId = sku;

      // 2. 抓取商品快照
      const snap: ProductSnapshot = await ProductService.fetchSnapshot(sku);
      if (!snap.ok) {
        this.parsing = false;
        this.errorMsg = snap.errorMsg || '商品信息获取失败，请检查链接或重新登录';
        promptAction.showToast({ message: this.errorMsg, duration: 2500 });
        return;
      }

      this.title = snap.title || `商品 ${sku}`;
      this.imageUrl = snap.imageUrl;
      this.currentPrice = snap.price;
      this.originPrice = snap.originPrice;
      this.inStock = snap.inStock;
      this.stockText = snap.stockText || (snap.inStock ? '有货' : '无货');
      // 默认目标价：当前价下浮 5%，取整到元，方便用户微调
      const suggested: number = Math.max(1, Math.floor(snap.price * 0.95));
      this.targetPriceStr = String(suggested);
      this.parsed = true;

      Logger.info(`商品解析成功: ${this.title} 当前价 ${snap.price} 库存 ${this.stockText}`);
    } catch (e) {
      this.errorMsg = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: this.errorMsg, duration: 2500 });
    } finally {
      this.parsing = false;
    }
  }

  async save(): Promise<void> {
    const target: number = parseFloat(this.targetPriceStr);
    if (isNaN(target) || target <= 0) {
      promptAction.showToast({ message: '请输入有效的目标价格', duration: 1500 });
      return;
    }
    if (target > this.currentPrice && this.currentPrice > 0) {
      // 目标价高于当前价：会立即触发，提示确认
      promptAction.showToast({ message: '目标价高于当前价，保存后将立即触发下单', duration: 2500 });
    }

    const task: MonitorTask = new MonitorTask({
      skuId: this.skuId,
      title: this.title,
      imageUrl: this.imageUrl,
      shareUrl: this.shareInput.trim(),
      targetPrice: target,
      requireInStock: this.requireInStock,
      autoAddCart: this.autoAddCart,
      intervalMs: INTERVAL_OPTIONS[this.intervalIdx],
      lastPrice: this.currentPrice,
      lastInStock: this.inStock,
      lastCheckTime: Date.now()
    });

    await MonitorService.addTask(task);
    promptAction.showToast({ message: '监控任务已创建', duration: 1500 });
    router.back();
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textPrimary)
      .width('100%')
      .margin({ top: 16, bottom: 8 })
  }

  @Builder
  rowItem(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(Theme.textSecondary)
      Blank()
      Text(value).fontSize(14).fontColor(Theme.textPrimary)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: Theme.lineGray })
  }

  @Builder
  switchItem(label: string, desc: string, checked: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column() {
        Text(label).fontSize(14).fontColor(Theme.textPrimary)
        Text(desc).fontSize(11).fontColor(Theme.textPlaceholder).margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(Theme.brandRed)
        .onChange(onChange)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
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
        Text('添加监控商品')
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

      Scroll() {
        Column() {
          // ============ 链接输入区 ============
          this.sectionTitle('商品分享链接')

          Column() {
            TextArea({
              placeholder: '粘贴京东商品分享链接或口令，例如：\nhttps://item.m.jd.com/product/100012043978.html',
              text: this.shareInput
            })
              .width('100%')
              .height(88)
              .fontSize(13)
              .backgroundColor(Theme.cardBg)
              .borderRadius(8)
              .onChange((v: string) => {
                this.shareInput = v;
                if (this.parsed) {
                  this.parsed = false;
                }
              })

            Row() {
              Button('从剪贴板粘贴')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor(Theme.pageBg)
                .fontColor(Theme.textPrimary)
                .onClick(() => this.pasteFromClipboard())

              Button(this.parsing ? '解析中...' : '解析商品')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor(Theme.brandRed)
                .fontColor(Color.White)
                .margin({ left: 10 })
                .enabled(!this.parsing)
                .onClick(() => this.doParse())
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Theme.cardBg)
          .borderRadius(10)

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(12)
              .fontColor(Theme.brandRed)
              .width('100%')
              .margin({ top: 8 })
              .padding(10)
              .backgroundColor('#FFF0EF')
              .borderRadius(6)
          }

          // ============ 解析结果 ============
          if (this.parsed) {
            this.sectionTitle('商品信息')

            Column() {
              Row() {
                Image(this.imageUrl || $r('app.media.startIcon'))
                  .width(80)
                  .height(80)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(Theme.lineGray)
                  .alt($r('app.media.startIcon'))

                Column() {
                  Text(this.title)
                    .fontSize(14)
                    .fontColor(Theme.textPrimary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row() {
                    Text(formatPrice(this.currentPrice))
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.brandRed)
                    if (this.originPrice > this.currentPrice) {
                      Text(formatPrice(this.originPrice))
                        .fontSize(12)
                        .fontColor(Theme.textPlaceholder)
                        .decoration({ type: TextDecorationType.LineThrough })
                        .margin({ left: 8 })
                    }
                  }
                  .margin({ top: 6 })
                  Text(`库存：${this.stockText}`)
                    .fontSize(12)
                    .fontColor(this.inStock ? Theme.successGreen : Theme.textSecondary)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              this.rowItem('商品 ID', this.skuId)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)

            // ============ 下单条件 ============
            this.sectionTitle('下单条件')

            Column() {
              Row() {
                Text('目标价格')
                  .fontSize(14)
                  .fontColor(Theme.textPrimary)
                  .width(80)
                Text('¥')
                  .fontSize(16)
                  .fontColor(Theme.brandRed)
                TextInput({ text: this.targetPriceStr, placeholder: '请输入' })
                  .type(InputType.Number)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.brandRed)
                  .backgroundColor(Color.Transparent)
                  .padding(0)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.targetPriceStr = v; })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .border({ width: { bottom: 1 }, color: Theme.lineGray })

              Text(`当前价 ${formatPrice(this.currentPrice)}，低于等于目标价时将触发提醒`)
                .fontSize(11)
                .fontColor(Theme.textPlaceholder)
                .width('100%')
                .margin({ top: 8 })

              this.switchItem('必须有货才触发', '无货时不提醒，避免下单失败', this.requireInStock,
                (v: boolean) => { this.requireInStock = v; })

              this.switchItem('命中后自动加购', '自动加入购物车，方便快速结算', this.autoAddCart,
                (v: boolean) => { this.autoAddCart = v; })
            }
            .width('100%')
            .padding({ left: 12, right: 12 })
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)

            // ============ 轮询间隔 ============
            this.sectionTitle('检查频率')

            Column() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(INTERVAL_OPTIONS, (ms: number, idx: number) => {
                  Text(intervalLabel(ms))
                    .fontSize(13)
                    .fontColor(this.intervalIdx === idx ? Color.White : Theme.textPrimary)
                    .backgroundColor(this.intervalIdx === idx ? Theme.brandRed : Theme.pageBg)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => { this.intervalIdx = idx; })
                }, (ms: number) => String(ms))
              }
              .width('100%')

              Text('间隔越短越及时，但请求更频繁，可能触发京东风控，建议 5 秒以上')
                .fontSize(11)
                .fontColor(Theme.textPlaceholder)
                .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Theme.cardBg)
            .borderRadius(10)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 100 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)

      // 保存按钮
      if (this.parsed) {
        Button('开始监控')
          .width('92%')
          .height(46)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Theme.brandRed)
          .fontColor(Color.White)
          .borderRadius(23)
          .margin({ bottom: 16 })
          .onClick(() => this.save())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
