import React, { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from 'react-leaflet';
import L from 'leaflet';
import { Loader2 } from 'lucide-react';
import { LocationReport } from '../types';

// Fix for default marker icon in react-leaflet
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

// Custom icon for history points
const createHistoryIcon = () => {
  return L.divIcon({
    className: 'history-marker',
    html: '<div style="width: 10px; height: 10px; background-color: #64748b; border-radius: 50%; border: 2px solid white; box-shadow: 0 0 2px rgba(0,0,0,0.4);"></div>',
    iconSize: [10, 10],
    iconAnchor: [5, 5],
  });
};

interface DeviceLocationMapProps {
  locations: LocationReport[];
  lastKnown: LocationReport | null;
  isLoading?: boolean;
}

// Component to handle auto-centering the map when new location arrives
const MapCentering = ({ center }: { center: [number, number] }) => {
  const map = useMap();
  useEffect(() => {
    map.setView(center, map.getZoom());
  }, [center, map]);
  return null;
};

export const DeviceLocationMap: React.FC<DeviceLocationMapProps> = ({ 
  locations, 
  lastKnown, 
  isLoading = false 
}) => {
  const [mapReady, setMapReady] = useState(false);

  // If no location at all
  if (!lastKnown && locations.length === 0 && !isLoading) {
    return (
      <div className="flex flex-col items-center justify-center h-[400px] bg-muted/20 rounded-md border border-dashed">
        <p className="text-muted-foreground">No location data available for this device.</p>
      </div>
    );
  }

  // Determine center point
  const centerPosition: [number, number] = lastKnown 
    ? [lastKnown.latitude, lastKnown.longitude] 
    : locations.length > 0 
      ? [locations[0].latitude, locations[0].longitude]
      : [23.8103, 90.4125]; // Default to Dhaka, Bangladesh

  // Prepare polyline positions (oldest to newest or vice versa doesn't matter for polyline)
  const polylinePositions: [number, number][] = locations.map(loc => [loc.latitude, loc.longitude]);
  
  if (lastKnown) {
    // Add the last known to the beginning to connect the trail
    polylinePositions.unshift([lastKnown.latitude, lastKnown.longitude]);
  }

  return (
    <div className="relative h-[400px] rounded-md overflow-hidden border">
      {isLoading && (
        <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-background/50 backdrop-blur-sm">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      )}
      
      <MapContainer 
        center={centerPosition} 
        zoom={15} 
        style={{ height: '100%', width: '100%', zIndex: 0 }}
        whenReady={() => setMapReady(true)}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        
        {/* Draw the trail */}
        {polylinePositions.length > 1 && (
          <Polyline 
            positions={polylinePositions} 
            color="#3b82f6" 
            weight={3} 
            opacity={0.6}
            dashArray="5, 10" 
          />
        )}

        {/* Draw history points */}
        {locations.map((loc, index) => (
          <Marker 
            key={loc.id || index} 
            position={[loc.latitude, loc.longitude]}
            icon={createHistoryIcon()}
          >
            <Popup>
              <div className="text-sm">
                <p className="font-semibold mb-1">Historical Location</p>
                <p>Accuracy: {Math.round(loc.accuracy)}m</p>
                <p>Time: {new Date(loc.timestamp).toLocaleString()}</p>
                {loc.battery_level && <p>Battery: {loc.battery_level}%</p>}
              </div>
            </Popup>
          </Marker>
        ))}

        {/* Draw current/last known location */}
        {lastKnown && (
          <Marker position={[lastKnown.latitude, lastKnown.longitude]}>
            <Popup>
              <div className="text-sm">
                <p className="font-semibold mb-1">Last Known Location</p>
                <p>Accuracy: {Math.round(lastKnown.accuracy)}m</p>
                <p>Time: {new Date(lastKnown.timestamp).toLocaleString()}</p>
                {lastKnown.battery_level && <p>Battery: {lastKnown.battery_level}%</p>}
              </div>
            </Popup>
          </Marker>
        )}

        {mapReady && <MapCentering center={centerPosition} />}
      </MapContainer>
    </div>
  );
};
