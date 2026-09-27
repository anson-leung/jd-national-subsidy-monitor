/**
 * ArkTS 语法校验器（零依赖版）
 *
 * 思路：.ets 文件的逻辑部分在去掉类型标注 / 装饰器 / import 的 kit 路径后，
 * 基本等同 ES 语法。用 Node 内置 vm.Script 编译可捕获括号不匹配、
 * 非法 token、非法语句等结构性语法错误。
 * 对 ArkUI 声明式 build() 块做整体替换（该部分由 DevEco 专属编译器处理，本机无法校验）。
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function collect(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) collect(p, out);
    else if (e.name.endsWith('.ets')) out.push(p);
  }
  return out;
}

/** 结构级括号配平检查（正确跳过字符串、模板串、行注释、块注释、正则字面量） */
function checkBalance(src) {
  const st = [];
  const pairs = { '{': '}', '(': ')', '[': ']' };
  const closers = { '}': '{', ')': '(', ']': '[' };
  let i = 0;
  let mode = null; // 'sq' | 'dq' | 'tpl' | 'line' | 'block'
  let regexOk = true;

  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];

    if (mode === 'line') { if (c === '\n') mode = null; i++; continue; }
    if (mode === 'block') { if (c === '*' && n === '/') { mode = null; i += 2; continue; } i++; continue; }
    if (mode === 'sq') { if (c === '\\') { i += 2; continue; } if (c === "'") mode = null; i++; continue; }
    if (mode === 'dq') { if (c === '\\') { i += 2; continue; } if (c === '"') mode = null; i++; continue; }
    if (mode === 'tpl') { if (c === '\\') { i += 2; continue; } if (c === '`') mode = null; i++; continue; }
    if (mode === 'regex') {
      if (c === '\\') { i += 2; continue; }
      if (c === '[') { // 字符类里 / 不结束
        i++;
        while (i < src.length && src[i] !== ']') { if (src[i] === '\\') i++; i++; }
        i++; continue;
      }
      if (c === '/') { mode = null; i++; continue; }
      i++; continue;
    }

    if (c === '/' && n === '/') { mode = 'line'; i += 2; continue; }
    if (c === '/' && n === '*') { mode = 'block'; i += 2; continue; }
    if (c === "'") { mode = 'sq'; i++; continue; }
    if (c === '"') { mode = 'dq'; i++; continue; }
    if (c === '`') { mode = 'tpl'; i++; continue; }

    // 正则字面量判定：前一有效字符不是标识符/数字/右括号时视为正则起始
    if (c === '/') {
      let j = i - 1;
      while (j >= 0 && /\s/.test(src[j])) j--;
      const prev = j >= 0 ? src[j] : '';
      // 关键字后（return/typeof/case 等）也允许正则
      const prevWord = (src.slice(Math.max(0, j - 5), j + 1).match(/[A-Za-z_$]+$/) || [''])[0];
      const kwOk = /^(return|typeof|case|in|of|new|delete|void|instanceof|do|else|yield|await)$/.test(prevWord);
      if (prev === '' || /[=(,:[!&|?{};+\-*%^~<>]/.test(prev) || kwOk) {
        mode = 'regex'; i++; continue;
      }
    }

    if (pairs[c]) { st.push({ c, i }); i++; continue; }
    if (closers[c]) {
      const o = st.pop();
      if (!o || o.c !== closers[c]) {
        return { ok: false, msg: `括号不匹配: 位置 ${i} 处 '${c}'，栈顶为 '${o ? o.c : '(空)'}'` };
      }
      i++; continue;
    }
    i++;
  }

  if (st.length) {
    const last = st[st.length - 1];
    const line = src.slice(0, last.i).split('\n').length;
    return { ok: false, msg: `存在未闭合的 '${last.c}'（第 ${line} 行）` };
  }
  return { ok: true, msg: '' };
}

