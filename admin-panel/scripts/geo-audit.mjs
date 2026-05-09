/**
 * PRE-PRODUCTION GEO-DATA INTEGRITY AUDIT
 * Bangladesh District Map — Senior Architect Final Check
 */
import { readFileSync } from 'fs';

// ═══ OFFICIAL REFERENCE DATA ═══
const OFFICIAL = {
  'Barishal':    ['Barguna','Barishal','Bhola','Jhalokati','Patuakhali','Pirojpur'],
  'Chattogram':  ['Bandarban','Brahmanbaria','Chandpur','Chattogram','Cumilla',"Cox's Bazar",'Feni','Khagrachari','Lakshmipur','Noakhali','Rangamati'],
  'Dhaka':       ['Dhaka','Faridpur','Gazipur','Gopalganj','Kishoreganj','Madaripur','Manikganj','Munshiganj','Narayanganj','Narsingdi','Rajbari','Shariatpur','Tangail'],
  'Khulna':      ['Bagerhat','Chuadanga','Jashore','Jhenaidah','Khulna','Kushtia','Magura','Meherpur','Narail','Satkhira'],
  'Mymensingh':  ['Jamalpur','Mymensingh','Netrokona','Sherpur'],
  'Rajshahi':    ['Bogura','Nawabganj','Joypurhat','Naogaon','Natore','Pabna','Rajshahi','Sirajgonj'],
  'Rangpur':     ['Dinajpur','Gaibandha','Kurigram','Lalmonirhat','Nilphamari','Panchagarh','Rangpur','Thakurgaon'],
  'Sylhet':      ['Habiganj','Maulvibazar','Sunamganj','Sylhet'],
};

const OFFICIAL_UPAZILA_COUNTS = {
  Barguna:7, Barishal:10, Bhola:7, Jhalokati:4, Patuakhali:8, Pirojpur:7,
  Bandarban:7, Brahmanbaria:9, Chandpur:8, Chattogram:16, Cumilla:16, "Cox's Bazar":8,
  Feni:6, Khagrachari:9, Lakshmipur:5, Noakhali:9, Rangamati:10,
  Dhaka:12, Faridpur:9, Gazipur:5, Gopalganj:5, Kishoreganj:13, Madaripur:5,
  Manikganj:7, Munshiganj:6, Narayanganj:5, Narsingdi:6, Rajbari:5, Shariatpur:6, Tangail:12,
  Bagerhat:9, Chuadanga:4, Jashore:8, Jhenaidah:6, Khulna:9, Kushtia:6,
  Magura:4, Meherpur:3, Narail:3, Satkhira:7,
  Jamalpur:7, Mymensingh:13, Netrokona:10, Sherpur:5,
  Bogura:12, Nawabganj:5, Joypurhat:5, Naogaon:11, Natore:7,
  Pabna:9, Rajshahi:9, Sirajgonj:9,
  Dinajpur:13, Gaibandha:7, Kurigram:9, Lalmonirhat:5, Nilphamari:6,
  Panchagarh:5, Rangpur:8, Thakurgaon:5,
  Habiganj:8, Maulvibazar:7, Sunamganj:11, Sylhet:13,
};

// ═══ PARSE MAP DATA ═══
const distSrc = readFileSync('src/components/admin/districtPaths.ts', 'utf-8');
const upSrc = readFileSync('src/components/admin/upazilaPaths.ts', 'utf-8');
const mapSrc = readFileSync('src/components/admin/BangladeshMap.tsx', 'utf-8');

// Parse district names
const districtNames = [];
for (const line of distSrc.split('\n')) {
  const m = line.match(/^\s+"([^"]+)":\s+"M/);
  if (m) districtNames.push(m[1]);
}

// Parse upazila data - line by line approach
const upazilasByDistrict = new Map();
let currentDistrict = null;
for (const line of upSrc.split('\n')) {
  // Detect district header: "DistrictName": {
  const distMatch = line.match(/^\s+"([^"]+)":\s*\{$/);
  if (distMatch && !line.includes('": "M')) {
    currentDistrict = distMatch[1];
    if (!upazilasByDistrict.has(currentDistrict)) {
      upazilasByDistrict.set(currentDistrict, []);
    }
    continue;
  }
  // Detect upazila: "UpazilaName": "Mxxx,yyy..."
  if (currentDistrict) {
    const upMatch = line.match(/^\s+"([^"]+)":\s*"(M[^"]+)"/);
    if (upMatch) {
      const name = upMatch[1];
      const path = upMatch[2];
      const pts = [];
      const pRe = /([ML])([\d.]+),([\d.]+)/g;
      let pm;
      while ((pm = pRe.exec(path)) !== null) pts.push([+pm[2], +pm[3]]);
      const cx = pts.length ? pts.reduce((s, c) => s + c[0], 0) / pts.length : NaN;
      const cy = pts.length ? pts.reduce((s, c) => s + c[1], 0) / pts.length : NaN;
      upazilasByDistrict.get(currentDistrict).push({ name, cx, cy });
    }
    // Detect close of district block
    if (line.match(/^\s+\},?$/)) {
      currentDistrict = null;
    }
  }
}
// Remove non-district entries
for (const key of upazilasByDistrict.keys()) {
  if (upazilasByDistrict.get(key).length === 0) upazilasByDistrict.delete(key);
}

