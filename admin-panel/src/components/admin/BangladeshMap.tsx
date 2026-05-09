import { useState, useCallback, useMemo, useRef, useEffect, type MouseEvent } from 'react';
import type { DistrictSummary } from '@/types';
import { DISTRICT_PATHS, SVG_VIEWBOX } from './districtPaths';
import { UPAZILA_PATHS, DISTRICT_BOUNDS, RIVER_PATHS } from './upazilaPaths';

interface BangladeshMapProps {
  districtData: DistrictSummary[];
  selectedDistrict: string | null;
  onDistrictClick: (district: string) => void;
}

/* ─── Alias & Division maps ─── */
const ALIAS: Record<string, string> = {
  Comilla:'Cumilla', Chittagong:'Chattogram', Jessore:'Jashore', Bogra:'Bogura',
  Brahamanbaria:'Brahmanbaria', Moulvibazar:'Maulvibazar',
  Chapainawabganj:'Nawabganj', Khagrachhari:'Khagrachari',
};
const canon = (n: string) => ALIAS[n.trim()] ?? n.trim();

type Div = 'Barishal'|'Chattogram'|'Dhaka'|'Khulna'|'Mymensingh'|'Rajshahi'|'Rangpur'|'Sylhet';
const DM: Record<string, Div> = {
  Barguna:'Barishal',Barishal:'Barishal',Bhola:'Barishal',Jhalokati:'Barishal',Patuakhali:'Barishal',Pirojpur:'Barishal',
  Bandarban:'Chattogram',Brahmanbaria:'Chattogram',Chandpur:'Chattogram',Chattogram:'Chattogram',Cumilla:'Chattogram',
  "Cox's Bazar":'Chattogram',Feni:'Chattogram',Khagrachari:'Chattogram',Lakshmipur:'Chattogram',Noakhali:'Chattogram',Rangamati:'Chattogram',
  Dhaka:'Dhaka',Faridpur:'Dhaka',Gazipur:'Dhaka',Gopalganj:'Dhaka',Kishoreganj:'Dhaka',Madaripur:'Dhaka',Manikganj:'Dhaka',
  Munshiganj:'Dhaka',Narayanganj:'Dhaka',Narsingdi:'Dhaka',Rajbari:'Dhaka',Shariatpur:'Dhaka',Tangail:'Dhaka',
  Bagerhat:'Khulna',Chuadanga:'Khulna',Jashore:'Khulna',Jhenaidah:'Khulna',Khulna:'Khulna',Kushtia:'Khulna',
  Magura:'Khulna',Meherpur:'Khulna',Narail:'Khulna',Satkhira:'Khulna',
  Jamalpur:'Mymensingh',Mymensingh:'Mymensingh',Netrokona:'Mymensingh',Sherpur:'Mymensingh',
  Bogura:'Rajshahi',Nawabganj:'Rajshahi',Joypurhat:'Rajshahi',Naogaon:'Rajshahi',Natore:'Rajshahi',
  Pabna:'Rajshahi',Rajshahi:'Rajshahi',Sirajgonj:'Rajshahi',
  Dinajpur:'Rangpur',Gaibandha:'Rangpur',Kurigram:'Rangpur',Lalmonirhat:'Rangpur',Nilphamari:'Rangpur',
  Panchagarh:'Rangpur',Rangpur:'Rangpur',Thakurgaon:'Rangpur',
  Habiganj:'Sylhet',Maulvibazar:'Sylhet',Sunamganj:'Sylhet',Sylhet:'Sylhet',
};

interface DS { fill:string; fillHov:string; stroke:string; }
const DC: Record<Div, DS> = {
  Barishal:   { fill:'#7EC8C8', fillHov:'#5FB8B8', stroke:'#4AA0A0' },
  Chattogram: { fill:'#D4A574', fillHov:'#C48E5C', stroke:'#A87544' },
  Dhaka:      { fill:'#E8C170', fillHov:'#DAAD4C', stroke:'#C49838' },
  Khulna:     { fill:'#8DB580', fillHov:'#72A362', stroke:'#5A8A4C' },
  Mymensingh: { fill:'#A3C9A8', fillHov:'#85B88C', stroke:'#639A6A' },
  Rajshahi:   { fill:'#D49A6A', fillHov:'#C47E48', stroke:'#A66838' },
  Rangpur:    { fill:'#9BB5C4', fillHov:'#7CA0B4', stroke:'#5E88A0' },
  Sylhet:     { fill:'#6BA389', fillHov:'#508E70', stroke:'#3A7358' },
};

const UPZ_SHADES = ['#E0EFEA','#C8E2D4','#B0D5BE','#98C8A8','#80BB92','#68AE7C','#50A166','#389450'];

