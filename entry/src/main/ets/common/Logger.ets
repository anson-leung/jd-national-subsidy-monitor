import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0F01;
const TAG: string = 'JdMonitor';

export class Logger {
  static debug(msg: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', msg);
  }

  static info(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', msg);
  }
}
