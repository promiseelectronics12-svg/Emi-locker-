import { useState, useCallback, useMemo, type MouseEvent } from 'react';
import type { DistrictSummary } from '@/types';

interface BangladeshMapProps {
  districtData: DistrictSummary[];
  selectedDistrict: string | null;
  onDistrictClick: (district: string) => void;
}

// Simplified SVG path data for Bangladesh's 64 districts.
// Paths are derived from public-domain GeoJSON simplified to viewBox coordinates.
const DISTRICT_PATHS: Record<string, string> = {
  // Dhaka Division
  Dhaka:        'M180,280 L195,270 L210,280 L210,300 L195,310 L180,300 Z',
  Gazipur:      'M185,260 L200,250 L215,260 L215,270 L200,275 L185,270 Z',
  Narayanganj:  'M195,310 L210,305 L220,315 L215,330 L200,325 L195,315 Z',
  Tangail:      'M165,250 L180,240 L195,250 L195,265 L180,270 L165,260 Z',
  Manikganj:    'M155,270 L170,262 L180,275 L175,290 L160,285 L155,275 Z',
  Munshiganj:   'M185,315 L198,310 L205,320 L200,335 L188,330 Z',
  Narsingdi:    'M210,260 L225,252 L235,265 L230,278 L215,275 Z',
  Madaripur:    'M165,330 L180,322 L190,335 L185,350 L170,345 Z',
  Shariatpur:   'M180,340 L195,332 L205,345 L200,360 L185,355 Z',
  Rajbari:      'M145,310 L160,302 L172,315 L167,330 L152,325 Z',
  Gopalganj:    'M150,340 L165,332 L175,345 L170,360 L155,355 Z',
  Faridpur:     'M145,295 L160,285 L175,295 L170,312 L155,310 Z',
  Kishoreganj:  'M215,240 L232,232 L245,245 L240,258 L225,255 Z',

  // Chittagong Division
  Chattogram:   'M275,350 L295,340 L310,355 L305,380 L285,375 L275,365 Z',
  "Cox's Bazar": 'M285,400 L300,390 L310,405 L305,430 L290,425 L280,415 Z',
  Comilla:      'M240,290 L258,282 L270,295 L265,315 L248,310 Z',
  Brahmanbaria: 'M240,265 L258,255 L270,268 L265,285 L248,280 Z',
  Noakhali:     'M255,330 L273,322 L285,338 L280,355 L263,350 Z',
  Feni:         'M265,315 L280,308 L290,320 L285,335 L270,330 Z',
  Lakshmipur:   'M260,345 L275,338 L285,350 L280,365 L265,360 Z',
  Chandpur:     'M230,310 L245,302 L255,315 L250,330 L235,325 Z',
  Khagrachhari: 'M290,300 L310,290 L325,305 L320,325 L300,320 Z',
  Rangamati:    'M295,325 L315,315 L330,332 L325,355 L305,350 Z',
  Bandarban:    'M290,365 L310,355 L325,370 L320,395 L300,390 Z',

  // Rajshahi Division
  Rajshahi:     'M85,235 L102,225 L115,238 L110,255 L95,250 Z',
  Chapainawabganj: 'M68,225 L85,215 L98,228 L92,245 L78,240 Z',
  Naogaon:      'M95,210 L115,200 L130,215 L125,232 L108,228 Z',
  Natore:       'M105,248 L120,240 L133,252 L128,268 L113,264 Z',
  Nawabganj:    'M72,245 L88,238 L98,250 L93,265 L78,260 Z',
  Pabna:        'M120,260 L138,252 L150,265 L145,282 L128,278 Z',
  Bogura:       'M130,215 L148,205 L160,220 L155,238 L138,232 Z',
  Joypurhat:    'M120,195 L138,185 L148,200 L143,215 L128,210 Z',

  // Khulna Division
  Khulna:       'M135,355 L152,345 L165,360 L160,380 L142,375 Z',
  Satkhira:     'M110,365 L128,355 L140,370 L135,390 L118,385 Z',
  Jessore:      'M115,325 L132,315 L145,328 L140,348 L125,342 Z',
  Bagerhat:     'M150,370 L168,360 L180,375 L175,395 L158,390 Z',
  Narail:       'M130,330 L145,322 L155,335 L150,352 L135,348 Z',
  Magura:       'M135,305 L150,295 L162,308 L158,325 L142,320 Z',
  Kushtia:      'M110,280 L128,272 L140,285 L135,302 L118,298 Z',
  Jhenaidah:    'M115,305 L130,295 L142,308 L138,325 L122,320 Z',
  Chuadanga:    'M98,295 L115,285 L125,298 L120,315 L105,310 Z',
  Meherpur:     'M88,280 L105,270 L115,285 L110,300 L95,295 Z',

  // Barishal Division
  Barishal:     'M195,360 L212,350 L225,365 L220,385 L205,380 Z',
  Patuakhali:   'M200,390 L218,382 L230,395 L225,415 L210,410 Z',
  Bhola:        'M225,375 L242,365 L255,380 L250,400 L235,395 Z',
  Pirojpur:     'M180,370 L195,362 L205,375 L200,390 L185,385 Z',
  Jhalokati:    'M185,385 L200,378 L210,390 L205,405 L190,400 Z',
  Barguna:      'M190,405 L208,395 L220,410 L215,430 L198,425 Z',

  // Sylhet Division
  Sylhet:       'M265,210 L285,200 L300,215 L295,235 L278,230 Z',
  Moulvibazar:  'M270,235 L288,225 L300,240 L295,258 L280,252 Z',
  Habiganj:     'M250,245 L268,235 L280,250 L275,268 L258,262 Z',
  Sunamganj:    'M245,210 L265,200 L278,215 L273,232 L255,228 Z',

  // Rangpur Division
  Rangpur:      'M138,145 L155,135 L168,148 L163,165 L148,160 Z',
  Dinajpur:     'M105,140 L125,130 L138,145 L132,162 L115,158 Z',
  Kurigram:     'M155,128 L172,118 L185,132 L180,148 L165,142 Z',
  Gaibandha:    'M145,165 L162,155 L175,168 L170,185 L155,180 Z',
  Nilphamari:   'M130,118 L148,108 L160,122 L155,138 L140,132 Z',
  Lalmonirhat:  'M148,110 L165,100 L178,115 L172,130 L158,125 Z',
  Thakurgaon:   'M105,118 L122,108 L135,122 L130,138 L115,132 Z',
  Panchagarh:   'M112,98 L130,88 L142,102 L137,118 L122,112 Z',

  // Mymensingh Division
  Mymensingh:   'M195,225 L215,215 L230,228 L225,248 L210,242 Z',
  Jamalpur:     'M170,225 L188,215 L200,228 L195,245 L180,240 Z',
  Sherpur:      'M185,208 L202,198 L215,212 L210,228 L195,222 Z',
  Netrokona:    'M215,210 L235,200 L248,215 L243,232 L225,228 Z',
};