const gs = (n: string): DS => DC[DM[n]] ?? { fill:'#CBD5E1', fillHov:'#94A3B8', stroke:'#64748B' };

function centroid(d: string) {
  const pts: number[][] = [];
  const re = /([ML])([\d.]+),([\d.]+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(d)) !== null) pts.push([+m[2], +m[3]]);
  if (!pts.length) return { x: 200, y: 280 };
  const s = pts.reduce((a, c) => [a[0]+c[0], a[1]+c[1]], [0, 0]);
  return { x: s[0]/pts.length, y: s[1]/pts.length };
}

const ALL = Object.keys(DISTRICT_PATHS);
const CEN: Record<string, {x:number;y:number}> = {};
for (const [n, p] of Object.entries(DISTRICT_PATHS)) CEN[n] = centroid(p);

/* ─── Parse viewBox string ─── */
function parseVB(vb: string): [number,number,number,number] {
  const p = vb.split(' ').map(Number);
  return [p[0], p[1], p[2], p[3]];
}

/* ─── Component ─── */
export default function BangladeshMap({ districtData, selectedDistrict, onDistrictClick }: BangladeshMapProps) {
  const [hov, setHov] = useState<string | null>(null);
  const [tip, setTip] = useState({ x: 0, y: 0 });
  const containerRef = useRef<HTMLDivElement>(null);
  const [mounted, setMounted] = useState(false);
  const [drill, setDrill] = useState<string | null>(null);
  const [hovUp, setHovUp] = useState<string | null>(null);

  // Manual zoom/pan state
  const [manualZoom, setManualZoom] = useState(1);  // 1 = no zoom, >1 = zoomed in
  const [panOffset, setPanOffset] = useState({ x: 0, y: 0 });  // SVG-coordinate offset
  const isPanning = useRef(false);
  const panStart = useRef({ x: 0, y: 0 });
  const panOffsetStart = useRef({ x: 0, y: 0 });
  const svgRef = useRef<SVGSVGElement>(null);
  const [search, setSearch] = useState('');
  const [layers, setLayers] = useState({ rivers: true, labels: true, heatmap: false, divisions: true });

  // Animated viewBox
  const fullVB = parseVB(SVG_VIEWBOX);
  const targetVB = useMemo<[number,number,number,number]>(() => {
    if (!drill) return fullVB;
    const b = DISTRICT_BOUNDS[drill];
    if (!b) return fullVB;
    return [b.x, b.y, b.width, b.height];
  }, [drill]);

  const [animVB, setAnimVB] = useState<[number,number,number,number]>(fullVB);
  const animRef = useRef<number>(0);
  const startVB = useRef<[number,number,number,number]>(fullVB);
  const endVB = useRef<[number,number,number,number]>(fullVB);
  const animStart = useRef<number>(0);
  const ANIM_MS = 600;

  useEffect(() => {
    startVB.current = [...animVB] as [number,number,number,number];
    endVB.current = targetVB;
    animStart.current = performance.now();
    cancelAnimationFrame(animRef.current);
    const tick = (now: number) => {
      const t = Math.min(1, (now - animStart.current) / ANIM_MS);
      const e = 1 - Math.pow(1 - t, 3);
      const s = startVB.current, d = endVB.current;
      setAnimVB([s[0]+(d[0]-s[0])*e, s[1]+(d[1]-s[1])*e, s[2]+(d[2]-s[2])*e, s[3]+(d[3]-s[3])*e]);
      if (t < 1) animRef.current = requestAnimationFrame(tick);
    };
    animRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(animRef.current);
  }, [targetVB]);

  useEffect(() => { const t = setTimeout(() => setMounted(true), 80); return () => clearTimeout(t); }, []);

  const dataMap = useMemo(() => {
    const m = new Map<string, DistrictSummary>();
    for (const d of districtData) m.set(canon(d.district), d);
    return m;
  }, [districtData]);

  const maxK = useMemo(() => Math.max(1, ...districtData.map(d => d.total_keys_distributed)), [districtData]);
  const maxR = useMemo(() => Math.max(1, ...districtData.map(d => d.reseller_count)), [districtData]);
  const onMove = useCallback((e: MouseEvent) => {
    const rect = containerRef.current?.getBoundingClientRect();
    if (rect) {
      setTip({ x: e.clientX - rect.left, y: e.clientY - rect.top });
    }
  }, []);
  const hovData = hov ? dataMap.get(hov) : null;

  // Risk score: computed purely from existing data (0-10 scale)
  // High keys + low resellers = concentration risk. No data = cold zone.
  const riskMap = useMemo(() => {
    const m = new Map<string, number>();
    for (const name of ALL) {
      const d = dataMap.get(name);
      if (!d) { m.set(name, 0); continue; }
      const keyRatio = d.total_keys_distributed / maxK;
      const concentration = d.reseller_count > 0 ? d.total_keys_distributed / d.reseller_count : 0;
      const maxConc = maxK / Math.max(1, maxR) * 2;
      const concScore = Math.min(1, concentration / Math.max(1, maxConc));
      const score = Math.round((keyRatio * 4 + concScore * 6) * 10) / 10;
      m.set(name, Math.min(10, score));
    }
    return m;
  }, [dataMap, maxK, maxR]);

  // Heatmap color: green (safe) -> yellow -> red (risky)
  const heatColor = (score: number): string => {
    if (score <= 3) return `hsl(${120 - score * 12}, 60%, ${65 - score * 3}%)`;
    if (score <= 6) return `hsl(${84 - (score-3) * 18}, 70%, ${56 - (score-3) * 4}%)`;
    return `hsl(${30 - (score-6) * 8}, 80%, ${44 - (score-6) * 3}%)`;
  };

  // Search filter
  const searchResults = useMemo(() => {
    if (!search.trim()) return [];
    const q = search.toLowerCase();
    return ALL.filter(n => n.toLowerCase().includes(q)).slice(0, 5);
  }, [search]);

  const clickDistrict = (name: string) => {
    if (UPAZILA_PATHS[name] && Object.keys(UPAZILA_PATHS[name]).length > 0) {
      setDrill(name); setHov(null);
      setManualZoom(1); setPanOffset({ x: 0, y: 0 });
    }
    onDistrictClick(name);
    setSearch('');
  };
  const goBack = () => { setDrill(null); setHovUp(null); setManualZoom(1); setPanOffset({ x: 0, y: 0 }); };
  const toggleLayer = (k: keyof typeof layers) => setLayers(p => ({ ...p, [k]: !p[k] }));

  // Manual zoom/pan handlers (wheel zoom is handled via native event listener)

  const handlePanStart = useCallback((e: MouseEvent) => {
    if (e.button !== 0) return;
    isPanning.current = true;
    panStart.current = { x: e.clientX, y: e.clientY };
    panOffsetStart.current = { ...panOffset };
    e.preventDefault();
  }, [panOffset]);

  const handlePanMove = useCallback((e: MouseEvent) => {
    if (!isPanning.current) return;
    const svg = svgRef.current;
    if (!svg) return;
    const rect = svg.getBoundingClientRect();
    // Convert pixel drag to SVG coordinate drag
    const dx = (e.clientX - panStart.current.x) / rect.width * (animVB[2] / manualZoom);
    const dy = (e.clientY - panStart.current.y) / rect.height * (animVB[3] / manualZoom);
    setPanOffset({ x: panOffsetStart.current.x - dx, y: panOffsetStart.current.y - dy });
  }, [animVB, manualZoom]);

  const handlePanEnd = useCallback(() => { isPanning.current = false; }, []);

  // Attach native wheel listener (passive:false to prevent page scroll)
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;
    const onWheel = (e: globalThis.WheelEvent) => {
      e.preventDefault();
      const rect = svg.getBoundingClientRect();
      const mx = (e.clientX - rect.left) / rect.width;
      const my = (e.clientY - rect.top) / rect.height;
      const zoomFactor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
      setManualZoom(prev => {
        const next = Math.min(8, Math.max(0.5, prev * zoomFactor));
        const scale = next / prev;
        setPanOffset(po => ({
          x: po.x + (animVB[2] / prev) * mx * (1 - 1/scale) * prev,
          y: po.y + (animVB[3] / prev) * my * (1 - 1/scale) * prev,
        }));
        return next;
      });
    };
    svg.addEventListener('wheel', onWheel, { passive: false });
    return () => svg.removeEventListener('wheel', onWheel);
  }, [animVB]);

  useEffect(() => {
    const up = () => { isPanning.current = false; };
    window.addEventListener('mouseup', up);
    return () => window.removeEventListener('mouseup', up);
  }, []);

  const resetView = () => { setManualZoom(1); setPanOffset({ x: 0, y: 0 }); };
  const isZoomedOrPanned = manualZoom !== 1 || panOffset.x !== 0 || panOffset.y !== 0;

  // Compose final viewBox: animated target + manual zoom/pan
  const finalVB = useMemo(() => {
    const w = animVB[2] / manualZoom;
    const h = animVB[3] / manualZoom;
    const cx = animVB[0] + animVB[2] / 2 + panOffset.x;
    const cy = animVB[1] + animVB[3] / 2 + panOffset.y;
    return [cx - w/2, cy - h/2, w, h] as [number,number,number,number];
  }, [animVB, manualZoom, panOffset]);

  const vbStr = finalVB.map(v => Math.round(v * 100) / 100).join(' ');

  return (
    <div ref={containerRef} className="relative select-none" onMouseMove={onMove}>
      <style>{`
        @keyframes mapReveal {
          0%   { opacity:0; transform:scale(0.82) translateY(24px); filter:blur(6px); }
          60%  { opacity:1; filter:blur(0); }
          100% { opacity:1; transform:scale(1) translateY(0); filter:blur(0); }
        }
        @keyframes fadeInUp { from{opacity:0;transform:translateY(8px)} to{opacity:1;transform:translateY(0)} }
        @keyframes pulse { 0%,100%{opacity:.6;r:3} 50%{opacity:1;r:5} }
        .bd-w{opacity:0;transform:scale(.82) translateY(24px);filter:blur(6px)}
        .bd-w.on{animation:mapReveal .9s cubic-bezier(.22,1,.36,1) forwards}
        .bd-d{cursor:pointer;transition:filter .2s,opacity .2s}.bd-d:hover{filter:brightness(1.12)}
        .bd-u{cursor:pointer;transition:filter .2s,transform .2s}.bd-u:hover{filter:brightness(1.15) drop-shadow(0 0 4px rgba(255,180,77,.4))}
        .bd-pulse{animation:pulse 2s ease-in-out infinite}
      `}</style>

      {/* ─── Toolbar: Search + Layer Toggles ─── */}
      <div className="mb-3 flex flex-wrap items-center gap-2">
        {/* Search */}
        <div className="relative flex-1 min-w-[160px] max-w-[240px]">
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search district…"
            className="w-full pl-8 pr-3 py-1.5 rounded-lg text-xs border bg-white/80 backdrop-blur outline-none focus:ring-2 focus:ring-emerald-400/40"
            style={{ borderColor:'rgba(148,163,153,0.3)' }} />
          <svg className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><circle cx="11" cy="11" r="8" strokeWidth="2"/><path d="M21 21l-4.35-4.35" strokeWidth="2" strokeLinecap="round"/></svg>
          {searchResults.length > 0 && (
            <div className="absolute top-full left-0 mt-1 w-full bg-white rounded-lg shadow-lg border z-50 overflow-hidden"
              style={{ borderColor:'rgba(148,163,153,0.2)' }}>
              {searchResults.map(n => (
                <button key={n} onClick={() => clickDistrict(n)}
                  className="w-full px-3 py-1.5 text-left text-xs hover:bg-emerald-50 flex items-center gap-2 transition-colors">
                  <span style={{ width:6,height:6,borderRadius:'50%',backgroundColor:gs(n).fill,flexShrink:0 }} />
                  <span className="font-medium text-gray-800">{n}</span>
                  <span className="ml-auto text-gray-400 text-[10px]">{DM[n]}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Layer toggles */}
        {(['rivers','labels','heatmap','divisions'] as const).map(k => (
          <button key={k} onClick={() => toggleLayer(k)}
            className="px-2.5 py-1 rounded-lg text-[10px] font-semibold uppercase tracking-wider transition-all duration-150"
            style={{
              background: layers[k] ? 'linear-gradient(135deg,#e8f5e9,#c8e6c9)' : 'rgba(0,0,0,0.04)',
              color: layers[k] ? '#2e7d32' : '#9e9e9e',
              border: `1px solid ${layers[k] ? 'rgba(46,125,50,0.25)' : 'rgba(0,0,0,0.08)'}`,
            }}>
            {k === 'rivers' ? '🌊' : k === 'labels' ? '🏷' : k === 'heatmap' ? '🔥' : '🗺'} {k}
          </button>
        ))}
      </div>

      {/* Back button */}
      {drill && (
        <button onClick={goBack} className="mb-3 flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold transition-all duration-200 hover:scale-105 active:scale-95"
          style={{ background:'linear-gradient(135deg,rgba(255,255,255,.9),rgba(245,250,248,.85))',
            border:'1px solid rgba(148,163,153,.3)', boxShadow:'0 2px 8px rgba(0,0,0,.06)', color:'#1a3a2a' }}>
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M10 12L6 8L10 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Back to Bangladesh · <span style={{ color:gs(drill).stroke, fontWeight:700 }}>{drill}</span>
        </button>
      )}

      <div className={`bd-w rounded-2xl overflow-hidden ${mounted?'on':''}`}
        style={{ background:'linear-gradient(145deg,#F0F7F4,#E2EDE7 40%,#D5E5DC)',
          boxShadow:'0 4px 24px rgba(0,0,0,.06),0 1px 4px rgba(0,0,0,.04),inset 0 1px 0 rgba(255,255,255,.6)',
          border:'1px solid rgba(148,163,153,.25)', position:'relative' }}>

        {/* Zoom controls overlay */}
        <div style={{ position:'absolute', right:12, top:12, zIndex:20, display:'flex', flexDirection:'column', gap:4 }}>
          <button onClick={() => setManualZoom(z => Math.min(8, z * 1.3))}
            title="Zoom in" className="hover:scale-110 active:scale-95 transition-transform"
            style={{ width:32, height:32, borderRadius:8, border:'1px solid rgba(148,163,153,.3)',
              background:'rgba(255,255,255,.9)', color:'#1a3a2a', fontSize:18, cursor:'pointer',
              display:'flex', alignItems:'center', justifyContent:'center', fontWeight:700,
              boxShadow:'0 2px 6px rgba(0,0,0,.08)' }}>+</button>
          <button onClick={() => setManualZoom(z => Math.max(0.5, z / 1.3))}
            title="Zoom out" className="hover:scale-110 active:scale-95 transition-transform"
            style={{ width:32, height:32, borderRadius:8, border:'1px solid rgba(148,163,153,.3)',
              background:'rgba(255,255,255,.9)', color:'#1a3a2a', fontSize:18, cursor:'pointer',
              display:'flex', alignItems:'center', justifyContent:'center', fontWeight:700,
              boxShadow:'0 2px 6px rgba(0,0,0,.08)' }}>−</button>
          {isZoomedOrPanned && (
            <button onClick={resetView}
              title="Reset view" className="hover:scale-110 active:scale-95 transition-transform"
              style={{ width:32, height:32, borderRadius:8, border:'1px solid rgba(148,163,153,.3)',
                background:'rgba(255,255,255,.9)', color:'#E65100', fontSize:12, cursor:'pointer',
                display:'flex', alignItems:'center', justifyContent:'center', fontWeight:700,
                boxShadow:'0 2px 6px rgba(0,0,0,.08)' }}>⟲</button>
          )}
        </div>
        {/* Zoom level indicator */}
        {manualZoom !== 1 && (
          <div style={{ position:'absolute', left:12, bottom:12, zIndex:20, padding:'3px 8px',
            borderRadius:6, background:'rgba(0,0,0,.5)', color:'#fff', fontSize:10, fontWeight:600 }}>
            {Math.round(manualZoom * 100)}%
          </div>
        )}

        <svg ref={svgRef} viewBox={vbStr} className="w-full h-auto"
          style={{ maxHeight:'72vh', cursor: isPanning.current ? 'grabbing' : 'grab' }}
          onMouseDown={handlePanStart}
          onMouseMove={(e) => { onMove(e); handlePanMove(e); }}
          onMouseUp={handlePanEnd}
          onMouseLeave={handlePanEnd}>
          <defs>
            <filter id="bd-sh" x="-4%" y="-4%" width="108%" height="108%">
              <feDropShadow dx=".5" dy="1.2" stdDeviation="1.5" floodColor="#1a3a2a" floodOpacity=".12" />
            </filter>
            <filter id="bd-bv" x="-8%" y="-8%" width="120%" height="120%">
              <feDropShadow dx="0" dy="0" stdDeviation="3" floodColor="#fff" floodOpacity=".4" />
              <feDropShadow dx=".8" dy="1.8" stdDeviation="2" floodColor="#1a3a2a" floodOpacity=".2" />
            </filter>
            <filter id="bd-gl" x="-12%" y="-12%" width="130%" height="130%">
              <feDropShadow dx="0" dy="0" stdDeviation="4" floodColor="#FFB74D" floodOpacity=".5" />
            </filter>
            <linearGradient id="sheen" x1="0" y1="0" x2=".4" y2="1">
              <stop offset="0%" stopColor="white" stopOpacity=".18" />
              <stop offset="100%" stopColor="white" stopOpacity="0" />
            </linearGradient>
            <radialGradient id="water" cx="50%" cy="85%" r="60%">
              <stop offset="0%" stopColor="#B8D8E8" stopOpacity=".4" />
              <stop offset="100%" stopColor="#D5E5DC" stopOpacity="0" />
            </radialGradient>
          </defs>

          {/* Bay of Bengal */}
          {!drill && <ellipse cx="200" cy="520" rx="180" ry="80" fill="url(#water)" />}

          {/* ─── DISTRICT VIEW ─── */}
          {!drill && ALL.map(name => {
            const path = DISTRICT_PATHS[name]; if (!path) return null;
            const st = gs(name); const isH = hov===name; const isS = selectedDistrict===name;
            const c = CEN[name]; const data = dataMap.get(name);
            const risk = riskMap.get(name) ?? 0;
            const fillColor = isS ? '#FFB74D' : isH ? st.fillHov : layers.heatmap ? heatColor(risk) : st.fill;
            const divBorder = layers.divisions ? st.stroke : 'rgba(255,255,255,0.3)';
            return (
              <g key={name} className="bd-d"
                style={{ transition:'transform .25s cubic-bezier(.34,1.56,.64,1)',
                  transformOrigin:`${c.x}px ${c.y}px`,
                  transform:isH?'scale(1.06)':isS?'scale(1.03)':'scale(1)' }}
                onClick={() => clickDistrict(name)}
                onMouseEnter={() => setHov(name)} onMouseLeave={() => setHov(null)}>
                <path d={path} fill={fillColor}
                  stroke={isS?'#E65100':divBorder} strokeWidth={isS?1.2:isH?.8:.4}
                  strokeLinejoin="round" filter={isS?'url(#bd-gl)':isH?'url(#bd-bv)':'url(#bd-sh)'} />
                <path d={path} fill="url(#sheen)" stroke="none" pointerEvents="none" />
                {/* Pulse dot for high-risk or high-activity districts */}
                {risk > 5 && layers.heatmap && (
                  <circle className="bd-pulse" cx={c.x} cy={c.y} r={3} fill="#EF5350" opacity={0.7} pointerEvents="none" />
                )}
                {data && data.total_keys_distributed > 0 && !layers.heatmap && (
                  <circle cx={c.x} cy={c.y} r={2 + (data.total_keys_distributed/maxK)*6}
                    fill="#FFD54F" opacity={0.4} pointerEvents="none" />
                )}
              </g>
            );
          })}

          {/* ─── Rivers (conditional) ─── */}
          {layers.rivers && Object.entries(RIVER_PATHS).map(([name, path]) => {
            const widthMap: Record<string,number> = {
              Padma: 2.5, Jamuna: 2.2, Meghna: 2.0, 'Lower Meghna': 2.8,
              Surma: 1.4, Teesta: 1.3, Karnaphuli: 1.2, 'Old Brahmaputra': 1.1,
            };
            const baseWidth = widthMap[name] ?? 1.0;
            const zoomScale = drill ? Math.sqrt(fullVB[2] / Math.max(1, animVB[2])) : 1;
            const sw = baseWidth / Math.max(0.8, zoomScale * 0.6);
            return (
              <path key={`river-${name}`} d={path} fill="none"
                stroke="#4A90C4" strokeWidth={sw}
                strokeLinecap="round" strokeLinejoin="round"
                strokeDasharray={name === 'Old Brahmaputra' ? '3 2' : 'none'}
                opacity={drill ? 0.4 : 0.3} pointerEvents="none" />
            );
          })}

          {/* ─── UPAZILA DRILL-DOWN ─── */}
          {drill && (() => {
            const upz = UPAZILA_PATHS[drill]; if (!upz) return null;
            const st = gs(drill); const entries = Object.entries(upz);
            const distPath = DISTRICT_PATHS[drill];
            return (
              <>
                {/* Ghost surrounding districts */}
                {ALL.map(n => {
                  if (n === drill) return null;
                  const p = DISTRICT_PATHS[n]; if (!p) return null;
                  return <path key={`g-${n}`} d={p} fill="#E8EDE9" stroke="#D0D8D2" strokeWidth={.25} opacity={.4} pointerEvents="none" />;
                })}

                {/* Solid district backdrop — eliminates gaps between upazilas */}
                {distPath && <path d={distPath} fill={st.fill} stroke={st.stroke} strokeWidth={.5} strokeLinejoin="round" filter="url(#bd-sh)" />}

                {/* Upazila interactive overlays with subtle distinct fills */}
                {entries.map(([uN, uP], i) => {
                  const isH = hovUp === uN;
                  const c = centroid(uP);
                  // Alternate light overlays on top of the district base color
                  const overlayOpacity = isH ? 0.5 : (i % 2 === 0 ? 0.15 : 0.05);
                  return (
                    <g key={uN} className="bd-u"
                      style={{ transition:'transform .2s cubic-bezier(.34,1.56,.64,1)',
                        transformOrigin:`${c.x}px ${c.y}px`, transform:isH?'scale(1.03)':'scale(1)' }}
                      onMouseEnter={() => setHovUp(uN)} onMouseLeave={() => setHovUp(null)}>
                      {/* Semi-transparent fill on top of district base */}
                      <path d={uP} fill={isH ? '#fff' : '#fff'} fillOpacity={overlayOpacity}
                        stroke={isH ? st.stroke : 'rgba(255,255,255,0.5)'} strokeWidth={isH ? .6 : .3}
                        strokeLinejoin="round" />
                      {isH && <path d={uP} fill="none" stroke={st.stroke} strokeWidth={.8} strokeLinejoin="round"
                        filter="url(#bd-bv)" />}
                    </g>
                  );
                })}
                {hovUp && (() => {
                  const uP = upz[hovUp]; if (!uP) return null;
                  const c = centroid(uP);
                  const b = DISTRICT_BOUNDS[drill];
                  const fs = b ? Math.max(2.5, Math.min(5, b.width / 18)) : 4;
                  const labelW = hovUp.length * fs * 0.55 + 10;
                  const labelH = fs * 2;
                  return (
                    <g pointerEvents="none">
                      <rect x={c.x - labelW/2} y={c.y - labelH/2}
                        width={labelW} height={labelH} rx={labelH/2}
                        fill="rgba(26,58,42,0.88)" stroke="rgba(255,255,255,0.25)" strokeWidth={0.3} />
                      <text x={c.x} y={c.y + fs * 0.08} textAnchor="middle" dominantBaseline="central"
                        style={{ fontSize:`${fs}px`, fontWeight:700, fill:'#fff', letterSpacing:'.3px',
                          fontFamily:"'Inter','Segoe UI',sans-serif" }}>
                        {hovUp}
                      </text>
                    </g>
                  );
                })()}
              </>
            );
          })()}

          {/* Always-visible district names for full view */}
          {!drill && layers.labels && ALL.map(name => {
            const c = CEN[name]; if (!c) return null;
            const isH = hov === name; const isS = selectedDistrict === name;
            const short = name.length > 11 ? name.slice(0, 9) + '…' : name;
            return (
              <g key={`lbl-${name}`} pointerEvents="none">
                {/* White glow backdrop for readability */}
                <text x={c.x} y={c.y} textAnchor="middle" dominantBaseline="central"
                  style={{ fontSize: isH || isS ? '5.5px' : '4.8px', fontWeight:700,
                    fill:'white', letterSpacing:'.2px',
                    fontFamily:"'Inter','Segoe UI',sans-serif",
                    stroke:'rgba(255,255,255,0.9)', strokeWidth: 2.5, strokeLinejoin:'round' }}>
                  {short}
                </text>
                {/* Actual text */}
                <text x={c.x} y={c.y} textAnchor="middle" dominantBaseline="central"
                  style={{ fontSize: isH || isS ? '5.5px' : '4.8px',
                    fontWeight: isH || isS ? 800 : 700,
                    fill: isS ? '#E65100' : isH ? '#0D4F2B' : '#1a3a2a',
                    letterSpacing:'.2px',
                    fontFamily:"'Inter','Segoe UI',sans-serif",
                    transition:'all .2s ease' }}>
                  {short}
                </text>
              </g>
            );
          })}

          {/* Hover/Selected label removed — tooltip follows cursor instead */}

          {/* Compass */}
          {!drill && (
            <g transform="translate(370,30)" opacity=".35">
              <circle r="12" fill="none" stroke="#4A6B5A" strokeWidth=".6" />
              <line y1="-11" y2="-6" stroke="#4A6B5A" strokeWidth=".8" />
              <line y1="6" y2="11" stroke="#4A6B5A" strokeWidth=".4" />
              <line x1="-11" x2="-6" stroke="#4A6B5A" strokeWidth=".4" />
              <line x1="6" x2="11" stroke="#4A6B5A" strokeWidth=".4" />
              <text y="-14" textAnchor="middle" style={{ fontSize:'5px', fill:'#4A6B5A', fontWeight:700 }}>N</text>
            </g>
          )}
        </svg>
      </div>

      {/* ─── Tooltip ─── */}
      {(hov || (drill && hovUp)) && (() => {
        const cw = containerRef.current?.offsetWidth ?? 800;
        const ch = containerRef.current?.offsetHeight ?? 600;
        const flipX = tip.x > cw - 240;
        const flipY = tip.y > ch - 120;
        return (
        <div className="pointer-events-none absolute" style={{
          left: flipX ? tip.x - 14 : tip.x + 14,
          top: flipY ? tip.y - 14 : tip.y + 18,
          transform: flipX ? 'translateX(-100%)' : 'none',
          zIndex: 9999,
          maxWidth: 220,
        }}>
          <div style={{ background:'linear-gradient(135deg,rgba(255,255,255,.92),rgba(245,250,248,.88))',
            backdropFilter:'blur(16px) saturate(1.8)', borderRadius:'14px',
            border:'1px solid rgba(148,163,153,.3)', padding:'10px 16px',
            boxShadow:'0 12px 40px rgba(0,0,0,.08),0 4px 12px rgba(0,0,0,.04)' }}>
            {drill && hovUp ? (
              <>
                <div className="flex items-center gap-2">
                  <span style={{ width:8,height:8,borderRadius:'50%',backgroundColor:gs(drill).fill,
                    border:`1.5px solid ${gs(drill).stroke}`,flexShrink:0 }} />
                  <span style={{ fontWeight:700,color:'#1a3a2a',fontSize:'13px' }}>{hovUp}</span>
                </div>
                <p style={{ color:'#4A6B5A',fontSize:'11px',marginTop:3,fontWeight:500 }}>Upazila · {drill} District</p>
              </>
            ) : hov ? (() => {
              const risk = riskMap.get(hov) ?? 0;
              const riskLabel = risk <= 3 ? 'Low' : risk <= 6 ? 'Medium' : 'High';
              const riskColor = risk <= 3 ? '#4CAF50' : risk <= 6 ? '#FF9800' : '#EF5350';
              return (
                <>
                  <div className="flex items-center gap-2">
                    <span style={{ width:8,height:8,borderRadius:'50%',backgroundColor:gs(hov).fill,
                      border:`1.5px solid ${gs(hov).stroke}`,flexShrink:0 }} />
                    <span style={{ fontWeight:700,color:'#1a3a2a',fontSize:'13px' }}>{hov}</span>
                    <span style={{ fontSize:'10px',color:'#6b8f7a',fontWeight:500 }}>{DM[hov]??''}</span>
                  </div>
                  <div style={{ display:'flex',gap:'8px',marginTop:4,fontSize:'11px',color:'#4A6B5A',fontWeight:500 }}>
                    {hovData ? (
                      <>
                        <span>{hovData.reseller_count} reseller{hovData.reseller_count!==1?'s':''}</span>
                        <span style={{opacity:0.4}}>·</span>
                        <span>{hovData.total_keys_distributed} keys</span>
                      </>
                    ) : <span>No data yet</span>}
                    <span style={{opacity:0.4}}>·</span>
                    <span style={{color:riskColor,fontWeight:700}}>Risk: {riskLabel} ({risk})</span>
                  </div>
                  <p style={{ color:'#7a9a8a',fontSize:'10px',marginTop:2 }}>Click to view upazilas →</p>
                </>
              );
            })() : null}
          </div>
        </div>
        ); })()}

      {/* Legend */}
      {!drill ? (
        <div className="mt-4 space-y-2">
          {/* Division legend */}
          <div className="grid gap-x-4 gap-y-1.5" style={{ gridTemplateColumns:'repeat(4,auto)', fontSize:'11px' }}>
            {(Object.entries(DC) as [Div,DS][]).map(([d,s]) => (
              <span key={d} className="inline-flex items-center gap-1.5">
                <span style={{ width:12,height:12,borderRadius:3,backgroundColor:s.fill,
                  border:`1.5px solid ${s.stroke}`,boxShadow:'0 1px 2px rgba(0,0,0,.08)',flexShrink:0 }} />
                <span style={{ color:'#3d5a4a',fontWeight:500 }}>{d}</span>
              </span>
            ))}
          </div>
          {/* Heatmap gradient legend */}
          {layers.heatmap && (
            <div className="flex items-center gap-2 pt-1" style={{ fontSize:'10px', color:'#4A6B5A' }}>
              <span className="font-semibold">Risk:</span>
              <span style={{color:'#4CAF50'}}>Low</span>
              <div style={{
                width:120, height:8, borderRadius:4,
                background:'linear-gradient(90deg, hsl(120,60%,65%), hsl(60,70%,50%), hsl(10,80%,40%))',
                border:'1px solid rgba(0,0,0,0.1)'
              }} />
              <span style={{color:'#EF5350'}}>High</span>
              <span className="ml-2 opacity-60">• Pulsing dots = risk &gt; 5</span>
            </div>
          )}
        </div>
      ) : (
        <div className="mt-3 flex items-center gap-3 text-xs" style={{ color:'#4A6B5A' }}>
          <span style={{ fontWeight:600,color:'#1a3a2a' }}>{drill} District</span>
          <span>·</span>
          <span>{Object.keys(UPAZILA_PATHS[drill]||{}).length} upazilas</span>
          <span>·</span>
          <span style={{ color: (riskMap.get(drill) ?? 0) <= 3 ? '#4CAF50' : (riskMap.get(drill) ?? 0) <= 6 ? '#FF9800' : '#EF5350', fontWeight:600 }}>
            Risk: {(riskMap.get(drill) ?? 0)}
          </span>
        </div>
      )}
    </div>
  );
}