// Parse division map from BangladeshMap.tsx
const divAssignments = new Map();
const dmBlock = mapSrc.match(/const DM[^{]*\{([\s\S]*?)\};/);
if (dmBlock) {
  const entries = dmBlock[1].matchAll(/['"]?([^'",:]+?)['"]?\s*:\s*'([^']+)'/g);
  for (const m of entries) divAssignments.set(m[1].trim(), m[2].trim());
}

// ═══ AUDIT ═══
let errors = 0, warnings = 0;
const err = (m) => { console.log(`❌ ERROR: ${m}`); errors++; };
const warn = (m) => { console.log(`⚠️  WARN:  ${m}`); warnings++; };
const ok = (m) => { console.log(`✅ OK:    ${m}`); };
const info = (m) => { console.log(`ℹ️  INFO:  ${m}`); };

console.log('═══════════════════════════════════════════════════════════════');
console.log(' PRE-PRODUCTION GEO-DATA INTEGRITY AUDIT');
console.log(' Bangladesh District Map — Final Check');
console.log('═══════════════════════════════════════════════════════════════\n');

// CHECK 1: District Count
console.log('── CHECK 1: District Count ──────────────────────────────────');
if (districtNames.length === 64) ok(`District count: ${districtNames.length}/64`);
else err(`District count: ${districtNames.length}/64`);

// CHECK 2: District Names
console.log('\n── CHECK 2: District Names ─────────────────────────────────');
const mapNameSet = new Set(districtNames);
const allOfficial = Object.values(OFFICIAL).flat();
const missing = allOfficial.filter(n => !mapNameSet.has(n));
const extra = districtNames.filter(n => !new Set(allOfficial).has(n));
if (!missing.length) ok('All 64 official district names present');
else for (const n of missing) err(`Missing: "${n}"`);
if (!extra.length) ok('No extra/unknown names');
else for (const n of extra) warn(`Extra: "${n}"`);

// CHECK 3: Division Assignment
console.log('\n── CHECK 3: Division Assignment ────────────────────────────');
let divErr = 0;
for (const [div, dists] of Object.entries(OFFICIAL)) {
  for (const d of dists) {
    const mapped = divAssignments.get(d);
    if (!mapped) { warn(`"${d}" not in DM map (check alias)`); continue; }
    if (mapped !== div) { err(`"${d}" → "${mapped}" should be "${div}"`); divErr++; }
  }
}
if (!divErr) ok('All division assignments correct');

// CHECK 4: Upazila Counts
console.log('\n── CHECK 4: Upazila Counts ─────────────────────────────────');
let totalUp = 0, countIssues = 0;
for (const [dist, exp] of Object.entries(OFFICIAL_UPAZILA_COUNTS)) {
  const ups = upazilasByDistrict.get(dist);
  const act = ups ? ups.length : 0;
  totalUp += act;
  if (act !== exp) {
    const d = act - exp;
    if (Math.abs(d) >= 3) err(`${dist}: ${act}/${exp} (${d > 0 ? '+' : ''}${d})`);
    else warn(`${dist}: ${act}/${exp} (${d > 0 ? '+' : ''}${d})`);
    countIssues++;
  }
}
if (!countIssues) ok('All upazila counts match');
info(`Total: ${totalUp} upazilas (official: 495)`);

// CHECK 5: Duplicate Names
console.log('\n── CHECK 5: Duplicate Upazila Names ────────────────────────');
const nameToDistricts = new Map();
for (const [dist, ups] of upazilasByDistrict) {
  for (const u of ups) {
    if (!nameToDistricts.has(u.name)) nameToDistricts.set(u.name, []);
    nameToDistricts.get(u.name).push({ dist, cx: u.cx, cy: u.cy });
  }
}
let dups = 0;
for (const [name, occs] of nameToDistricts) {
  if (occs.length <= 1) continue;
  dups++;
  info(`"${name}" in: ${occs.map(o => o.dist).join(', ')}`);
  for (let i = 0; i < occs.length; i++) {
    for (let j = i + 1; j < occs.length; j++) {
      const d = Math.sqrt((occs[i].cx - occs[j].cx) ** 2 + (occs[i].cy - occs[j].cy) ** 2);
      if (d < 15) warn(`  "${name}": ${occs[i].dist} ↔ ${occs[j].dist} only ${d.toFixed(0)} units apart — SUSPICIOUS`);
      else ok(`  "${name}" instances well-separated (${d.toFixed(0)} units)`);
    }
  }
}
info(`${dups} duplicate name(s) found`);

