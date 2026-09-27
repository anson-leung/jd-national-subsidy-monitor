import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MonitorService } from '../service/MonitorService';
import { LoginService } from '../service/LoginService';
import { StorageService } from '../service/StorageService';
import { MonitorTask, ProductSnapshot, TaskStatus, JdAccount } from '../model/MonitorTask';
import { TaskCard } from '../components/TaskCard';
import { Theme, formatPrice } from '../common/UiUtil';
import { AlertService } from '../service/AlertService';
import { Logger } from '../common/Logger';

/**
 * 首页：监控任务列表
 */
@Entry
@Component
struct Index {
  @State tasks: MonitorTask[] = [];
  @State logged: boolean = false;
  @State nickname: string = '';
  @State refreshing: boolean = false;
  @State runningCount: number = 0;
  @State hitCount: number = 0;

  private context = getContext(this) as common.UIAbilityContext;

  async aboutToAppear(): Promise<void> {
    // 注册监控回调（先注册再启动，避免首批结果丢失）
    MonitorService.setCallbacks(
      (task: MonitorTask, snap: ProductSnapshot) => {
        this.syncFromService();
      },
      (task: MonitorTask, snap: ProductSnapshot) => {
        this.syncFromService();
        promptAction.showToast({ message: `🎯 ${task.title || task.skuId} 已到目标价！`, duration: 3000 });
      }
    );

    await this.loadState();
    await MonitorService.start();
    this.syncFromService();
  }

  onPageShow(): void {
    this.loadState();
    this.syncFromService();
    // 从详情页返回时可能登录态有变化，重新注入到网络层
    this.refreshAccount();
  }

  async loadState(): Promise<void> {
    const acc: JdAccount = await StorageService.loadAccount();
    this.logged = acc.logged;
    this.nickname = acc.nickname || acc.ptPin;
  }

  async refreshAccount(): Promise<void> {
    const acc: JdAccount = await StorageService.loadAccount();
    this.logged = acc.logged;
    this.nickname = acc.nickname || acc.ptPin;
  }

  /** 从服务同步任务列表到 UI 状态 */
  syncFromService(): void {
    const list: MonitorTask[] = MonitorService.getAllTasks();
    // 用新数组触发 UI 刷新（@State 需要引用变化）
    this.tasks = list.map((t: MonitorTask) => new MonitorTask(t));
    this.runningCount = list.filter((t: MonitorTask) => t.status === TaskStatus.RUNNING).length;
    this.hitCount = list.filter((t: MonitorTask) => t.status === TaskStatus.HIT).length;
  }

  async toggleTask(task: MonitorTask): Promise<void> {
    await MonitorService.toggleTask(task.id);
    this.syncFromService();
  }

  goAdd(): void {
    if (!this.logged) {
      promptAction.showToast({ message: '请先登录京东账号', duration: 1500 });
      router.pushUrl({ url: 'pages/LoginPage' });
      return;
    }
    router.pushUrl({ url: 'pages/AddTaskPage' });
  }

  goDetail(task: MonitorTask): void {
    router.pushUrl({
      url: 'pages/TaskDetailPage',
      params: { taskId: task.id }
    });
  }

  @Builder
  header() {
    Column() {
      Row() {
        Column() {
          Text('京东国补监控')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.logged ? `已登录：${this.nickname}` : '未登录，点击右侧登录')
            .fontSize(12)
            .fontColor('#FFD9D6')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.logged ? '切换账号' : '去登录')
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('#33FFFFFF')
          .onClick(() => { router.pushUrl({ url: 'pages/LoginPage' }); })

        Text('设置')
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('#33FFFFFF')
          .margin({ left: 8 })
          .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 统计
      Row() {
        this.statItem(`${this.runningCount}`, '监控中')
        this.statItem(`${this.hitCount}`, '已命中')
        this.statItem(`${this.tasks.length}`, '任务总数')
      }
      .width('100%')
      .margin({ top: 16 })
      .justifyContent(FlexAlign.SpaceAround)
      .backgroundColor('#22FFFFFF')
      .borderRadius(10)
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 20 })
    .backgroundColor(Theme.brandRed)
  }

  @Builder
  statItem(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text(label)
        .fontSize(11)
        .fontColor('#FFD9D6')
        .margin({ top: 2 })
    }
  }

  @Builder
  emptyView() {
    Column() {
      Text('📦')
        .fontSize(48)
        .margin({ bottom: 12 })
      Text('还没有监控任务')
        .fontSize(15)
        .fontColor(Theme.textSecondary)
      Text('点击下方按钮，粘贴京东商品分享链接开始监控')
        .fontSize(12)
        .fontColor(Theme.textPlaceholder)
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.header()

      if (this.tasks.length === 0) {
        this.emptyView()
      } else {
        List({ space: 10 }) {
          ListItem() {
            Row() {
              Text('下拉可刷新')
                .fontSize(11)
                .fontColor(Theme.textPlaceholder)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 8, bottom: 4 })
          }
          .width('100%')

          ForEach(this.tasks, (task: MonitorTask) => {
            ListItem() {
              TaskCard({
                task: task,
                onTap: (t: MonitorTask) => this.goDetail(t),
                onToggle: (t: MonitorTask) => this.toggleTask(t)
              })
            }
            .width('100%')
          }, (task: MonitorTask) => task.id + '_' + task.status + '_' + task.lastPrice + '_' + task.lastCheckTime)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 8, bottom: 80 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      // 底部添加按钮
      Button('+  添加监控商品')
        .width('92%')
        .height(46)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(Theme.brandRed)
        .fontColor(Color.White)
        .borderRadius(23)
        .margin({ bottom: 16 })
        .onClick(() => this.goAdd())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
