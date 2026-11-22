/* Name editor, browser side. The game's side is src/name-editor/main.lua: keep the two in step (same ids, same token model, same markup builders).
   Only the icon markup (a placeholder atlas here, the game's UI images there), the keyboard and the clipboard differ. */
(function () {
'use strict';
const DATA = window.NAME_EDITOR_DATA;
const ICPFX = '\\gffffffff00000', CPFX = '\\cff';
const TABS = ['col', 'ico', 'grd'];
const MAXRAW = 63;      // what the character creation's name field takes (measured in the game)
const st = {toks: [], caret: 0, recent: [], tab: 0, gA: 'ED1C24', gB: 'FFF14E', slot: 'A', scope: 'all', selhex: null, marks: true};
const $ = (s) => document.querySelector(s);
let blinkOn = true;

/* model */
function serialize(toks) { return (toks || st.toks).map(k => k.t === 'ch' ? k.v : k.t === 'ic' ? ICPFX + k.v : CPFX + k.v).join(''); }
function parse(s) {
  const out = [], arr = Array.from(s);          // code points: a pasted emoji is one token
  let pos = 0;
  while (pos < arr.length) {
    const rest = arr.slice(pos, pos + 20).join('');
    let m;
    if ((m = /^\\gffffffff00000([0-9a-fA-F]{3})/.exec(rest))) { out.push({t: 'ic', v: m[1].toUpperCase()}); pos += ICPFX.length + 3; }
    else if ((m = /^\\cff([0-9a-fA-F]{6})/.exec(rest))) { out.push({t: 'co', v: m[1].toUpperCase()}); pos += CPFX.length + 6; }
    else { const c = arr[pos++]; if (c >= ' ') out.push({t: 'ch', v: c}); }
  }
  return out;
}
function colorAt(idx) { let c = null; for (let i = 0; i < idx; i++) if (st.toks[i].t === 'co') c = st.toks[i].v; return c; }
function hx(h) { return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
function mix(a, b, f) { const A = hx(a), B = hx(b); return A.map((v, i) => Math.floor(v + (B[i] - v) * f + 0.5).toString(16).padStart(2, '0')).join('').toUpperCase(); }
function esc(c) { return c === ' ' ? '&nbsp;' : c.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

/* markup builders */
const AC = 16, AW = 24, AH = 26;
function iconHtml(code) {
  const i = DATA.ids.indexOf(code);
  if (i < 0) return '<span class="ic"></span>';
  return `<span class="ic" style="background-image: url(${window.NAME_EDITOR_ATLAS}); background-repeat: no-repeat; background-position: -${(i % AC) * AW}px -${Math.floor(i / AC) * AH}px"></span>`;
}
function tokensHtml(withCursor, withMarks) {
  const out = []; let c = null;
  for (let i = 0; i <= st.toks.length; i++) {
    if (withCursor && i === st.caret) out.push('<span id="ne-cur" class="cur">_</span>');
    const k = st.toks[i];
    if (!k) break;
    if (k.t === 'co') { c = k.v; if (withMarks) out.push(`<span class="cm" style="background-color: #${k.v}"></span>`); }
    else if (k.t === 'ic') out.push(iconHtml(k.v));
    else if (c) out.push(`<span style="color: #${c}">${esc(k.v)}</span>`);
    else out.push(esc(k.v));
  }
  return out.join('');
}
function rawHtml() {
  if (!st.toks.length) return '<span class="e">(empty)</span>';
  return st.toks.map(k => k.t === 'ch' ? esc(k.v) : k.t === 'ic' ? `<span class="g">\\gffffffff00000${k.v}</span>` : `<span class="k">\\cff</span><span class="h">${k.v}</span>`).join('');
}
function colorName(i) { const r = Math.floor((i - 1) / 6) + 1, c = (i - 1) % 6 + 1; return c <= 5 ? DATA.rows[r - 1] + ' \u00b7 ' + DATA.cols[c - 1] : DATA.rgbnames[r - 1]; }
function gridHtml(prefix) { return DATA.pal.map((hex, n) => `<button id="${prefix}-${hex}" class="sw" style="background-color: #${hex}" title="${colorName(n + 1)}  \\cff${hex}"></button>`).join(''); }
function iconsHtml() { return DATA.ids.map(code => `<button id="ic-${code}" class="ib" title="Icon ${code} (UI image ${parseInt(code, 16)})">${iconHtml(code)}</button>`).join(''); }
function barHtml(a, b, n) { let o = ''; for (let i = 0; i < n; i++) o += `<span class="sl" style="background-color: #${mix(a, b, n > 1 ? i / (n - 1) : 0)}"></span>`; return o; }
function presetsHtml() { return DATA.presets.map((p, i) => `<button id="pre-${i + 1}" class="pre" title="${p[0]}">${barHtml(p[1], p[2], 12)}</button>`).join(''); }
function recentHtml() { return st.recent.map(hex => `<button id="rc-${hex}" class="sw" style="background-color: #${hex}" title="Recent  \\cff${hex}"></button>`).join(''); }

/* the document */
const cls = (sel, name, on) => { const e = $(sel); if (e) e.classList.toggle(name, !!on); };
function markSelected() { if (st.selhex) cls('#sw-' + st.selhex, 'sel', false); const c = colorAt(st.caret); st.selhex = c; if (c) cls('#sw-' + c, 'sel', true); }
function paintGradient() {
  $('#ne-gbar').innerHTML = barHtml(st.gA, st.gB, 32);
  for (const s of ['A', 'B']) {
    const hex = s === 'A' ? st.gA : st.gB;
    $('#slot-' + s + '-dot').style.backgroundColor = '#' + hex;
    $('#slot-' + s + '-txt').textContent = (s === 'A' ? 'Start ' : 'End ') + hex;
    cls('#slot-' + s, 'on', st.slot === s);
  }
  cls('#scope-all', 'on', st.scope === 'all'); cls('#scope-cursor', 'on', st.scope === 'cursor');
  const vis = st.toks.filter(k => k.t === 'ch' && k.v !== ' ').length;
  $('#ne-gcost').textContent = `Adds up to ${vis * 9} raw characters (9 per colored letter)`;
}
function refresh() {
  $('#ne-prev').innerHTML = tokensHtml(false, false);
  $('#ne-raw').innerHTML = rawHtml();
  let pill = tokensHtml(true, st.marks);
  if (!st.toks.length) pill += '<span class="ph">Type a name\u2026</span>';
  $('#ne-pill').innerHTML = pill;
  const chars = st.toks.filter(k => k.t === 'ch').length, icons = st.toks.filter(k => k.t === 'ic').length;
  const rawLen = serialize().length;
  $('#ne-info').textContent = `Characters ${chars}  ·  Icons ${icons}  ·  Raw length ${rawLen} of ${MAXRAW}${rawLen > MAXRAW ? ' (too long for the name field)' : ''}`;
  cls('#ne-info', 'over', rawLen > MAXRAW);
  blinkOn = true; markSelected(); paintGradient();
}
function insert(list) { st.toks.splice(st.caret, 0, ...list); st.caret += list.length; refresh(); }
function back() { if (st.caret > 0) { st.toks.splice(st.caret - 1, 1); st.caret--; refresh(); } }
function del() { if (st.caret < st.toks.length) { st.toks.splice(st.caret, 1); refresh(); } }
function setRaw(s) { st.toks = parse(s); st.caret = st.toks.length; refresh(); }
function insertColor(hex) {
  insert([{t: 'co', v: hex}]);
  st.recent = [hex, ...st.recent.filter(x => x !== hex)].slice(0, 10);
  $('#ne-recent').innerHTML = recentHtml();
}
function applyGradient() {
  const from = st.scope === 'cursor' ? st.caret : 0;
  const head = st.toks.slice(0, from), tail = st.toks.slice(from).filter(k => k.t !== 'co');
  const vis = tail.filter(k => k.t === 'ch' && k.v !== ' ').length;
  let n = 0, last = colorAt(from);
  for (const k of tail) {
    if (k.t === 'ch' && k.v !== ' ') { const c = mix(st.gA, st.gB, vis > 1 ? n / (vis - 1) : 0); n++; if (c !== last) { head.push({t: 'co', v: c}); last = c; } }
    head.push(k);
  }
  st.toks = head; st.caret = st.toks.length; refresh();
}
function removeColors() { st.toks = st.toks.filter(k => k.t !== 'co'); st.caret = Math.min(st.caret, st.toks.length); refresh(); }
function setTab(i) {
  st.tab = (i % TABS.length + TABS.length) % TABS.length;
  TABS.forEach((t, n) => { cls('#ne-p-' + t, 'ne-hide', n !== st.tab); cls('#tab-' + t, 'on', n === st.tab); });
  paintGradient();
}
async function copyRaw(b) {
  try { await navigator.clipboard.writeText(serialize()); }
  catch (e) { const r = document.createRange(); r.selectNodeContents($('#ne-raw')); getSelection().removeAllRanges(); getSelection().addRange(r); document.execCommand('copy'); }
  if (b) { const t = b.textContent; b.textContent = 'Copied'; setTimeout(() => b.textContent = t, 900); }
}
const EXAMPLE = ICPFX + '0DA ' + CPFX + 'FEC2C5Ra' + CPFX + 'F2D7D7v' + CPFX + 'BF0B57en ' + CPFX + 'A2B90AHe' + CPFX + 'F49AC1ro ' + ICPFX + '496';

/* what a press of a button (by id) does; the same table of ids as main.lua */
function press(id, btn) {
  const m = /^([a-z]+)-(.+)$/.exec(id), kind = m && m[1], arg = m && m[2];
  if (kind === 'sw' || kind === 'rc') insertColor(arg);
  else if (kind === 'gs') { if (st.slot === 'A') { st.gA = arg; st.slot = 'B'; } else st.gB = arg; paintGradient(); }
  else if (kind === 'ic') insert([{t: 'ic', v: arg}]);
  else if (kind === 'tab') setTab(TABS.indexOf(arg));
  else if (kind === 'slot') { st.slot = arg; paintGradient(); }
  else if (kind === 'scope') { st.scope = arg; paintGradient(); }
  else if (kind === 'pre') { const p = DATA.presets[+arg - 1]; if (p) { st.gA = p[1]; st.gB = p[2]; paintGradient(); } }
  else if (id === 'act-left') { st.caret = Math.max(0, st.caret - 1); refresh(); }
  else if (id === 'act-right') { st.caret = Math.min(st.toks.length, st.caret + 1); refresh(); }
  else if (id === 'act-back') back();
  else if (id === 'act-clear') { st.toks = []; st.caret = 0; refresh(); }
  else if (id === 'act-example') setRaw(EXAMPLE);
  else if (id === 'act-copy') copyRaw(btn);
  else if (id === 'act-paste') { navigator.clipboard.readText().then(setRaw).catch(() => { if (btn) btn.textContent = 'Use Ctrl+V in the name'; }); }
  else if (id === 'act-swap') { [st.gA, st.gB] = [st.gB, st.gA]; paintGradient(); }
  else if (id === 'act-apply') applyGradient();
  else if (id === 'act-nocol') removeColors();
}

/* wiring */
const pill = $('#ne-pill');
$('#ne').addEventListener('click', (e) => {
  const b = e.target.closest('button, a');
  if (b && b.id) { press(b.id, b); pill.focus({preventScroll: true}); }
});
pill.addEventListener('focus', () => pill.classList.add('on'));
pill.addEventListener('blur', () => pill.classList.remove('on'));
pill.addEventListener('keydown', (e) => {
  if (e.ctrlKey || e.metaKey) return;
  const k = e.key;
  if (Array.from(k).length === 1) { insert([{t: 'ch', v: k}]); e.preventDefault(); }
  else if (k === 'Backspace') { back(); e.preventDefault(); }
  else if (k === 'Delete') { del(); e.preventDefault(); }
  else if (k === 'ArrowLeft') { st.caret = Math.max(0, st.caret - 1); refresh(); e.preventDefault(); }
  else if (k === 'ArrowRight') { st.caret = Math.min(st.toks.length, st.caret + 1); refresh(); e.preventDefault(); }
  else if (k === 'Home') { st.caret = 0; refresh(); e.preventDefault(); }
  else if (k === 'End') { st.caret = st.toks.length; refresh(); e.preventDefault(); }
  else if (k === 'PageDown') { setTab(st.tab + 1); e.preventDefault(); }
  else if (k === 'PageUp') { setTab(st.tab - 1); e.preventDefault(); }
});
pill.addEventListener('paste', (e) => { e.preventDefault(); insert(parse(e.clipboardData.getData('text'))); });
document.addEventListener('copy', (e) => { if (document.activeElement === pill) { e.clipboardData.setData('text/plain', serialize()); e.preventDefault(); } });
setInterval(() => { const on = (performance.now() * 1.7 / 1000) % 1 < 0.6; if (on !== blinkOn) { blinkOn = on; cls('#ne-cur', 'off', !on); } }, 50);

/* a gamepad: LB / RB switch the tabs, B is backspace, X copies, Y clears; the d-pad is the browser's own focus movement */
const held = {};
(function poll() {
  const gp = (navigator.getGamepads ? navigator.getGamepads() : [])[0];
  document.body.classList.toggle('pad', !!gp);
  if (gp) {
    const edge = (n, v, fn) => { if (v && !held[n]) fn(); held[n] = v; };
    const b = (i) => gp.buttons[i] && gp.buttons[i].pressed;
    edge('lb', b(4), () => setTab(st.tab - 1)); edge('rb', b(5), () => setTab(st.tab + 1));
    edge('b', b(1), back); edge('x', b(2), () => copyRaw($('#act-copy'))); edge('y', b(3), () => press('act-clear'));
  }
  requestAnimationFrame(poll);
})();

$('#ne-colors').innerHTML = gridHtml('sw'); $('#ne-gcolors').innerHTML = gridHtml('gs');
$('#ne-icons').innerHTML = iconsHtml(); $('#ne-presets').innerHTML = presetsHtml(); $('#ne-recent').innerHTML = recentHtml();
setTab(0);
const initial = new URLSearchParams(location.search).get('raw');
st.toks = parse(initial !== null ? initial : EXAMPLE); st.caret = st.toks.length;
refresh(); pill.focus({preventScroll: true});
window.nameEditor = {state: st, press, setRaw, serialize, parse};
})();
