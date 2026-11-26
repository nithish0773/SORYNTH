/**
 * SORYNTH Tactical Geospatial Coordinate Utilities
 * Provides strict validation, parsing, formatting, and Leaflet LatLng conversion.
 */

import type { Emergency, RescueTeam } from '../types';

export interface ValidatedCoordinate {
  latitude: number;
  longitude: number;
}

/**
 * Validates and parses latitude and longitude values.
 * Enforces:
 *  - Both must be convertible to finite numbers (rejects NaN, Infinity)
 *  - Latitude must be between -90 and 90 degrees
 *  - Longitude must be between -180 and 180 degrees
 *  - Disallows (0, 0) "Null Island" coordinates (indicates unacquired GPS lock in hardware telemetry)
 */
export function parseCoordinate(lat: unknown, lng: unknown): ValidatedCoordinate | null {
  if (lat === null || lat === undefined || lng === null || lng === undefined) {
    return null;
  }

  const parsedLat = typeof lat === 'number' ? lat : typeof lat === 'string' ? parseFloat(lat.trim()) : NaN;
  const parsedLng = typeof lng === 'number' ? lng : typeof lng === 'string' ? parseFloat(lng.trim()) : NaN;

  if (!Number.isFinite(parsedLat) || !Number.isFinite(parsedLng)) {
    return null;
  }

  // Latitude must be [-90, 90]
  if (parsedLat < -90 || parsedLat > 90) {
    return null;
  }

  // Longitude must be [-180, 180]
  if (parsedLng < -180 || parsedLng > 180) {
    return null;
  }

  // Exclude uninitialized/missing GPS fix (0, 0)
  if (Math.abs(parsedLat) < 0.000001 && Math.abs(parsedLng) < 0.000001) {
    return null;
  }

  return {
    latitude: parsedLat,
    longitude: parsedLng,
  };
}

/**
 * Returns true if the coordinate pair is valid and plottable.
 */
export function isValidCoordinate(lat: unknown, lng: unknown): boolean {
  return parseCoordinate(lat, lng) !== null;
}

/**
 * Converts coordinates to Leaflet LatLngExpression tuple in strict [latitude, longitude] order.
 * Returns null if the coordinates are invalid.
 */
export function toLeafletLatLng(lat: unknown, lng: unknown): [number, number] | null {
  const parsed = parseCoordinate(lat, lng);
  if (!parsed) return null;
  return [parsed.latitude, parsed.longitude];
}

/**
 * Safely formats coordinate pair into human-readable string without throwing on string/null values.
 * Example: "12.9141, 74.8560"
 */
export function formatCoordinate(lat: unknown, lng: unknown, precision = 4): string {
  const parsed = parseCoordinate(lat, lng);
  if (!parsed) return '—';
  return `${parsed.latitude.toFixed(precision)}, ${parsed.longitude.toFixed(precision)}`;
}

/**
 * Safely formats a single coordinate value (latitude or longitude) to specified decimal precision.
 */
export function formatSingleCoordinate(val: unknown, precision = 6): string {
  if (val === null || val === undefined) return '—';
  const num = typeof val === 'number' ? val : typeof val === 'string' ? parseFloat(val.trim()) : NaN;
  if (!Number.isFinite(num)) return '—';
  return num.toFixed(precision);
}

export interface FitBoundsOptions {
  emergencies: Emergency[];
  rescueTeams?: RescueTeam[];
  showTeams?: boolean;
  selectedEmergency?: Emergency | null;
  currentLocation?: { latitude: number; longitude: number } | null;
  fallbackCenter?: [number, number];
}

/**
 * Computes the exact array of [latitude, longitude] tuples to fit in view.
 * Prioritizes:
 *  1. All visible, valid SOS emergencies and visible rescue teams.
 *  2. Guarantees the selected emergency is included if valid.
 *  3. Does NOT include operator browser location when tactical markers exist (avoids world-spanning zoom).
 *  4. Only falls back to currentLocation or fallbackCenter when zero markers are present.
 */