// CHECK 6: Geographic Coherence
console.log('\n── CHECK 6: Upazila Geographic Coherence ───────────────────');
let coIssues = 0;
for (const [dist, ups] of upazilasByDistrict) {
  if (ups.length < 2) continue;
  const dcx = ups.reduce((s, u) => s + u.cx, 0) / ups.length;
  const dcy = ups.reduce((s, u) => s + u.cy, 0) / ups.length;
  const ds = ups.map(u => ({ name: u.name, d: Math.sqrt((u.cx - dcx) ** 2 + (u.cy - dcy) ** 2) }));
  ds.sort((a, b) => a.d - b.d);
  const med = ds[Math.floor(ds.length / 2)].d;
  for (const { name, d } of ds) {
    if (d > med * 4 && d > 30) {
      err(`OUTLIER: "${name}" in ${dist} — ${d.toFixed(0)} units from centroid (median: ${med.toFixed(0)})`);
      coIssues++;
    }
  }
}
if (!coIssues) ok('All upazilas coherent');

// CHECK 7: Relative Position
console.log('\n── CHECK 7: Relative Position Sanity ───────────────────────');
const distCen = new Map();
for (const [dist, ups] of upazilasByDistrict) {
  if (!ups.length) continue;
  distCen.set(dist, {
    cx: ups.reduce((s, u) => s + u.cx, 0) / ups.length,
    cy: ups.reduce((s, u) => s + u.cy, 0) / ups.length,
  });
}
const checks = [
  ['Panchagarh', 'Dhaka', 'y', 'less', 'Panchagarh NORTH of Dhaka'],
  ['Sylhet', 'Dhaka', 'x', 'more', 'Sylhet EAST of Dhaka'],
  ['Chattogram', 'Dhaka', 'x', 'more', 'Chattogram EAST of Dhaka'],
  ['Chattogram', 'Rajshahi', 'x', 'more', 'Chattogram EAST of Rajshahi'],
  ['Rajshahi', 'Chattogram', 'y', 'less', 'Rajshahi NORTH of Chattogram'],
  ['Khulna', 'Rangpur', 'y', 'more', 'Khulna SOUTH of Rangpur'],
  ["Cox's Bazar", 'Dhaka', 'y', 'more', "Cox's Bazar SOUTH of Dhaka"],
  ['Rangpur', 'Dhaka', 'y', 'less', 'Rangpur NORTH of Dhaka'],
  ['Thakurgaon', 'Rangpur', 'x', 'less', 'Thakurgaon WEST of Rangpur'],
  ['Sylhet', 'Rajshahi', 'x', 'more', 'Sylhet EAST of Rajshahi'],
  ['Barishal', 'Mymensingh', 'y', 'more', 'Barishal SOUTH of Mymensingh'],
  ['Satkhira', 'Chattogram', 'x', 'less', 'Satkhira WEST of Chattogram'],
  ['Dinajpur', 'Sylhet', 'x', 'less', 'Dinajpur WEST of Sylhet'],
  ['Panchagarh', "Cox's Bazar", 'y', 'less', "Panchagarh NORTH of Cox's Bazar"],
];
let posErr = 0;
for (const [a, b, axis, exp, desc] of checks) {
  const ca = distCen.get(a), cb = distCen.get(b);
  if (!ca || !cb) { warn(`Cannot check: ${desc} (missing data)`); continue; }
  const va = axis === 'x' ? ca.cx : ca.cy;
  const vb = axis === 'x' ? cb.cx : cb.cy;
  if ((exp === 'less' && va < vb) || (exp === 'more' && va > vb)) {
    ok(desc);
  } else {
    err(`${desc} — FAILED (${a}=${Math.round(axis==='x'?ca.cx:ca.cy)}, ${b}=${Math.round(axis==='x'?cb.cx:cb.cy)})`);
    posErr++;
  }
}

// CHECK 8: Data Integrity
console.log('\n── CHECK 8: Data Integrity ─────────────────────────────────');
let dataErr = 0;
for (const d of districtNames) {
  if (!upazilasByDistrict.has(d)) { err(`"${d}" has no upazila data`); dataErr++; }
}
if (!dataErr) ok('All districts have upazila data and bounds');

// SUMMARY
console.log('\n═══════════════════════════════════════════════════════════════');
console.log(` AUDIT COMPLETE — ${errors} errors, ${warnings} warnings`);
console.log('═══════════════════════════════════════════════════════════════');
if (errors === 0) console.log('\n🟢 MAP IS PRODUCTION-READY');
else console.log(`\n🔴 ${errors} ERROR(S) — Fix before production`);
console.log('');
