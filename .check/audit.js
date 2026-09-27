/**
 * 工程一致性审查
 * 1. 路由页面是否已注册
 * 2. $r() 引用的媒体资源是否存在
 * 3. ArkTS 禁用特性（any / var）
 * 4. module.json5 / app.json5 引用的字符串资源是否定义
 */
const fs = require('fs');
const path = require('path');

function walk(d, o = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, o);
    else if (p.endsWith('.ets')) o.push(p);
  }
  return o;
}

const files = walk('entry/src/main/ets');
let issues = 0;

// ---- 1. 路由注册检查 ----
const pages = JSON.parse(fs.readFileSync('entry/src/main/resources/base/profile/main_pages.json', 'utf8')).src;
console.log('注册页面: ' + pages.join(', '));
const reRoute = /url:\s*['"]pages\/([A-Za-z0-9_]+)['"]/g;
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = reRoute.exec(s)) !== null) {
    if (!pages.includes('pages/' + m[1])) {
      console.log('  [X] 未注册路由: ' + m[1] + ' (在 ' + path.basename(f) + ')');
      issues++;
    }
  }
}

// ---- 2. 媒体资源存在性 ----
const reRes = /\$r\(\s*['"]app\.(media|string|color)\.([A-Za-z0-9_]+)['"]\s*\)/g;
const strNames = JSON.parse(fs.readFileSync('entry/src/main/resources/base/element/string.json', 'utf8')).string.map((x) => x.name);
const colorNames = JSON.parse(fs.readFileSync('entry/src/main/resources/base/element/color.json', 'utf8')).color.map((x) => x.name);
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = reRes.exec(s)) !== null) {
    const kind = m[1];
    const name = m[2];
    if (kind === 'media') {
      const p = 'entry/src/main/resources/base/media/' + name + '.png';
      if (!fs.existsSync(p)) {
        console.log('  [X] 缺少 media: ' + name + ' (在 ' + path.basename(f) + ')');
        issues++;
      }
    } else if (kind === 'string') {
      if (!strNames.includes(name)) {
        console.log('  [X] 缺少 string: ' + name + ' (在 ' + path.basename(f) + ')');
        issues++;
      }
    } else if (kind === 'color') {
      if (!colorNames.includes(name)) {
        console.log('  [X] 缺少 color: ' + name + ' (在 ' + path.basename(f) + ')');
        issues++;
      }
    }
  }
}

// ---- 3. ArkTS 禁用特性 ----
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach((ln, i) => {
    const code = ln.replace(/\/\/.*$/, '');
    if (/^\s*\*/.test(code)) return;
    if (/\bany\b/.test(code)) {
      console.log('  [!] any 类型: ' + path.basename(f) + ':' + (i + 1));
      issues++;
    }
    if (/\bvar\s+[A-Za-z_$]/.test(code)) {
      console.log('  [!] var 声明: ' + path.basename(f) + ':' + (i + 1));
      issues++;
    }
  });
}

// ---- 4. module.json5 字符串引用 ----
const mod = fs.readFileSync('entry/src/main/module.json5', 'utf8');
const reModStr = /\$string:([A-Za-z0-9_]+)/g;
let m2;
while ((m2 = reModStr.exec(mod)) !== null) {
  if (!strNames.includes(m2[1])) {
    console.log('  [X] module.json5 引用未定义字符串: ' + m2[1]);
    issues++;
  }
}
// media 引用
const mediaInModule = /\$media:([A-Za-z0-9_]+)/g;
while ((m2 = mediaInModule.exec(mod)) !== null) {
  const p = 'entry/src/main/resources/base/media/' + m2[1] + '.png';
  if (!fs.existsSync(p)) {
    console.log('  [X] module.json5 引用未定义 media: ' + m2[1]);
    issues++;
  }
}

// ---- 5. AppScope 字符串引用 ----
const appStr = JSON.parse(fs.readFileSync('AppScope/resources/base/element/string.json', 'utf8')).string.map((x) => x.name);
const appJson = fs.readFileSync('AppScope/app.json5', 'utf8');
const reAppStr = /\$string:([A-Za-z0-9_]+)/g;
while ((m2 = reAppStr.exec(appJson)) !== null) {
  if (!appStr.includes(m2[1])) {
    console.log('  [X] app.json5 引用未定义字符串: ' + m2[1]);
    issues++;
  }
}
const reAppMedia = /\$media:([A-Za-z0-9_]+)/g;
while ((m2 = reAppMedia.exec(appJson)) !== null) {
  const p = 'AppScope/resources/base/media/' + m2[1] + '.png';
  if (!fs.existsSync(p)) {
    console.log('  [X] app.json5 引用未定义 media: ' + m2[1]);
    issues++;
  }
}

// ---- 6. monitorService 中残留的无效 AlertService 空判断 ----
const monSrv = fs.readFileSync('entry/src/main/ets/service/MonitorService.ets', 'utf8');
if (/if\s*\(\s*AlertService\s*\)/.test(monSrv)) {
  console.log('  [!] MonitorService 存在 `if (AlertService)` 永真判断，应移除');
  issues++;
}

console.log('\n>>> 一致性问题: ' + issues + ' 处');
process.exit(issues > 0 ? 1 : 0);