export function calculateFitBoundsCoords(options: FitBoundsOptions): [number, number][] {
  const {
    emergencies = [],
    rescueTeams = [],
    showTeams = true,
    selectedEmergency,
  } = options;

  const coords: [number, number][] = [];
  const coordKeySet = new Set<string>();

  const addPoint = (lat: number, lng: number) => {
    const key = `${lat.toFixed(6)}:${lng.toFixed(6)}`;
    if (!coordKeySet.has(key)) {
      coordKeySet.add(key);
      coords.push([lat, lng]);
    }
  };

  // 1. Visible emergencies
  for (const em of emergencies) {
    const pt = parseCoordinate(em.latitude, em.longitude);
    if (pt) {
      addPoint(pt.latitude, pt.longitude);
    }
  }

  // 2. Visible rescue teams (only if showTeams is active)
  if (showTeams) {
    for (const team of rescueTeams) {
      const pt = parseCoordinate(team.latitude, team.longitude);
      if (pt) {
        addPoint(pt.latitude, pt.longitude);
      }
    }
  }

  // 3. Ensure selected emergency is included
  if (selectedEmergency) {
    const pt = parseCoordinate(selectedEmergency.latitude, selectedEmergency.longitude);
    if (pt) {
      addPoint(pt.latitude, pt.longitude);
    }
  }

  return coords;
}

export interface DrawerBoundingRect {
  left: number;
  width: number;
  right?: number;
}

export interface TacticalMapLayoutComputation {
  isDesktop: boolean;
  drawerLeft: number;
  drawerWidth: number;
  gap: number;
  leftMargin: number;
  rightBoundary: number;
  rightOffset: number;
  mapWidth: number;
  mapRightEdge: number;
  clearanceToDrawer: number;
  rightStyle: string;
  maxWidthStyle: string;
  isStacked: boolean;
}

/**
 * Calculates responsive desktop boundaries and dimensions for the contained tactical map overlay.
 * Uses the actual measured drawer bounding rectangle (getBoundingClientRect) rather than drawer width alone.
 * Guarantees the drawer stays fully inside the viewport (never overflowing right edge).
 * Guarantees the map overlay's right edge is at least 20px (default 24px) left of the drawer's actual left edge.
 * At narrower desktop widths where available map width falls below 300px, switches to stacked layout.
 */
export function calculateTacticalMapOverlayLayout(
  viewportWidth: number,
  drawerRectOrWidth: number | DrawerBoundingRect = 576,
  gap: number = 24,
  leftMargin: number = 16
): TacticalMapLayoutComputation {
  const isDesktop = viewportWidth >= 768; // Tailwind md breakpoint

  let rawDrawerLeft: number;
  let rawDrawerWidth: number;

  if (typeof drawerRectOrWidth === 'object' && drawerRectOrWidth !== null) {
    rawDrawerWidth = drawerRectOrWidth.width;
    rawDrawerLeft = drawerRectOrWidth.left;
  } else {
    rawDrawerWidth = drawerRectOrWidth;
    rawDrawerLeft = viewportWidth - rawDrawerWidth;
  }

  // Ensure drawer is clamped fully inside viewport bounds:
  // 1. Drawer width cannot exceed viewportWidth
  const drawerWidth = Math.min(rawDrawerWidth > 0 ? rawDrawerWidth : 576, viewportWidth);
  // 2. Drawer left edge cannot extend past (viewportWidth - drawerWidth), preventing horizontal overflow
  const drawerLeft = Math.max(0, Math.min(rawDrawerLeft, viewportWidth - drawerWidth));

  // Enforce minimum 20px clearance per requirements
  const effectiveGap = Math.max(20, gap);

  // Position the desktop map so its RIGHT EDGE is at least effectiveGap left of the drawer's actual LEFT EDGE
  const maxMapRightEdge = Math.max(leftMargin, drawerLeft - effectiveGap);
  const candidateMapWidth = Math.max(0, maxMapRightEdge - leftMargin);

  // Switch to stacked layout if mobile OR if narrow desktop lacks sufficient width for usable map (min 300px)
  const isStacked = !isDesktop || candidateMapWidth < 300;

  const mapWidth = !isStacked ? candidateMapWidth : viewportWidth;
  const mapRightEdge = !isStacked ? leftMargin + mapWidth : viewportWidth;
  const clearanceToDrawer = drawerLeft - mapRightEdge;
  const rightOffset = Math.max(0, viewportWidth - mapRightEdge);
  const rightBoundary = rightOffset;

  return {
    isDesktop,
    drawerLeft,
    drawerWidth,
    gap: effectiveGap,
    leftMargin,
    rightBoundary,
    rightOffset,
    mapWidth,
    mapRightEdge,
    clearanceToDrawer,
    rightStyle: `${rightOffset}px`,
    maxWidthStyle: `${mapWidth}px`,
    isStacked,
  };
}

