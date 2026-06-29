import { useEffect, useMemo, useRef } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import MapView, { Marker, Polyline as MapPolyline, type LatLng } from 'react-native-maps';
import Svg, { Defs, LinearGradient, Stop, Polyline as SvgPolyline, Circle, Rect } from 'react-native-svg';
import { colors, radius, type } from '../theme';

type Pt = { lat: number; lng: number };

// A premium-looking trip route, drawn on-device from the GPS breadcrumb.
// No street map (that needs a native maps SDK / dev build), but it shows the
// shape of the journey with start/finish markers — the architecture is ready
// to swap in Google Maps later.
export function RouteMap({ route, height = 180 }: { route: Pt[]; height?: number }) {
  const pts = (route ?? []).filter(p => typeof p?.lat === 'number' && typeof p?.lng === 'number');
  const distinct = new Set(pts.map(p => `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`)).size;

  if (Platform.OS === 'ios' && pts.length > 0) {
    return <AppleRouteMap route={pts} height={height} needsMoreMovement={distinct < 2} />;
  }

  if (distinct < 2) {
    return (
      <View style={{ height, borderRadius: radius.lg, borderWidth: 1, borderColor: 'rgba(128,128,128,0.25)', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
        <Feather name="navigation" size={26} color={colors.textTertiary} />
        <Text style={[type.caption, { textAlign: 'center' }]}>Move a little to start your route…</Text>
      </View>
    );
  }

  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of pts) {
    minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
  }
  const padLat = (maxLat - minLat) * 0.12 || 0.002;
  const padLng = (maxLng - minLng) * 0.12 || 0.002;
  minLat -= padLat; maxLat += padLat; minLng -= padLng; maxLng += padLng;

  const cosLat = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
  const spanLat = maxLat - minLat;
  const spanLng = (maxLng - minLng) * cosLat || spanLat;
  const W = 100, H = Math.max(50, Math.min(120, (spanLat / spanLng) * 100));

  const x = (lng: number) => ((lng - minLng) / (maxLng - minLng)) * W;
  const y = (lat: number) => ((maxLat - lat) / (maxLat - minLat)) * H;
  const line = pts.map(p => `${x(p.lng).toFixed(2)},${y(p.lat).toFixed(2)}`).join(' ');
  const a = pts[0], b = pts[pts.length - 1];

  return (
    <View style={{ borderRadius: radius.lg, overflow: 'hidden', backgroundColor: '#EEF3F1', height }}>
      <Svg width="100%" height="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
        <Defs>
          <LinearGradient id="route" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0%" stopColor={colors.brandMid} />
            <Stop offset="100%" stopColor={colors.brandDeep} />
          </LinearGradient>
        </Defs>
        <Rect x="0" y="0" width={W} height={H} fill="#EEF3F1" />
        <SvgPolyline points={line} fill="none" stroke="url(#route)" strokeWidth={2.4} strokeLinejoin="round" strokeLinecap="round" />
        {/* start (green) and finish (brand) markers */}
        <Circle cx={x(a.lng)} cy={y(a.lat)} r={3.4} fill="#fff" />
        <Circle cx={x(a.lng)} cy={y(a.lat)} r={2.2} fill={colors.green} />
        <Circle cx={x(b.lng)} cy={y(b.lat)} r={3.6} fill="#fff" />
        <Circle cx={x(b.lng)} cy={y(b.lat)} r={2.4} fill={colors.brandDeep} />
      </Svg>
    </View>
  );
}

function AppleRouteMap({ route, height, needsMoreMovement }: { route: Pt[]; height: number; needsMoreMovement: boolean }) {
  const mapRef = useRef<MapView | null>(null);
  const coordinates = useMemo<LatLng[]>(
    () => route.map(p => ({ latitude: p.lat, longitude: p.lng })),
    [route],
  );
  const region = useMemo(() => {
    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    for (const p of route) {
      minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
      minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
    }
    const latitudeDelta = Math.max((maxLat - minLat) * 1.45, 0.006);
    const longitudeDelta = Math.max((maxLng - minLng) * 1.45, 0.006);
    return {
      latitude: (minLat + maxLat) / 2,
      longitude: (minLng + maxLng) / 2,
      latitudeDelta,
      longitudeDelta,
    };
  }, [route]);

  useEffect(() => {
    if (coordinates.length < 2) return;
    const id = setTimeout(() => {
      mapRef.current?.fitToCoordinates(coordinates, {
        edgePadding: { top: 36, right: 36, bottom: 36, left: 36 },
        animated: false,
      });
    }, 80);
    return () => clearTimeout(id);
  }, [coordinates]);

  const start = coordinates[0];
  const end = coordinates[coordinates.length - 1];

  return (
    <View style={[styles.mapShell, { height }]}>
      <MapView
        ref={mapRef}
        style={StyleSheet.absoluteFill}
        initialRegion={region}
        mapType="standard"
        rotateEnabled={false}
        pitchEnabled={false}
        showsCompass={false}
        showsScale={false}
        showsTraffic={false}
      >
        {coordinates.length >= 2 ? (
          <MapPolyline
            coordinates={coordinates}
            strokeColor={colors.brandDeep}
            strokeWidth={5}
            lineCap="round"
            lineJoin="round"
          />
        ) : null}
        <Marker coordinate={start} anchor={{ x: 0.5, y: 0.5 }}>
          <View style={[styles.markerOuter, styles.markerStart]}>
            <View style={styles.markerInner} />
          </View>
        </Marker>
        {!needsMoreMovement ? (
          <Marker coordinate={end} anchor={{ x: 0.5, y: 0.5 }}>
            <View style={[styles.markerOuter, styles.markerEnd]}>
              <View style={styles.markerInner} />
            </View>
          </Marker>
        ) : null}
      </MapView>
      {needsMoreMovement ? (
        <View style={styles.mapHint}>
          <Feather name="navigation" size={14} color={colors.textSecondary} />
          <Text style={styles.mapHintText}>Move a little to draw your route</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  mapShell: {
    borderRadius: radius.lg,
    overflow: 'hidden',
    backgroundColor: '#EEF3F1',
  },
  mapHint: {
    position: 'absolute',
    left: 10,
    right: 10,
    bottom: 10,
    minHeight: 34,
    borderRadius: radius.full,
    backgroundColor: 'rgba(255,255,255,0.92)',
    borderWidth: 1,
    borderColor: 'rgba(20,30,26,0.08)',
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 7,
  },
  mapHintText: {
    ...type.caption,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  markerOuter: {
    width: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 3,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.22,
    shadowRadius: 5,
    shadowOffset: { width: 0, height: 2 },
  },
  markerStart: {
    backgroundColor: colors.green,
  },
  markerEnd: {
    backgroundColor: colors.brandDeep,
  },
  markerInner: {
    width: 5,
    height: 5,
    borderRadius: 2.5,
    backgroundColor: '#fff',
  },
});