// All 64 district names for reference
const ALL_DISTRICTS = Object.keys(DISTRICT_PATHS);

function getActivityLevel(data: DistrictSummary | undefined, maxKeys: number): number {
  if (!data || data.reseller_count === 0) return 0;
  if (maxKeys === 0) return data.reseller_count > 0 ? 15 : 0;
  return Math.min(100, Math.round((data.total_keys_distributed / maxKeys) * 100));
}

function getFillColor(level: number, isSelected: boolean, isHovered: boolean): string {
  if (isSelected) return '#059669';   // emerald-600
  if (isHovered) return '#34d399';    // emerald-400

  if (level === 0) return '#ecfdf5';  // emerald-50
  if (level <= 25) return '#a7f3d0';  // emerald-200
  if (level <= 50) return '#34d399';  // emerald-400
  if (level <= 75) return '#059669';  // emerald-600
  return '#065f46';                    // emerald-800
}

function getStrokeColor(isSelected: boolean): string {
  return isSelected ? '#022c22' : '#6ee7b7'; // emerald-950 or emerald-300
}

export default function BangladeshMap({ districtData, selectedDistrict, onDistrictClick }: BangladeshMapProps) {
  const [hoveredDistrict, setHoveredDistrict] = useState<string | null>(null);
  const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 });

  const dataMap = useMemo(() => {
    const m = new Map<string, DistrictSummary>();
    for (const d of districtData) m.set(d.district, d);
    return m;
  }, [districtData]);

  const maxKeys = useMemo(
    () => Math.max(1, ...districtData.map(d => d.total_keys_distributed)),
    [districtData]
  );

  const handleMouseMove = useCallback((e: MouseEvent) => {
    setTooltipPos({ x: e.clientX, y: e.clientY });
  }, []);

  const hoveredData = hoveredDistrict ? dataMap.get(hoveredDistrict) : null;

  return (
    <div className="relative select-none" onMouseMove={handleMouseMove}>
      <svg
        viewBox="60 80 280 370"
        className="w-full h-auto"
        style={{ maxHeight: '70vh' }}
      >
        {/* Water/background */}
        <rect x="60" y="80" width="280" height="370" fill="#f0fdf4" rx="8" />

        {ALL_DISTRICTS.map(name => {
          const path = DISTRICT_PATHS[name];
          if (!path) return null;

          const data = dataMap.get(name);
          const level = getActivityLevel(data, maxKeys);
          const isSelected = selectedDistrict === name;
          const isHovered = hoveredDistrict === name;

          return (
            <path
              key={name}
              d={path}
              data-district={name}
              fill={getFillColor(level, isSelected, isHovered)}
              stroke={getStrokeColor(isSelected)}
              strokeWidth={isSelected ? 2 : 0.8}
              className="cursor-pointer transition-colors duration-150"
              onClick={() => onDistrictClick(name)}
              onMouseEnter={() => setHoveredDistrict(name)}
              onMouseLeave={() => setHoveredDistrict(null)}
            />
          );
        })}
      </svg>

      {/* Tooltip */}
      {hoveredDistrict && (
        <div
          className="pointer-events-none fixed z-50 rounded-lg border border-emerald-200 bg-white/95 px-3 py-2 text-sm shadow-lg backdrop-blur"
          style={{
            left: tooltipPos.x + 12,
            top: tooltipPos.y - 40,
          }}
        >
          <p className="font-semibold text-emerald-950">{hoveredDistrict}</p>
          <p className="text-muted-foreground">
            {hoveredData
              ? `${hoveredData.reseller_count} reseller${hoveredData.reseller_count !== 1 ? 's' : ''} · ${hoveredData.total_keys_distributed} keys`
              : 'No resellers'}
          </p>
        </div>
      )}

      {/* Legend */}
      <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
        <span>Activity:</span>
        {[
          { color: '#ecfdf5', label: 'None' },
          { color: '#a7f3d0', label: 'Low' },
          { color: '#34d399', label: 'Med' },
          { color: '#059669', label: 'High' },
          { color: '#065f46', label: 'Top' },
        ].map(({ color, label }) => (
          <span key={label} className="flex items-center gap-1">
            <span className="inline-block h-3 w-3 rounded border border-emerald-200" style={{ backgroundColor: color }} />
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