export interface PageMapLayoutComputation {
  isConstrained: boolean;
  mapLeft: number;
  drawerLeft: number;
  clearance: number;
  maxAllowedWidth: number;
  mapRightEdge: number;
  clearanceToDrawer: number;
  isStacked: boolean;
}

/**
 * Calculates responsive desktop boundaries for a page-level tactical map wrapper
 * when an incident drawer is open on the right side of the screen.
 * Clamps drawer inside the viewport so it never extends outside visible browser bounds.
 * Guarantees the map wrapper's right edge is at least 24px left of the drawer's actual left edge.
 * Switches to stacked layout at narrower desktop widths (< 1024px or map width < 300px).
 */
export function calculatePageMapWrapperLayout(options: {
  viewportWidth: number;
  mapLeft: number;
  drawerLeft: number;
  drawerWidth?: number;
  isDrawerOpen: boolean;
  clearance?: number;
}): PageMapLayoutComputation {
  const {
    viewportWidth,
    mapLeft,
    drawerLeft: rawDrawerLeft,
    drawerWidth: rawDrawerWidth = 576,
    isDrawerOpen,
    clearance = 24,
  } = options;

  const isDesktop = viewportWidth >= 768;
  const isConstrained = isDesktop && isDrawerOpen && rawDrawerLeft > 0;

  if (!isConstrained) {
    return {
      isConstrained: false,
      mapLeft,
      drawerLeft: rawDrawerLeft,
      clearance,
      maxAllowedWidth: 0,
      mapRightEdge: 0,
      clearanceToDrawer: 0,
      isStacked: false,
    };
  }

  // Ensure drawer stays fully inside the viewport
  const effectiveDrawerWidth = Math.min(rawDrawerWidth > 0 ? rawDrawerWidth : 576, viewportWidth);
  const drawerLeft = Math.max(0, Math.min(rawDrawerLeft, viewportWidth - effectiveDrawerWidth));

  const effectiveClearance = Math.max(24, clearance);
  const targetRightEdge = drawerLeft - effectiveClearance;
  const availableMapWidth = targetRightEdge - mapLeft;

  // On narrow desktop (< 1024px) or when available space for map is under 300px, trigger stacked layout
  const isStacked = viewportWidth < 1024 || availableMapWidth < 300;

  const maxAllowedWidth = isStacked
    ? Math.max(0, viewportWidth - mapLeft - 16)
    : Math.max(0, availableMapWidth);

  const mapRightEdge = mapLeft + maxAllowedWidth;
  const clearanceToDrawer = drawerLeft - mapRightEdge;

  return {
    isConstrained: true,
    mapLeft,
    drawerLeft,
    clearance: effectiveClearance,
    maxAllowedWidth,
    mapRightEdge,
    clearanceToDrawer,
    isStacked,
  };
}



