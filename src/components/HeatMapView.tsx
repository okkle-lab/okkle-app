import { useEffect, useMemo, useRef } from 'react';
import { Platform, StyleSheet, View, Text } from 'react-native';
import MapView, { Circle as MapCircle, Polyline as MapPolyline, type LatLng } from 'react-native-maps';
import Svg, { Circle, Defs, LinearGradient, Polyline, Rect, Stop } from 'react-native-svg';
import { colors, radius, type } from '../theme';
import type { HeatPoint } from '../db';

// Real map + app-owned density overlays. We avoid react-native-maps Heatmap
// because some iOS map-provider builds do not register AIRMapHeatmap.

type Bounds = { minLat: number; maxLat: number; minLng: number; maxLng: number };
type Hotspot = { key: string; latitude: number; longitude: number; t: number; radius: number; color: string };

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function colorFor(t: number): string {
  if (t > 0.78) return '#E2604A';
  if (t > 0.58) return '#E0961F';
  if (t > 0.36) return '#E7C66B';
  if (t > 0.18) return '#5FD0BB';
  return '#9BE3D2';
}

function hexToRgba(hex: string, alpha: number): string {
  const value = hex.replace('#', '');
  const r = parseInt(value.slice(0, 2), 16);
  const g = parseInt(value.slice(2, 4), 16);
  const b = parseInt(value.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

function boundsFor(points: HeatPoint[]): Bounds {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of points) {
    minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
  }
  return { minLat, maxLat, minLng, maxLng };
}

function regionFor(bounds: Bounds) {
  return {
    latitude: (bounds.minLat + bounds.maxLat) / 2,
    longitude: (bounds.minLng + bounds.maxLng) / 2,
    latitudeDelta: Math.max((bounds.maxLat - bounds.minLat) * 1.55, 0.012),
    longitudeDelta: Math.max((bounds.maxLng - bounds.minLng) * 1.55, 0.012),
  };
}

function routeCoordinates(points: HeatPoint[]): LatLng[] {
  const step = Math.max(1, Math.ceil(points.length / 360));
  return points
    .filter((_, i) => i % step === 0)
    .map(p => ({ latitude: p.lat, longitude: p.lng }));
}

function hotspotRadius(bounds: Bounds): number {
  const latMeters = Math.max(400, (bounds.maxLat - bounds.minLat) * 111_000);
  const lngMeters = Math.max(400, (bounds.maxLng - bounds.minLng) * 72_000);
  return clamp(Math.min(latMeters, lngMeters) / 7, 120, 760);
}

function hotspotsFor(points: HeatPoint[], bounds: Bounds): Hotspot[] {
  const spanLat = Math.max(bounds.maxLat - bounds.minLat, 0.002);
  const spanLng = Math.max(bounds.maxLng - bounds.minLng, 0.002);
  const cellLat = Math.max(0.0018, spanLat / 9);
  const cellLng = Math.max(0.0018, spanLng / 9);
  const cells = new Map<string, { lat: number; lng: number; weight: number; count: number }>();

  for (const p of points) {
    const row = Math.floor((p.lat - bounds.minLat) / cellLat);
    const col = Math.floor((p.lng - bounds.minLng) / cellLng);
    const key = `${row}-${col}`;
    const weight = Math.max(0.1, p.w);
    const cell = cells.get(key) ?? { lat: 0, lng: 0, weight: 0, count: 0 };
    cell.lat += p.lat * weight;
    cell.lng += p.lng * weight;
    cell.weight += weight;
    cell.count += 1;
    cells.set(key, cell);
  }

  let maxWeight = 0;
  for (const cell of cells.values()) maxWeight = Math.max(maxWeight, cell.weight);
  const baseRadius = hotspotRadius(bounds);

  return Array.from(cells.entries())
    .map(([key, cell]) => {
      const t = maxWeight > 0 ? cell.weight / maxWeight : 0;
      return {
        key,
        latitude: cell.lat / cell.weight,
        longitude: cell.lng / cell.weight,
        t,
        radius: baseRadius * (0.72 + Math.sqrt(t) * 0.85),
        color: colorFor(t),
      };
    })
    .filter(h => h.t > 0.08)
    .sort((a, b) => b.t - a.t)
    .slice(0, 18);
}

export function HeatMapView({ points, height = 220 }: { points: HeatPoint[]; height?: number }) {
  const valid = points.filter(p => typeof p?.lat === 'number' && typeof p?.lng === 'number');
  const distinct = new Set(valid.map(p => `${p.lat.toFixed(3)},${p.lng.toFixed(3)}`)).size;
  if (valid.length === 0 || distinct < 2) {
    return (
      <View style={[styles.empty, { height }]}>
        <Text style={styles.emptyIcon}>🗺️</Text>
        <Text style={styles.emptyText}>Track a few trips with GPS this week and your hotspots will appear here.</Text>
      </View>
    );
  }

  if (Platform.OS === 'ios') {
    return <AppleHeatMap points={valid} height={height} />;
  }

  return <SvgHeatMap points={valid} height={height} />;
}

function AppleHeatMap({ points, height }: { points: HeatPoint[]; height: number }) {
  const mapRef = useRef<MapView | null>(null);
  const bounds = useMemo(() => boundsFor(points), [points]);
  const region = useMemo(() => regionFor(bounds), [bounds]);
  const route = useMemo(() => routeCoordinates(points), [points]);
  const hotspots = useMemo(() => hotspotsFor(points, bounds), [points, bounds]);

  useEffect(() => {
    if (route.length < 2) return;
    const id = setTimeout(() => {
      mapRef.current?.fitToCoordinates(route, {
        edgePadding: { top: 34, right: 34, bottom: 34, left: 34 },
        animated: false,
      });
    }, 80);
    return () => clearTimeout(id);
  }, [route]);

  return (
    <View style={[styles.mapShell, { height }]}>
      <MapView
        ref={mapRef}
        style={StyleSheet.absoluteFill}
        initialRegion={region}
        mapType="mutedStandard"
        rotateEnabled={false}
        pitchEnabled={false}
        scrollEnabled={false}
        zoomEnabled={false}
        showsCompass={false}
        showsScale={false}
        showsTraffic={false}
        showsUserLocation={false}
      >
        {route.length >= 2 ? (
          <MapPolyline
            coordinates={route}
            strokeColor="rgba(14,142,120,0.38)"
            strokeWidth={5}
            lineCap="round"
            lineJoin="round"
            zIndex={1}
          />
        ) : null}
        {hotspots.map(h => (
          <MapCircle
            key={`${h.key}-outer`}
            center={{ latitude: h.latitude, longitude: h.longitude }}
            radius={h.radius * 1.65}
            fillColor={hexToRgba(h.color, 0.13)}
            strokeColor={hexToRgba(h.color, 0)}
            zIndex={2}
          />
        ))}
        {hotspots.map(h => (
          <MapCircle
            key={`${h.key}-middle`}
            center={{ latitude: h.latitude, longitude: h.longitude }}
            radius={h.radius}
            fillColor={hexToRgba(h.color, 0.24 + h.t * 0.12)}
            strokeColor={hexToRgba(h.color, 0.1)}
            strokeWidth={1}
            zIndex={3}
          />
        ))}
        {hotspots.slice(0, 8).map(h => (
          <MapCircle
            key={`${h.key}-core`}
            center={{ latitude: h.latitude, longitude: h.longitude }}
            radius={h.radius * 0.34}
            fillColor={hexToRgba(h.color, 0.52)}
            strokeColor={hexToRgba('#FFFFFF', 0.55)}
            strokeWidth={1}
            zIndex={4}
          />
        ))}
      </MapView>
    </View>
  );
}

function SvgHeatMap({ points, height }: { points: HeatPoint[]; height: number }) {
  const bounds = boundsFor(points);
  const coords = routeCoordinates(points);
  const x = (lng: number) => 7 + ((lng - bounds.minLng) / (bounds.maxLng - bounds.minLng)) * 86;
  const y = (lat: number) => 7 + ((bounds.maxLat - lat) / (bounds.maxLat - bounds.minLat)) * 48;
  const trail = coords.map(p => `${x(p.longitude).toFixed(1)},${y(p.latitude).toFixed(1)}`).join(' ');
  const hotspots = hotspotsFor(points, bounds).slice(0, 12);

  return (
    <View style={[styles.mapShell, { height }]}>
      <Svg width="100%" height="100%" viewBox="0 0 100 62" preserveAspectRatio="xMidYMid slice">
        <Defs>
          <LinearGradient id="fallbackMapBg" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor="#F9FBFA" />
            <Stop offset="1" stopColor="#E7F0EA" />
          </LinearGradient>
        </Defs>
        <Rect x={0} y={0} width={100} height={62} fill="url(#fallbackMapBg)" />
        <Polyline points={trail} fill="none" stroke="#0E8E78" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" opacity={0.42} />
        {hotspots.map(h => (
          <Circle key={h.key} cx={x(h.longitude)} cy={y(h.latitude)} r={3 + h.t * 7} fill={h.color} opacity={0.24 + h.t * 0.28} />
        ))}
      </Svg>
    </View>
  );
}

const styles = StyleSheet.create({
  mapShell: {
    borderRadius: radius.lg,
    overflow: 'hidden',
    backgroundColor: '#EEF3F1',
  },
  empty: {
    borderRadius: radius.lg,
    backgroundColor: colors.bgSoft,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  emptyIcon: {
    fontSize: 30,
    marginBottom: 8,
  },
  emptyText: {
    ...type.caption,
    textAlign: 'center',
    lineHeight: 19,
  },
});
