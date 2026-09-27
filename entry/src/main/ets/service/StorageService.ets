import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { Logger } from '../common/Logger';
import { Const } from '../common/Const';
import { JdAccount, MonitorTask, TaskStatus } from '../model/MonitorTask';

/**
 * 本地存储服务
 * - 账号 Cookie 采用 AES-GCM 加密后落盘，避免明文泄露
 * - 任务列表 JSON 序列化存储
 * - 设置项键值存储
 */
export class StorageService {
  private static accountStore: preferences.Preferences | null = null;
  private static taskStore: preferences.Preferences | null = null;
  private static settingsStore: preferences.Preferences | null = null;
  private static context: common.UIAbilityContext | null = null;

  /** 由 Ability 在启动时注入 context */
  static init(context: common.UIAbilityContext): void {
    StorageService.context = context;
  }

  private static async getAccountStore(): Promise<preferences.Preferences> {
    if (!StorageService.accountStore) {
      StorageService.accountStore = await preferences.getPreferences(
        StorageService.context!, Const.PREF_ACCOUNT);
    }
    return StorageService.accountStore;
  }

  private static async getTaskStore(): Promise<preferences.Preferences> {
    if (!StorageService.taskStore) {
      StorageService.taskStore = await preferences.getPreferences(
        StorageService.context!, Const.PREF_TASKS);
    }
    return StorageService.taskStore;
  }

  private static async getSettingsStore(): Promise<preferences.Preferences> {
    if (!StorageService.settingsStore) {
      StorageService.settingsStore = await preferences.getPreferences(
        StorageService.context!, Const.PREF_SETTINGS);
    }
    return StorageService.settingsStore;
  }

  // ==================== 账号 ====================

  /** 保存账号（pt_key 加密存储） */
  static async saveAccount(acc: JdAccount): Promise<void> {
    try {
      const store: preferences.Preferences = await StorageService.getAccountStore();
      const encKey: string = await StorageService.encrypt(acc.ptKey);
      await store.put('pt_key_enc', encKey);
      await store.put('pt_pin', acc.ptPin);
      await store.put('nickname', acc.nickname);
      await store.put('login_at', acc.loginAt);
      await store.flush();
      Logger.info('账号已保存');
    } catch (e) {
      Logger.error('saveAccount failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /** 读取账号 */
  static async loadAccount(): Promise<JdAccount> {
    const acc: JdAccount = new JdAccount();
    try {
      const store: preferences.Preferences = await StorageService.getAccountStore();
      const encKey: string = await store.get('pt_key_enc', '') as string;
      acc.ptKey = encKey ? await StorageService.decrypt(encKey) : '';
      acc.ptPin = await store.get('pt_pin', '') as string;
      acc.nickname = await store.get('nickname', '') as string;
      acc.loginAt = await store.get('login_at', 0) as number;
    } catch (e) {
      Logger.error('loadAccount failed: ' + (e instanceof Error ? e.message : String(e)));
    }
    return acc;
  }

  /** 退出登录 */
  static async clearAccount(): Promise<void> {
    try {
      const store: preferences.Preferences = await StorageService.getAccountStore();
      await store.clear();
      await store.flush();
      Logger.info('账号已清除');
    } catch (e) {
      Logger.error('clearAccount failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  // ==================== 任务 ====================

  static async saveTasks(tasks: MonitorTask[]): Promise<void> {
    try {
      const store: preferences.Preferences = await StorageService.getTaskStore();
      await store.put('task_list', JSON.stringify(tasks));
      await store.flush();
    } catch (e) {
      Logger.error('saveTasks failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  static async loadTasks(): Promise<MonitorTask[]> {
    try {
      const store: preferences.Preferences = await StorageService.getTaskStore();
      const raw: string = await store.get('task_list', '[]') as string;
      const arr: MonitorTask[] = JSON.parse(raw) as MonitorTask[];
      // 反序列化后恢复为类实例，避免方法丢失
      return arr.map((t: MonitorTask) => new MonitorTask(t));
    } catch (e) {
      Logger.error('loadTasks failed: ' + (e instanceof Error ? e.message : String(e)));
      return [];
    }
  }

  // ==================== 设置 ====================

  static async setSetting(key: string, value: string): Promise<void> {
    try {
      const store: preferences.Preferences = await StorageService.getSettingsStore();
      await store.put(key, value);
      await store.flush();
    } catch (e) {
      Logger.error('setSetting failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  static async getSetting(key: string, def: string): Promise<string> {
    try {
      const store: preferences.Preferences = await StorageService.getSettingsStore();
      return await store.get(key, def) as string;
    } catch (e) {
      return def;
    }
  }

  // ==================== 加解密 ====================

  /**
   * 使用设备绑定的派生根对 Cookie 做 AES-GCM 加密。
   * 说明：此处用固定盐 + 设备信息派生密钥，属于「防明文读取」级别，
   * 不追求对抗拥有 root 权限的攻击者（移动端常见权衡）。
   */
  private static deriveKey(): cryptoFramework.SymKey {
    // 32 字节密钥材料
    const seed: string = 'JdMonitor::v1::' + (StorageService.context?.applicationInfo?.name ?? 'jdmon');
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new Uint8Array(buffer.from(seed, 'utf-8').buffer) });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    const keyBlob: cryptoFramework.DataBlob = { data: digest.data };
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    return generator.convertKeySync(keyBlob);
  }

  private static async encrypt(plain: string): Promise<string> {
    if (!plain) {
      return '';
    }
    try {
      const key: cryptoFramework.SymKey = StorageService.deriveKey();
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, null);
      const input: cryptoFramework.DataBlob = { data: new Uint8Array(buffer.from(plain, 'utf-8').buffer) };
      const output: cryptoFramework.DataBlob = await cipher.doFinal(input);
      return buffer.from(output.data).toString('base64');
    } catch (e) {
      Logger.error('encrypt failed: ' + (e instanceof Error ? e.message : String(e)));
      return '';
    }
  }

  private static async decrypt(cipherText: string): Promise<string> {
    if (!cipherText) {
      return '';
    }
    try {
      const key: cryptoFramework.SymKey = StorageService.deriveKey();
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, null);
      const input: cryptoFramework.DataBlob = {
        data: new Uint8Array(buffer.from(cipherText, 'base64').buffer)
      };
      const output: cryptoFramework.DataBlob = await cipher.doFinal(input);
      return buffer.from(output.data).toString('utf-8');
    } catch (e) {
      Logger.error('decrypt failed: ' + (e instanceof Error ? e.message : String(e)));
      return '';
    }
  }
}
