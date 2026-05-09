/**
 * Converts bangladesh.geojson (upazila-level) into:
 *   1. District-level SVG paths (merged upazilas per district)
 *   2. Upazila-level SVG paths grouped by district (for drill-down)
 *   3. Per-district bounding boxes (for zoom animation)
 *
 * Output files:
 *   - src/components/admin/districtPaths.ts   (existing)
 *   - src/components/admin/upazilaPaths.ts    (new)
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const INPUT = join(__dirname, '..', 'bangladesh.geojson');
const OUTPUT_DISTRICTS = join(__dirname, '..', 'src', 'components', 'admin', 'districtPaths.ts');
const OUTPUT_UPAZILAS = join(__dirname, '..', 'src', 'components', 'admin', 'upazilaPaths.ts');

// ── Read & parse ───────────────────────────────────────────────────────────
const raw = readFileSync(INPUT, 'utf-8');
const geo = JSON.parse(raw);
console.log(`Loaded ${geo.features.length} features.`);

// ── Group polygons by district AND by upazila ──────────────────────────────
const districtPolygons = new Map(); // district_name => [[ring1], [ring2], ...]
const upazilaData = new Map();      // district_name => Map(upazila_name => [[ring1], ...])

// ── PASS 1: Collect labeled features + track centroids ───────────────────────
const orphans = [];
const featuresByDistrictId = new Map(); // district_id => [{name, rings, centroid}]

for (const f of geo.features) {
  const dName = (f.properties.district_name || '').trim();
  const uName = (f.properties.name || f.properties.NAME_3 || f.properties.upazila_name || 'Unknown').trim();
  const uId = f.properties.upazila_id || '';

  const geom = f.geometry;
  const rings = [];
  if (geom.type === 'Polygon') {
    rings.push(geom.coordinates[0]);
  } else if (geom.type === 'MultiPolygon') {
    for (const poly of geom.coordinates) rings.push(poly[0]);
  }
  if (rings.length === 0) continue;

  // Compute centroid for validation
  const allPts = rings.flat();
  const cx = allPts.reduce((s, c) => s + c[0], 0) / allPts.length;
  const cy = allPts.reduce((s, c) => s + c[1], 0) / allPts.length;

  if (!dName) {
    orphans.push({ name: uName, id: uId, rings, cx, cy });
    continue;
  }

  // Build district polygons
  if (!districtPolygons.has(dName)) districtPolygons.set(dName, []);
  for (const r of rings) districtPolygons.get(dName).push(r);

  // Build upazila data (use upazila_id to disambiguate same-name upazilas)
  if (!upazilaData.has(dName)) upazilaData.set(dName, new Map());
  const districtUpazilas = upazilaData.get(dName);
  if (!districtUpazilas.has(uName)) districtUpazilas.set(uName, { rings: [], cx, cy });
  const entry = districtUpazilas.get(uName);
  for (const r of rings) entry.rings.push(r);
}

// ── PASS 2: Compute district bounding boxes ──────────────────────────────────
const districtBBox = new Map(); // district => { minLon, maxLon, minLat, maxLat }
for (const [dName, polys] of districtPolygons) {
  let minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
  for (const ring of polys) {
    for (const [lon, lat] of ring) {
      if (lon < minLon) minLon = lon; if (lon > maxLon) maxLon = lon;
      if (lat < minLat) minLat = lat; if (lat > maxLat) maxLat = lat;
    }
  }
  districtBBox.set(dName, { minLon, maxLon, minLat, maxLat });
}

// ── PASS 3: Validate labeled upazilas using centroid-distance outlier detection ──
for (const [dName, upMap] of upazilaData) {
  if (upMap.size < 2) continue;
  let sumX = 0, sumY = 0, cnt = 0;
  for (const [, entry] of upMap) { sumX += entry.cx; sumY += entry.cy; cnt++; }
  const dcx = sumX / cnt, dcy = sumY / cnt;
  const dists = [];
  for (const [uName, entry] of upMap) {
    dists.push({ uName, d: Math.sqrt((entry.cx - dcx) ** 2 + (entry.cy - dcy) ** 2) });
  }
  dists.sort((a, b) => a.d - b.d);
  const median = dists[Math.floor(dists.length / 2)].d;
  const threshold = Math.max(0.8, median * 2.5 + 0.3);
  for (const { uName, d } of dists) {
    if (d > threshold) {
      const entry = upMap.get(uName);
      console.log(`⚠️  MISLABELED: "${uName}" in ${dName} is ${d.toFixed(2)}° from centroid (threshold: ${threshold.toFixed(2)}°). Removing.`);
      // Remove rings from districtPolygons too (prevent bbox pollution)
      const dPolys = districtPolygons.get(dName);
      if (dPolys) {
        for (const badRing of entry.rings) {
          const idx = dPolys.indexOf(badRing);
          if (idx !== -1) dPolys.splice(idx, 1);
        }
      }
      upMap.delete(uName);
      orphans.push({ name: uName, id: '', rings: entry.rings, cx: entry.cx, cy: entry.cy });
    }
  }
}

// ── PASS 3.5: Detect and fix swapped duplicate-name upazilas ─────────────────
// When two districts have upazilas with the same name, check if they are swapped
// (i.e., each upazila is geographically closer to the OTHER district's centroid).
{
  // Build a map: upazila_name => [{districtName, entry}]
  const nameOccurrences = new Map();
  for (const [dName, upMap] of upazilaData) {
    for (const [uName, entry] of upMap) {
      if (!nameOccurrences.has(uName)) nameOccurrences.set(uName, []);
      nameOccurrences.get(uName).push({ dName, entry });
    }
  }
  // Compute preliminary district centroids (excluding the duplicate in question for accuracy)
  const computeCentroidExcluding = (dName, excludeUpazila) => {
    const upMap = upazilaData.get(dName);
    if (!upMap) return null;
    let sx = 0, sy = 0, n = 0;
    for (const [uN, entry] of upMap) {
      if (uN === excludeUpazila) continue;
      sx += entry.cx; sy += entry.cy; n++;
    }
    return n > 0 ? { cx: sx / n, cy: sy / n } : null;
  };

  for (const [uName, occurrences] of nameOccurrences) {
    if (occurrences.length !== 2) continue; // Only handle pairs
    const [a, b] = occurrences;
    const centA = computeCentroidExcluding(a.dName, uName);
    const centB = computeCentroidExcluding(b.dName, uName);
    if (!centA || !centB) continue;

    // Current assignment distances
    const distA_toA = Math.sqrt((a.entry.cx - centA.cx)**2 + (a.entry.cy - centA.cy)**2);
    const distB_toB = Math.sqrt((b.entry.cx - centB.cx)**2 + (b.entry.cy - centB.cy)**2);
    const currentTotal = distA_toA + distB_toB;

    // Swapped distances
    const distA_toB = Math.sqrt((a.entry.cx - centB.cx)**2 + (a.entry.cy - centB.cy)**2);
    const distB_toA = Math.sqrt((b.entry.cx - centA.cx)**2 + (b.entry.cy - centA.cy)**2);
    const swappedTotal = distA_toB + distB_toA;

    if (swappedTotal < currentTotal * 0.7) { // Swap only if significantly better (30%+ improvement)
      console.log(`🔄 SWAP DETECTED: "${uName}" between ${a.dName} and ${b.dName}`);
      console.log(`   Current: ${a.dName}→${distA_toA.toFixed(3)}° + ${b.dName}→${distB_toB.toFixed(3)}° = ${currentTotal.toFixed(3)}°`);
      console.log(`   Swapped: ${a.dName}→${distB_toB.toFixed(3)}° + ${b.dName}→${distA_toA.toFixed(3)}° = ${swappedTotal.toFixed(3)}°`);

      // Remove from current districts
      const upMapA = upazilaData.get(a.dName);
      const upMapB = upazilaData.get(b.dName);
      const entryA = upMapA.get(uName);
      const entryB = upMapB.get(uName);
      // Remove rings from districtPolygons
      const dPolysA = districtPolygons.get(a.dName);
      const dPolysB = districtPolygons.get(b.dName);
      if (dPolysA) for (const r of entryA.rings) { const idx = dPolysA.indexOf(r); if (idx !== -1) dPolysA.splice(idx, 1); }
      if (dPolysB) for (const r of entryB.rings) { const idx = dPolysB.indexOf(r); if (idx !== -1) dPolysB.splice(idx, 1); }

      // Swap: A's data goes to B's district, B's data goes to A's district
      upMapA.set(uName, { rings: entryB.rings, cx: entryB.cx, cy: entryB.cy });
      upMapB.set(uName, { rings: entryA.rings, cx: entryA.cx, cy: entryA.cy });
      // Re-add rings to correct districts
      if (dPolysA) for (const r of entryB.rings) dPolysA.push(r);
      if (dPolysB) for (const r of entryA.rings) dPolysB.push(r);

      console.log(`   ✅ Swapped successfully.`);
    }
  }
}

// ── PASS 4: Recompute bboxes after cleanup ───────────────────────────────────
districtBBox.clear();
for (const [dName, polys] of districtPolygons) {
  let minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
  for (const ring of polys) {
    for (const [lon, lat] of ring) {
      if (lon < minLon) minLon = lon; if (lon > maxLon) maxLon = lon;
      if (lat < minLat) minLat = lat; if (lat > maxLat) maxLat = lat;
    }
  }
  districtBBox.set(dName, { minLon, maxLon, minLat, maxLat });
}

// ── PASS 5: Recover orphans using pure centroid distance ─────────────────────
// Compute district centroids from CLEAN data
const districtCentroids = new Map();
for (const [dName, upMap] of upazilaData) {
  let sx = 0, sy = 0, n = 0;
  for (const [, entry] of upMap) { sx += entry.cx; sy += entry.cy; n++; }
  if (n > 0) districtCentroids.set(dName, { cx: sx / n, cy: sy / n });
}

let recoveredCount = 0;
for (const orphan of orphans) {
  let bestDist = Infinity;
  let bestDistName = '';
  // Find nearest district by centroid distance
  for (const [dName, dc] of districtCentroids) {
    const dist = Math.sqrt((orphan.cx - dc.cx) ** 2 + (orphan.cy - dc.cy) ** 2);
    if (dist < bestDist) { bestDist = dist; bestDistName = dName; }
  }
  if (bestDistName && bestDist < 2.0) {
    for (const r of orphan.rings) districtPolygons.get(bestDistName).push(r);
    if (!upazilaData.has(bestDistName)) upazilaData.set(bestDistName, new Map());
    const upMap = upazilaData.get(bestDistName);
    if (!upMap.has(orphan.name)) {
      upMap.set(orphan.name, { rings: [], cx: orphan.cx, cy: orphan.cy });
    }
    const entry = upMap.get(orphan.name);
    for (const r of orphan.rings) entry.rings.push(r);
    recoveredCount++;
  } else {
    console.log(`❌ UNRECOVERABLE: "${orphan.name}" at (${orphan.cx.toFixed(2)},${orphan.cy.toFixed(2)}) - nearest district ${bestDistName} is ${bestDist.toFixed(2)}° away`);
  }
}
console.log(`Recovered ${recoveredCount}/${orphans.length} orphaned features.`);

console.log(`Found ${districtPolygons.size} districts.`);
let totalUpazilas = 0;
for (const m of upazilaData.values()) totalUpazilas += m.size;
console.log(`Found ${totalUpazilas} upazilas across all districts.`);

// ── Compute global bounding box ───────────────────────────────────────────
let minLon = Infinity, maxLon = -Infinity;
let minLat = Infinity, maxLat = -Infinity;

for (const rings of districtPolygons.values()) {
  for (const ring of rings) {
    for (const [lon, lat] of ring) {
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
    }
  }
}

console.log(`Bounds: lon [${minLon.toFixed(3)}, ${maxLon.toFixed(3)}], lat [${minLat.toFixed(3)}, ${maxLat.toFixed(3)}]`);

// ── Mercator projection ───────────────────────────────────────────────────
const SVG_W = 400;
const SVG_H = 560;
const PADDING = 15;

function mercatorY(lat) {
  const latRad = (lat * Math.PI) / 180;
  return Math.log(Math.tan(Math.PI / 4 + latRad / 2));
}

const minY = mercatorY(minLat);
const maxY = mercatorY(maxLat);

function projectLon(lon) {
  return PADDING + ((lon - minLon) / (maxLon - minLon)) * (SVG_W - 2 * PADDING);
}

function projectLat(lat) {
  const y = mercatorY(lat);
  return PADDING + ((maxY - y) / (maxY - minY)) * (SVG_H - 2 * PADDING);
}

// ── Douglas-Peucker simplification ────────────────────────────────────────
function distanceToSegment(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  if (dx === 0 && dy === 0) {
    return Math.sqrt((p[0] - a[0]) ** 2 + (p[1] - a[1]) ** 2);
  }
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)));
  const px = a[0] + t * dx, py = a[1] + t * dy;
  return Math.sqrt((p[0] - px) ** 2 + (p[1] - py) ** 2);
}

function douglasPeucker(points, epsilon) {
  if (points.length <= 2) return points;

  let maxDist = 0, maxIdx = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = distanceToSegment(points[i], points[0], points[points.length - 1]);
    if (d > maxDist) { maxDist = d; maxIdx = i; }
  }

  if (maxDist > epsilon) {
    const left = douglasPeucker(points.slice(0, maxIdx + 1), epsilon);
    const right = douglasPeucker(points.slice(maxIdx), epsilon);
    return left.slice(0, -1).concat(right);
  }

  return [points[0], points[points.length - 1]];
}

// ── Helper: build SVG path from rings ─────────────────────────────────────
function ringsToPath(rings, epsilon) {
  const pathParts = [];
  for (const ring of rings) {
    const projected = ring.map(([lon, lat]) => [
      Math.round(projectLon(lon) * 10) / 10,
      Math.round(projectLat(lat) * 10) / 10,
    ]);
    const simplified = douglasPeucker(projected, epsilon);
    if (simplified.length < 3) continue;
    const [first, ...rest] = simplified;
    let d = `M${first[0]},${first[1]}`;
    for (const [x, y] of rest) {
      d += `L${x},${y}`;
    }
    d += 'Z';
    pathParts.push(d);
  }
  return pathParts.join(' ');
}

// ── Helper: compute bounding box from SVG path string ─────────────────────
function computeBounds(pathStr) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  const regex = /([ML])([\d.]+),([\d.]+)/g;
  let m;
  while ((m = regex.exec(pathStr)) !== null) {
    const x = parseFloat(m[2]);
    const y = parseFloat(m[3]);
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  // Add some padding
  const pad = 8;
  return {
    x: Math.round((minX - pad) * 10) / 10,
    y: Math.round((minY - pad) * 10) / 10,
    width: Math.round((maxX - minX + pad * 2) * 10) / 10,
    height: Math.round((maxY - minY + pad * 2) * 10) / 10,
  };
}

// ══════════════════════════════════════════════════════════════════════════
// FILE 1: District paths (same as before)
// ══════════════════════════════════════════════════════════════════════════
const EPSILON_DISTRICT = 0.9;
const districtPaths = {};

for (const [name, rings] of districtPolygons) {
  const p = ringsToPath(rings, EPSILON_DISTRICT);
  if (p) districtPaths[name] = p;
}

console.log(`Generated SVG paths for ${Object.keys(districtPaths).length} districts.`);

const districtLines = Object.entries(districtPaths)
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([name, path]) => `  ${JSON.stringify(name)}: ${JSON.stringify(path)},`)
  .join('\n');

const districtOutput = `// Auto-generated from bangladesh.geojson – DO NOT EDIT MANUALLY
// Source: https://github.com/ifahimreza/bangladesh-geojson (CC BY 4.0)
// Generated at: ${new Date().toISOString()}

export const DISTRICT_PATHS: Record<string, string> = {
${districtLines}
};

export const SVG_VIEWBOX = '0 0 ${SVG_W} ${SVG_H}';
`;

writeFileSync(OUTPUT_DISTRICTS, districtOutput, 'utf-8');
console.log(`✅ District paths: ${OUTPUT_DISTRICTS} (${(Buffer.byteLength(districtOutput) / 1024).toFixed(1)} KB)`);

// ══════════════════════════════════════════════════════════════════════════
// FILE 2: Upazila paths + district bounding boxes
// ══════════════════════════════════════════════════════════════════════════
const EPSILON_UPAZILA = 0.5; // finer detail for upazilas
const upazilaPathsByDistrict = {};
const districtBounds = {};

for (const [districtName, upMap] of upazilaData) {
  const upazilaObj = {};
  for (const [upazilaName, entry] of upMap) {
    const p = ringsToPath(entry.rings, EPSILON_UPAZILA);
    if (p) upazilaObj[upazilaName] = p;
  }
  if (Object.keys(upazilaObj).length > 0) {
    upazilaPathsByDistrict[districtName] = upazilaObj;
  }

  // Compute bounding box from the district path
  if (districtPaths[districtName]) {
    districtBounds[districtName] = computeBounds(districtPaths[districtName]);
  }
}

console.log(`Generated upazila paths for ${Object.keys(upazilaPathsByDistrict).length} districts.`);

// Build output
const upLines = [];
for (const [dist, upazilas] of Object.entries(upazilaPathsByDistrict).sort(([a],[b]) => a.localeCompare(b))) {
  const inner = Object.entries(upazilas)
    .sort(([a],[b]) => a.localeCompare(b))
    .map(([name, path]) => `    ${JSON.stringify(name)}: ${JSON.stringify(path)},`)
    .join('\n');
  upLines.push(`  ${JSON.stringify(dist)}: {\n${inner}\n  },`);
}

const boundsLines = Object.entries(districtBounds)
  .sort(([a],[b]) => a.localeCompare(b))
  .map(([name, b]) => `  ${JSON.stringify(name)}: { x: ${b.x}, y: ${b.y}, width: ${b.width}, height: ${b.height} },`)
  .join('\n');

const upOutput = `// Auto-generated from bangladesh.geojson – DO NOT EDIT MANUALLY
// Upazila-level SVG paths grouped by district, for drill-down map view
// Generated at: ${new Date().toISOString()}

export const UPAZILA_PATHS: Record<string, Record<string, string>> = {
${upLines.join('\n')}
};

export const DISTRICT_BOUNDS: Record<string, { x: number; y: number; width: number; height: number }> = {
${boundsLines}
};
`;

// ══════════════════════════════════════════════════════════════════════════
// RIVERS: major river paths projected through the same Mercator transform
// ══════════════════════════════════════════════════════════════════════════
const RIVERS = {
  // Padma: Entry near Chapai Nawabganj (88.05E,24.67N) -> past Rajshahi -> Goalundo confluence (89.75E,23.83N) -> Chandpur (90.62E,23.22N)
  Padma: [
    [88.05,24.67],[88.12,24.63],[88.20,24.58],[88.28,24.52],[88.35,24.48],[88.40,24.43],
    [88.48,24.40],[88.55,24.38],[88.60,24.35],[88.65,24.30],[88.72,24.25],[88.80,24.20],
    [88.88,24.15],[88.95,24.10],[89.02,24.07],[89.10,24.03],[89.18,23.98],[89.25,23.95],
    [89.32,23.92],[89.40,23.90],[89.48,23.88],[89.55,23.86],[89.62,23.84],[89.68,23.83],
    [89.75,23.83], // Goalundo confluence with Jamuna
    [89.82,23.80],[89.88,23.75],[89.95,23.68],[90.02,23.60],[90.08,23.55],[90.15,23.50],
    [90.22,23.45],[90.28,23.40],[90.35,23.35],[90.42,23.30],[90.48,23.27],[90.55,23.24],
    [90.62,23.22], // Chandpur confluence with Meghna
  ],
  // Jamuna: Entry at Kurigram (89.75E,25.67N) -> south through Sirajganj -> Goalundo (89.75E,23.83N)
  Jamuna: [
    [89.75,25.67],[89.73,25.58],[89.70,25.50],[89.72,25.42],[89.75,25.35],[89.73,25.28],
    [89.70,25.20],[89.68,25.12],[89.72,25.05],[89.75,24.98],[89.78,24.90],[89.80,24.82],
    [89.82,24.75],[89.85,24.68],[89.88,24.60],[89.90,24.52],[89.92,24.45],[89.90,24.38],
    [89.88,24.30],[89.85,24.22],[89.82,24.15],[89.80,24.08],[89.78,24.00],[89.76,23.93],
    [89.75,23.83], // Goalundo confluence
  ],
  // Meghna: Forms near Bhairab (90.98E,24.25N) -> south to Chandpur (90.62E,23.22N) -> Bay of Bengal estuary
  Meghna: [
    [90.98,24.25],[90.95,24.18],[90.92,24.10],[90.88,24.02],[90.85,23.95],[90.82,23.88],
    [90.78,23.80],[90.75,23.72],[90.72,23.65],[90.70,23.58],[90.68,23.50],[90.65,23.42],
    [90.63,23.35],[90.62,23.28],[90.62,23.22], // Chandpur confluence with Padma
  ],
  // Lower Meghna / Estuary: Chandpur -> Bay of Bengal (wide estuary)
  'Lower Meghna': [
    [90.62,23.22],[90.65,23.15],[90.68,23.08],[90.72,23.00],[90.75,22.92],[90.78,22.85],
    [90.80,22.78],[90.82,22.70],[90.85,22.62],[90.88,22.55],[90.90,22.48],[90.92,22.40],
  ],
  // Surma: From Sylhet region (91.87E,24.90N) -> west to Bhairab confluence with Meghna
  Surma: [
    [91.87,24.90],[91.78,24.89],[91.70,24.87],[91.62,24.86],[91.55,24.84],[91.48,24.82],
    [91.40,24.80],[91.32,24.78],[91.25,24.75],[91.18,24.72],[91.12,24.68],[91.05,24.62],
    [90.98,24.55],[90.95,24.48],[90.92,24.42],[90.90,24.35],[90.92,24.28],[90.98,24.25],
  ],
  // Teesta: From Rangpur (88.72E,26.33N) -> south to join Jamuna near Gaibandha
  Teesta: [
    [88.72,26.33],[88.75,26.25],[88.78,26.18],[88.80,26.10],[88.83,26.02],[88.85,25.95],
    [88.88,25.88],[88.92,25.80],[88.96,25.72],[89.00,25.65],[89.05,25.58],[89.10,25.52],
    [89.18,25.45],[89.25,25.38],[89.32,25.32],[89.40,25.25],[89.48,25.18],[89.55,25.10],
    [89.60,25.02],[89.65,24.95],[89.68,24.90],
  ],
  // Karnaphuli: From Chittagong hills (92.22E,22.55N) -> west to Chattogram port (91.80E,22.32N)
  Karnaphuli: [
    [92.22,22.55],[92.15,22.52],[92.08,22.50],[92.00,22.48],[91.95,22.45],[91.90,22.42],
    [91.85,22.40],[91.80,22.38],[91.75,22.36],[91.70,22.34],[91.65,22.33],[91.60,22.32],
  ],
  // Old Brahmaputra: branches from Jamuna near Jamalpur -> east to Bhairab
  'Old Brahmaputra': [
    [89.85,24.95],[89.92,24.92],[90.00,24.88],[90.08,24.85],[90.15,24.82],[90.22,24.78],
    [90.30,24.72],[90.38,24.65],[90.45,24.58],[90.52,24.50],[90.60,24.42],[90.68,24.38],
    [90.75,24.35],[90.82,24.30],[90.90,24.28],[90.98,24.25],
  ],
};

const riverPaths = {};
for (const [name, waypoints] of Object.entries(RIVERS)) {
  const projected = waypoints.map(([lon, lat]) => [
    Math.round(projectLon(lon) * 10) / 10,
    Math.round(projectLat(lat) * 10) / 10,
  ]);
  const [first, ...rest] = projected;
  let d = `M${first[0]},${first[1]}`;
  // Use quadratic curves for smooth river lines
  for (let i = 0; i < rest.length - 1; i++) {
    const mid = [(rest[i][0] + rest[i+1][0]) / 2, (rest[i][1] + rest[i+1][1]) / 2];
    d += `Q${rest[i][0]},${rest[i][1]} ${Math.round(mid[0]*10)/10},${Math.round(mid[1]*10)/10}`;
  }
  d += `L${rest[rest.length-1][0]},${rest[rest.length-1][1]}`;
  riverPaths[name] = d;
}
console.log(`Generated ${Object.keys(riverPaths).length} river paths.`);

const riverLines = Object.entries(riverPaths)
  .map(([name, path]) => `  ${JSON.stringify(name)}: ${JSON.stringify(path)},`)
  .join('\n');

// Append rivers to the upazila output
const finalUpOutput = upOutput + `\nexport const RIVER_PATHS: Record<string, string> = {\n${riverLines}\n};\n`;

writeFileSync(OUTPUT_UPAZILAS, finalUpOutput, 'utf-8');
console.log(`✅ Upazila paths + rivers: ${OUTPUT_UPAZILAS} (${(Buffer.byteLength(finalUpOutput) / 1024).toFixed(1)} KB)`);
