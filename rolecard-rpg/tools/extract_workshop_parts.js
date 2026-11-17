// Extract the card's sigil-workshop pattern catalogue (PATTERN_DEFS) into Godot-readable JSON.
// Source: F:/sigil-circuit/sigil-workbench.html (live card front end, read-only).
// Output: data/workshop/patterns.json - per pattern: kind, nature, cost, shorthand, name, desc,
// slots (ports with x/y/a), and the glyph as primitives parsed from its SVG (circle/ellipse/path).
// Usage: node tools/extract_workshop_parts.js
const fs = require('fs');
const path = require('path');
const SRC = 'F:/sigil-circuit/sigil-workbench.html';
const OUT = path.join(__dirname, '..', 'data', 'workshop', 'patterns.json');
const t = fs.readFileSync(SRC, 'utf8');
const a = t.indexOf('function ringSlots');
const b = t.indexOf('var PART_KIND');
if (a < 0 || b < 0) throw new Error('catalogue markers not found');
const code = t.slice(a, b) + '\n;globalThis.__P = PATTERN_DEFS;';
new Function(code)();
const P = globalThis.__P;

function attrs(s) {
  const o = {};
  for (const m of s.matchAll(/([\w-]+)="([^"]*)"/g)) o[m[1]] = m[2];
  return o;
}
// Path data -> list of polylines (absolute coords). Supports M L H V C Q Z (upper case, as used).
function pathToPolys(d) {
  const toks = d.match(/[MLHVCQZmlhvcqz]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
  const polys = []; let cur = null; let x = 0, y = 0, sx = 0, sy = 0, i = 0, cmd = '';
  const num = () => parseFloat(toks[i++]);
  while (i < toks.length) {
    if (/[A-Za-z]/.test(toks[i])) cmd = toks[i++];
    const C = cmd.toUpperCase();
    if (C === 'Z') { if (cur) { cur.push([sx, sy]); cur.closed = true; } cur = null; continue; }
    if (C === 'M') { x = num(); y = num(); sx = x; sy = y; cur = [[x, y]]; polys.push(cur); cmd = 'L'; continue; }
    if (!cur) { cur = [[x, y]]; polys.push(cur); }
    if (C === 'L') { x = num(); y = num(); cur.push([x, y]); }
    else if (C === 'H') { x = num(); cur.push([x, y]); }
    else if (C === 'V') { y = num(); cur.push([x, y]); }
    else if (C === 'C') {
      const x1 = num(), y1 = num(), x2 = num(), y2 = num(), x3 = num(), y3 = num();
      for (let k = 1; k <= 12; k++) { const s = k / 12, u = 1 - s;
        cur.push([u*u*u*x + 3*u*u*s*x1 + 3*u*s*s*x2 + s*s*s*x3, u*u*u*y + 3*u*u*s*y1 + 3*u*s*s*y2 + s*s*s*y3]); }
      x = x3; y = y3;
    } else if (C === 'Q') {
      const x1 = num(), y1 = num(), x2 = num(), y2 = num();
      for (let k = 1; k <= 10; k++) { const s = k / 10, u = 1 - s;
        cur.push([u*u*x + 2*u*s*x1 + s*s*x2, u*u*y + 2*u*s*y1 + s*s*y2]); }
      x = x2; y = y2;
    } else { i++; }
  }
  return polys.map(p => ({ pts: p.map(q => [+q[0].toFixed(2), +q[1].toFixed(2)]), closed: !!p.closed }));
}
function glyph(svg) {
  const out = [];
  for (const m of svg.matchAll(/<(circle|ellipse|path)\b([^>]*)\/?>/g)) {
    const at = attrs(m[2]);
    const cls = (at['class'] || '').split(/\s+/).filter(Boolean);
    const card = /var\(--card\)/.test(at.style || '');
    const toneFill = /fill:\s*#/.test(at.style || '');
    const base = { cls, card, tone: toneFill };
    if (m[1] === 'circle') out.push({ ...base, t: 'circle', cx: +(at.cx || 0), cy: +(at.cy || 0), r: +(at.r || 0) });
    else if (m[1] === 'ellipse') {
      const rot = /rotate\(([-\d.]+)\)/.exec(at.transform || '');
      out.push({ ...base, t: 'ellipse', cx: +(at.cx || 0), cy: +(at.cy || 0), rx: +at.rx, ry: +at.ry, rot: rot ? +rot[1] : 0 });
    } else out.push({ ...base, t: 'path', polys: pathToPolys(at.d || '') });
  }
  return out;
}
const out = { _note: 'Extracted from sigil-workbench.html PATTERN_DEFS by tools/extract_workshop_parts.js. Do not hand-edit; re-run the extractor.', source: SRC, scale: 1.45, link_gap: 38, link_gap_core: 52, order: [], patterns: {} };
for (const id of Object.keys(P)) {
  const d = P[id];
  out.order.push(id);
  out.patterns[id] = { kind: d.kind, nature: d.nature, cost: d.cost, shorthand: d.shorthand, name: d.name, desc: d.desc,
    anchor: d.anchor || 0, reach: d.reach || 0, slots: d.slots || [], glyph: glyph(d.draw ? d.draw() : '') };
}
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 1));
console.log(out.order.length, 'patterns ->', OUT);
for (const id of out.order) console.log(id, P[id].kind, P[id].nature, P[id].cost, (P[id].slots || []).length, out.patterns[id].glyph.length);
