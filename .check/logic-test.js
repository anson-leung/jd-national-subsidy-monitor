/**
 * 核心业务逻辑单元测试（Node 环境）
 * 把 .ets 中纯逻辑部分抽出来验证，确保算法正确
 */
const assert = require('assert');

// ============ 复刻 JdLinkParser 的逻辑做验证 ============
function extractSkuId(raw) {
  if (!raw) return null;
  const text = raw.trim();
  if (/^\d{6,20}$/.test(text)) return text;
  let m = text.match(/\/product\/(\d{6,20})\.html/);
  if (m) return m[1];
  m = text.match(/item\.jd\.com\/(\d{6,20})\.html/);
  if (m) return m[1];
  m = text.match(/[?&]sku(?:Id)?=(\d{6,20})/i);
  if (m) return m[1];
  m = text.match(/(\d{9,20})/);
  if (m) return m[1];
  return null;
}

function isShortLink(raw) {
  if (!raw) return false;
  return /(3\.cn|u\.jd\.com|jd\.com\/[a-zA-Z0-9]{4,8}$)/.test(raw.trim());
}

function extractUrl(raw) {
  if (!raw) return null;
  const m = raw.match(/https?:\/\/[^\s\u4e00-\u9fa5，,。、]+/);
  return m ? m[0] : null;
}