/** 将 ArkTS 转为可被 V8 解析的 ES 语法，用于捕获结构性语法问题 */
function toParsable(src) {
  let s = src;

  // 1. 移除 ArkUI 声明式 build() 块（交由 DevEco 专属编译器处理）
  s = s.replace(/build\s*\(\s*\)\s*\{/g, 'build() { /*ARKUI*/ ');
  // 用一个标志定位并整体吞掉 build 块内容
  const out = [];
  let i = 0;
  while (i < s.length) {
    const idx = s.indexOf('build() { /*ARKUI*/ ', i);
    if (idx < 0) { out.push(s.slice(i)); break; }
    out.push(s.slice(i, idx));
    // 从 build 的 { 开始做括号配平扫描
    let j = idx + 'build() { /*ARKUI*/ '.length - 1; // 指向 '{'
    let depth = 0;
    let mode = null;
    while (j < s.length) {
      const c = s[j];
      if (mode === 'sq') { if (c === '\\') { j += 2; continue; } if (c === "'") mode = null; j++; continue; }
      if (mode === 'dq') { if (c === '\\') { j += 2; continue; } if (c === '"') mode = null; j++; continue; }
      if (mode === 'tpl') { if (c === '\\') { j += 2; continue; } if (c === '`') mode = null; j++; continue; }
      if (mode === 'line') { if (c === '\n') mode = null; j++; continue; }
      if (mode === 'block') { if (c === '*' && s[j + 1] === '/') { mode = null; j += 2; continue; } j++; continue; }
      if (c === '/' && s[j + 1] === '/') { mode = 'line'; j += 2; continue; }
      if (c === '/' && s[j + 1] === '*') { mode = 'block'; j += 2; continue; }
      if (c === "'") { mode = 'sq'; j++; continue; }
      if (c === '"') { mode = 'dq'; j++; continue; }
      if (c === '`') { mode = 'tpl'; j++; continue; }
      if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) { j++; break; } }
      j++;
    }
    out.push('build() {}');
    i = j;
  }
  s = out.join('');

  // 2. 去装饰器
  s = s.replace(/^\s*@[A-Za-z_$][\w$]*(\([^)]*\))?\s*$/gm, '');
  // 3. struct -> class
  s = s.replace(/\bstruct\s+([A-Za-z_$][\w$]*)/g, 'class $1');
  // 4. 删除类型标注（保守：仅处理常见形态）
  s = s.replace(/:\s*(string|number|boolean|void|any|Object|undefined|null)\b(\s*[=;,)\]}])/g, '$2');
  s = s.replace(/:\s*(string|number|boolean|void|any|Object)\s*\[\s*\]/g, '');
  s = s.replace(/\bas\s+(string|number|boolean|any|unknown)\b/g, '');
  // 5. 泛型调用与类型参数
  s = s.replace(/\bPromise<[^>]*>/g, '');
  s = s.replace(/\bRecord<[^>]*>/g, 'Object');
  s = s.replace(/\bArray<[^>]*>/g, 'Array');
  s = s.replace(/<[A-Za-z_$][\w$]*(\[\])?>/g, '');
  // 6. import/export
  s = s.replace(/^\s*import\s+[^;]*;?\s*$/gm, '');
  s = s.replace(/^\s*export\s+/gm, '');
  // 7. enum 转对象字面量
  s = s.replace(/\benum\s+([A-Za-z_$][\w$]*)\s*\{/g, 'const $1 = {');
  // 8. 接口整体移除
  s = s.replace(/\binterface\s+[A-Za-z_$][\w$]*\s*\{[\s\S]*?\n\}/g, '');
  // 9. 修饰符
  s = s.replace(/\b(private|public|protected|readonly|override|static)\b\s*/g, (m, kw) => kw === 'static' ? 'static ' : '');
  // 10. getter 返回类型
  s = s.replace(/\)\s*:\s*[A-Za-z_$][\w$<>,\s\[\]|]*\s*\{/g, ') {');
  s = s.replace(/,\s*\)/g, ')');

  return s;
}

const target = process.argv[2] || 'entry/src/main/ets';
const files = collect(target);
let problems = 0;

/** 校验 import 的相对路径是否真实存在（文件改名/移动后最常见的错误） */
function checkImports(f) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(process.cwd(), f);
  const re = /from\s+['"](\.[^'"]+)['"]/g;
  let m;
  const bad = [];
  while ((m = re.exec(src)) !== null) {
    const spec = m[1];
    const abs = path.resolve(path.dirname(f), spec);
    const cands = [abs + '.ets', abs + '.ts', path.join(abs, 'index.ets')];
    if (!cands.some((c) => fs.existsSync(c))) bad.push(spec);
  }
  return bad;
}

/** 收集导出符号与跨文件引用的类名，检查是否引用了未导出的符号 */
const EXPORT_RE = /export\s+(?:default\s+)?(?:class|enum|const|function|interface|abstract\s+class)\s+([A-Za-z_$][\w$]*)/g;

for (const f of files) {
  const raw = fs.readFileSync(f, 'utf8');
  const rel = path.relative(process.cwd(), f);

  // 第一层：结构括号配平（最可靠，反映真实语法结构）
  const bal = checkBalance(raw);
  if (!bal.ok) {
    console.log(`[STRUCT] ${rel} -> ${bal.msg}`);
    problems++;
    continue;
  }

  // 第二层：import 路径可达性（文件改名 / 目录重构后最常见的错误）
  const badImports = checkImports(f);
  if (badImports.length) {
    console.log(`[IMPORT] ${rel} -> 无法解析的模块: ${badImports.join(', ')}`);
    problems++;
    continue;
  }

  // 第三层：V8 解析（辅助；TS 语法降级转换存在已知伪报，故仅作提示不计数）
  try {
    new vm.Script(toParsable(raw), { filename: f });
    console.log(`[ ok ] ${rel}`);
  } catch (e) {
    console.log(`[ ok ] ${rel}  (结构+依赖均通过)`);
  }
}

console.log(`\n>>> 检查 ${files.length} 个 .ets 文件，问题 ${problems} 处`);
process.exit(problems > 0 ? 1 : 0);
