/**
 * 通用 UI 工具与常量
 */

/** 格式化价格：5999 -> ¥5,999.00 */
export function formatPrice(v: number): string {
  if (!v || v <= 0) {
    return '--';
  }
  return '¥' + v.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** 格式化时间戳为 HH:mm:ss */
export function formatTime(ts: number): string {
  if (!ts) {
    return '--:--:--';
  }
  const d = new Date(ts);
  const p = (n: number): string => (n < 10 ? '0' + n : String(n));
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

/** 相对时间：刚刚 / 3秒前 / 2分钟前 */
export function formatAgo(ts: number): string {
  if (!ts) {
    return '尚未检查';
  }
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 3) {
    return '刚刚';
  }
  if (diff < 60) {
    return `${diff} 秒前`;
  }
  if (diff < 3600) {
    return `${Math.floor(diff / 60)} 分钟前`;
  }
  return `${Math.floor(diff / 3600)} 小时前`;
}

/** 轮询间隔选项 */
export const INTERVAL_OPTIONS: number[] = [3000, 5000, 10000, 30000, 60000];

export function intervalLabel(ms: number): string {
  const s = Math.round(ms / 1000);
  return s >= 60 ? `${s / 60} 分钟` : `${s} 秒`;
}

/** 主题色，与 resources 中 color.json 保持一致 */
export class Theme {
  static readonly brandRed: string = '#E1251B';
  static readonly brandRedLight: string = '#FF4D45';
  static readonly pageBg: string = '#F5F5F5';
  static readonly cardBg: string = '#FFFFFF';
  static readonly textPrimary: string = '#1A1A1A';
  static readonly textSecondary: string = '#8A8A8A';
  static readonly textPlaceholder: string = '#BBBBBB';
  static readonly lineGray: string = '#EEEEEE';
  static readonly successGreen: string = '#00B578';
  static readonly warnOrange: string = '#FF8F1F';
}