function normalizeImage(url) {
  if (!url) return '';
  let u = url.trim();
  if (u.startsWith('//')) u = 'https:' + u;
  u = u.replace(/\/n\d+\//, '/n1/');
  return u;
}

// ============ 复刻命中判定逻辑 ============
function checkHit(task, snap) {
  const priceHit = task.targetPrice > 0 && snap.price > 0 && snap.price <= task.targetPrice;
  const stockHit = !task.requireInStock || snap.inStock;
  return priceHit && stockHit;
}

// ============ 复刻 Cookie 解析 ============
function parseCookieText(text) {
  if (!text || text.trim().length === 0) return null;
  const acc = { ptKey: '', ptPin: '' };
  const keyMatch = text.match(/pt_key\s*=\s*([^;,\s]+)/);
  const pinMatch = text.match(/pt_pin\s*=\s*([^;,\s]+)/);
  if (keyMatch) acc.ptKey = keyMatch[1];
  if (pinMatch) acc.ptPin = decodeURIComponent(pinMatch[1]);
  if (!acc.ptKey && text.trim().length > 30 && !text.includes('=')) acc.ptKey = text.trim();
  return acc.ptKey.length > 0 ? acc : null;
}

// ============ 复刻价格解析 ============
function parsePrice(body) {
  const arr = JSON.parse(body);
  if (!arr || arr.length === 0) return { price: 0, origin: 0 };
  const item = arr[0];
  const toNum = (v) => { if (!v) return 0; const n = parseFloat(v); return isNaN(n) || n < 0 ? 0 : n; };
  let price = toNum(item['p']);
  const origin = toNum(item['m'] ?? item['op']);
  if (price <= 0) price = origin;
  return { price, origin };
}

// ============ 复刻退避算法 ============
function backoff(intervalMs, fails) {
  return Math.min(intervalMs * Math.pow(2, Math.min(fails, 4)), 60000);
}

// ============================================================
let pass = 0, fail = 0;
function t(name, fn) {
  try { fn(); console.log('  ✓ ' + name); pass++; }
  catch (e) { console.log('  ✗ ' + name + ' -> ' + e.message); fail++; }
}

console.log('\n【链接解析】');
t('移动端商品链接', () => {
  assert.strictEqual(extractSkuId('https://item.m.jd.com/product/100012043978.html'), '100012043978');
});
t('PC 端商品链接', () => {
  assert.strictEqual(extractSkuId('https://item.jd.com/100012043978.html'), '100012043978');
});
t('纯 skuId', () => {
  assert.strictEqual(extractSkuId('100012043978'), '100012043978');
});
t('带 query 的链接', () => {
  assert.strictEqual(extractSkuId('https://item.m.jd.com/product/100012043978.html?sceneval=2'), '100012043978');
});
t('分享口令文本（含短链）', () => {
  const raw = '【京东】https://3.cn/2abcDe ￥M8xYz1pQrS￥ 抢购中';
  assert.strictEqual(extractSkuId(raw), null);
  assert.strictEqual(isShortLink(raw), true);
  assert.strictEqual(extractUrl(raw), 'https://3.cn/2abcDe');
});
t('短链识别', () => {
  assert.strictEqual(isShortLink('https://3.cn/2abcDe'), true);
  assert.strictEqual(isShortLink('https://u.jd.com/abc123'), true);
  assert.strictEqual(isShortLink('https://item.m.jd.com/product/100012043978.html'), false);
});
t('skuId 参数形式', () => {
  assert.strictEqual(extractSkuId('https://x.jd.com/p?skuId=100012043978'), '100012043978');
});
t('无效输入返回 null', () => {
  assert.strictEqual(extractSkuId('随便一段中文没有数字'), null);
  assert.strictEqual(extractSkuId(''), null);
  assert.strictEqual(extractSkuId(null), null);
});
t('图片地址规范化', () => {
  assert.strictEqual(normalizeImage('//img14.360buyimg.com/n5/jfs/abc.jpg'), 'https://img14.360buyimg.com/n1/jfs/abc.jpg');
  assert.strictEqual(normalizeImage(''), '');
});

console.log('\n【价格解析】');
t('标准价格返回', () => {
  const r = parsePrice('[{"id":"J_100012043978","p":"5999.00","m":"6999.00","op":"6499.00"}]');
  assert.strictEqual(r.price, 5999);
  assert.strictEqual(r.origin, 6999);
});
t('p 为 -1 时回退到 m', () => {
  const r = parsePrice('[{"id":"J_1","p":"-1.00","m":"3999.00"}]');
  assert.strictEqual(r.price, 3999);
});
t('空数组返回 0', () => {
  const r = parsePrice('[]');
  assert.strictEqual(r.price, 0);
});
t('异常值不产生 NaN', () => {
  const r = parsePrice('[{"id":"J_1","p":"abc","m":""}]');
  assert.strictEqual(r.price, 0);
  assert.ok(!isNaN(r.price));
});

console.log('\n【命中判定】');
const baseTask = { targetPrice: 5000, requireInStock: true };
t('价格达标 + 有货 -> 命中', () => {
  assert.strictEqual(checkHit(baseTask, { price: 4800, inStock: true }), true);
});
t('价格达标但无货 -> 不命中', () => {
  assert.strictEqual(checkHit(baseTask, { price: 4800, inStock: false }), false);
});
t('不要求库存时无货也命中', () => {
  assert.strictEqual(checkHit({ targetPrice: 5000, requireInStock: false }, { price: 4800, inStock: false }), true);
});
t('价格高于目标 -> 不命中', () => {
  assert.strictEqual(checkHit(baseTask, { price: 5100, inStock: true }), false);
});
t('价格恰好等于目标 -> 命中（边界）', () => {
  assert.strictEqual(checkHit(baseTask, { price: 5000, inStock: true }), true);
});
t('目标价为 0（未设）-> 不命中', () => {
  assert.strictEqual(checkHit({ targetPrice: 0, requireInStock: true }, { price: 1, inStock: true }), false);
});
t('价格为 0（抓取失败）-> 不命中', () => {
  assert.strictEqual(checkHit(baseTask, { price: 0, inStock: true }), false);
});

console.log('\n【Cookie 解析】');
t('标准 Cookie 串', () => {
  const r = parseCookieText('pt_key=AAJxxxxx; pt_pin=jd_abc123; other=1');
  assert.strictEqual(r.ptKey, 'AAJxxxxx');
  assert.strictEqual(r.ptPin, 'jd_abc123');
});
t('URL 编码的 pt_pin 自动解码', () => {
  const r = parseCookieText('pt_key=AAJxxx; pt_pin=jd_%E4%B8%AD%E6%96%87;');
  assert.strictEqual(r.ptPin, 'jd_中文');
});
t('仅 pt_key 值无前缀', () => {
  const r = parseCookieText('AAJxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
  assert.strictEqual(r.ptKey, 'AAJxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
});
t('空输入返回 null', () => {
  assert.strictEqual(parseCookieText(''), null);
  assert.strictEqual(parseCookieText('   '), null);
});

console.log('\n【失败退避】');
t('退避序列 5s->10s->20s->40s->60s(封顶)', () => {
  assert.strictEqual(backoff(5000, 1), 10000);
  assert.strictEqual(backoff(5000, 2), 20000);
  assert.strictEqual(backoff(5000, 3), 40000);
  assert.strictEqual(backoff(5000, 4), 80000 > 60000 ? 60000 : 80000);
});
t('退避不超过 60 秒上限', () => {
  assert.strictEqual(backoff(5000, 10), 60000);
  assert.strictEqual(backoff(30000, 5), 60000);
});

console.log(`\n${'='.repeat(46)}`);
console.log(`通过 ${pass} 项，失败 ${fail} 项`);
process.exit(fail > 0 ? 1 : 0);
