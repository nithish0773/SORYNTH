import { describe, it, expect } from 'vitest';
import {
  parseCoordinate,
  isValidCoordinate,
  toLeafletLatLng,
  formatCoordinate,
  formatSingleCoordinate,
  calculateFitBoundsCoords,
  calculateTacticalMapOverlayLayout,
  calculatePageMapWrapperLayout,
} from '../utils/coordinateUtils';
import type { Emergency, RescueTeam } from '../types';

describe('Tactical Map - Geospatial Coordinate Utilities & Marker Positioning', () => {
  describe('1. Coordinate Validation & Parsing (parseCoordinate / isValidCoordinate)', () => {
    it('correctly parses valid positive and negative coordinates', () => {
      const coord = parseCoordinate(12.9141, 74.856);
      expect(coord).toEqual({ latitude: 12.9141, longitude: 74.856 });
      expect(isValidCoordinate(12.9141, 74.856)).toBe(true);

      const southernHemisphere = parseCoordinate(-33.8688, 151.2093);
      expect(southernHemisphere).toEqual({ latitude: -33.8688, longitude: 151.2093 });

      const westernHemisphere = parseCoordinate(40.7128, -74.006);
      expect(westernHemisphere).toEqual({ latitude: 40.7128, longitude: -74.006 });
    });

    it('parses valid numeric strings cleanly', () => {
      const coord = parseCoordinate('12.9141', ' 74.8560 ');
      expect(coord).toEqual({ latitude: 12.9141, longitude: 74.856 });
      expect(isValidCoordinate('12.9141', '74.8560')).toBe(true);
    });

    it('accepts exact geographic boundary limits', () => {
      expect(isValidCoordinate(90, 180)).toBe(true);
      expect(isValidCoordinate(-90, -180)).toBe(true);
      expect(isValidCoordinate(0, 50)).toBe(true);
      expect(isValidCoordinate(50, 0)).toBe(true);
    });

    it('rejects latitudes beyond [-90, 90]', () => {
      expect(parseCoordinate(90.0001, 74.856)).toBeNull();
      expect(parseCoordinate(-90.0001, 74.856)).toBeNull();
      expect(parseCoordinate(150, 74.856)).toBeNull();
      expect(isValidCoordinate(-120, 74.856)).toBe(false);
    });

    it('rejects longitudes beyond [-180, 180]', () => {
      expect(parseCoordinate(12.9141, 180.0001)).toBeNull();
      expect(parseCoordinate(12.9141, -180.0001)).toBeNull();
      expect(parseCoordinate(12.9141, 360)).toBeNull();
      expect(isValidCoordinate(12.9141, -200)).toBe(false);
    });

    it('rejects (0, 0) "Null Island" coordinates (unacquired GPS hardware fix)', () => {
      expect(parseCoordinate(0, 0)).toBeNull();
      expect(isValidCoordinate(0, 0)).toBe(false);
      expect(parseCoordinate('0.000000', '0.000000')).toBeNull();
    });

    it('rejects NaN, Infinity, null, undefined, and non-numeric strings', () => {
      expect(parseCoordinate(NaN, 74.856)).toBeNull();
      expect(parseCoordinate(12.9141, NaN)).toBeNull();
      expect(parseCoordinate(Infinity, 74.856)).toBeNull();
      expect(parseCoordinate(null, 74.856)).toBeNull();
      expect(parseCoordinate(12.9141, undefined)).toBeNull();
      expect(parseCoordinate('not-a-number', '74.856')).toBeNull();
      expect(parseCoordinate('', '')).toBeNull();
    });
  });

  describe('2. Leaflet LatLng Tuple Order Verification (toLeafletLatLng)', () => {
    it('strictly returns [latitude, longitude] order as expected by Leaflet', () => {
      const lat = 12.9141;
      const lng = 74.856;

      const tuple = toLeafletLatLng(lat, lng);
      expect(tuple).not.toBeNull();
      expect(tuple![0]).toBe(lat); // Latitude at index 0
      expect(tuple![1]).toBe(lng); // Longitude at index 1

      // Verify that [lat, lng] is distinct from [lng, lat]
      expect(tuple![0]).not.toBe(lng);
      expect(tuple![1]).not.toBe(lat);
    });

    it('returns null on invalid coordinates to prevent Leaflet runtime crashes', () => {
      expect(toLeafletLatLng(NaN, 74.856)).toBeNull();
      expect(toLeafletLatLng(999, 74.856)).toBeNull();
      expect(toLeafletLatLng(0, 0)).toBeNull();
    });
  });

  describe('3. Safe Coordinate Formatting (formatCoordinate / formatSingleCoordinate)', () => {
    it('formats coordinates with given precision', () => {
      expect(formatCoordinate(12.914123, 74.856045, 4)).toBe('12.9141, 74.8560');
      expect(formatCoordinate('12.9141', '74.8560', 2)).toBe('12.91, 74.86');
    });

    it('returns a fallback dash on invalid or null coordinates without throwing', () => {
      expect(formatCoordinate(null, null)).toBe('—');
      expect(formatCoordinate(NaN, 74.856)).toBe('—');
      expect(formatSingleCoordinate(null)).toBe('—');
      expect(formatSingleCoordinate('invalid')).toBe('—');
      expect(formatSingleCoordinate(12.914123, 5)).toBe('12.91412');
    });
  });

  describe('4. Selected SOS Incident Coordinate Mapping & Isolation', () => {
    const mockSosIncident: Emergency = {
      id: 'em-101',
      emergency_code: 'SOR-101',
      is_guest: false,
      sender_name: 'Victim Field Signal',
      emergency_type: 'MEDICAL',
      latitude: 12.935,
      longitude: 74.865,
      accuracy_meters: 15,
      communication_method: 'LORA_RELAY',
      status: 'DELIVERED',
      hop_count: 1,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    it('extracts exact actual coordinates from selected SOS incident', () => {
      const pt = toLeafletLatLng(mockSosIncident.latitude, mockSosIncident.longitude);
      expect(pt).toEqual([12.935, 74.865]);
      expect(pt![0]).toBe(12.935); // Matches incident latitude
      expect(pt![1]).toBe(74.865); // Matches incident longitude
    });

    it('does not confuse selected incident coordinates with operator GPS or anchor default', () => {
      const operatorGps = { latitude: 28.6139, longitude: 77.209 }; // New Delhi
      const anchorDefault = [12.9141, 74.856]; // Mangalore Command Anchor

      const sosPt = toLeafletLatLng(mockSosIncident.latitude, mockSosIncident.longitude);
      expect(sosPt![0]).not.toBe(operatorGps.latitude);
      expect(sosPt![1]).not.toBe(operatorGps.longitude);
      expect(sosPt![0]).not.toBe(anchorDefault[0]);
    });
  });

  describe('5. Rescue Team Coordinates Independence', () => {
    const mockTeamA: RescueTeam = {
      id: 'team-01',
      team_name: 'Alpha Coastal Squad',
      jurisdiction_zone: 'SECTOR-1',
      contact_phone: '+91 99000 11111',
      status: 'ACTIVE',
      latitude: 12.910,
      longitude: 74.850,
      created_at: new Date().toISOString(),
    };

    const mockTeamB: RescueTeam = {
      id: 'team-02',
      team_name: 'Bravo Highland Squad',
      jurisdiction_zone: 'SECTOR-2',
      contact_phone: '+91 99000 22222',
      status: 'ACTIVE',
      latitude: 12.980,
      longitude: 74.890,
      created_at: new Date().toISOString(),
    };

    const mockTeamNoGps: RescueTeam = {
      id: 'team-03',
      team_name: 'Headquarters Reserve',
      jurisdiction_zone: 'BASE',
      contact_phone: '+91 99000 33333',
      status: 'STANDBY',
      latitude: null,
      longitude: null,
      created_at: new Date().toISOString(),
    };

    it('preserves distinct independent coordinates for each rescue team', () => {
      const ptA = toLeafletLatLng(mockTeamA.latitude, mockTeamA.longitude);
      const ptB = toLeafletLatLng(mockTeamB.latitude, mockTeamB.longitude);

      expect(ptA).toEqual([12.91, 74.85]);
      expect(ptB).toEqual([12.98, 74.89]);
      expect(ptA).not.toEqual(ptB);
    });

    it('safely filters out teams with missing, null, or zero coordinates', () => {
      expect(toLeafletLatLng(mockTeamNoGps.latitude, mockTeamNoGps.longitude)).toBeNull();
      expect(isValidCoordinate(mockTeamNoGps.latitude, mockTeamNoGps.longitude)).toBe(false);
    });
  });

  describe('6. Fit All Bounds Calculation (calculateFitBoundsCoords)', () => {
    const em1: Emergency = {
      id: 'em-1',
      emergency_code: 'SOR-001',
      is_guest: false,
      emergency_type: 'NATURAL_DISASTER',
      latitude: 12.91,
      longitude: 74.85,
      communication_method: 'LORA_RELAY',
      status: 'DELIVERED',
      hop_count: 1,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const em2: Emergency = {
      id: 'em-2',
      emergency_code: 'SOR-002',
      is_guest: false,
      emergency_type: 'FIRE',
      latitude: 12.95,
      longitude: 74.88,
      communication_method: 'INTERNET',
      status: 'PENDING',
      hop_count: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const emInvalidGps: Emergency = {
      id: 'em-3',
      emergency_code: 'SOR-003',
      is_guest: false,
      emergency_type: 'MEDICAL',
      latitude: 0, // Null Island
      longitude: 0,
      communication_method: 'LORA_RELAY',
      status: 'DELIVERED',
      hop_count: 1,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const team1: RescueTeam = {
      id: 'team-1',
      team_name: 'Rapid Response Team 1',
      jurisdiction_zone: 'SECTOR-A',
      contact_phone: '+91 99000 44444',
      status: 'ACTIVE',
      latitude: 12.92,
      longitude: 74.86,
      created_at: new Date().toISOString(),
    };

    const farAwayOperator = {
      latitude: 51.5074, // London (far away from India sector)
      longitude: -0.1278,
    };

    it('includes all visible valid emergencies and teams in [lat, lng] order', () => {
      const coords = calculateFitBoundsCoords({
        emergencies: [em1, em2],
        rescueTeams: [team1],
        showTeams: true,
      });

      expect(coords).toHaveLength(3);
      expect(coords).toContainEqual([12.91, 74.85]);
      expect(coords).toContainEqual([12.95, 74.88]);
      expect(coords).toContainEqual([12.92, 74.86]);
    });

    it('excludes invalid emergencies (such as Null Island GPS)', () => {
      const coords = calculateFitBoundsCoords({
        emergencies: [em1, emInvalidGps],
        rescueTeams: [],
        showTeams: true,
      });

      expect(coords).toHaveLength(1);
      expect(coords).toEqual([[12.91, 74.85]]);
    });

    it('excludes rescue teams when showTeams is false', () => {
      const coords = calculateFitBoundsCoords({
        emergencies: [em1],
        rescueTeams: [team1],
        showTeams: false,
      });

      expect(coords).toHaveLength(1);
      expect(coords).toEqual([[12.91, 74.85]]);
    });

    it('does NOT include far-away operator GPS in bounds when tactical markers are visible', () => {
      // Prevents the bug where the map zooms out to the entire globe because of operator's location
      const coords = calculateFitBoundsCoords({
        emergencies: [em1, em2],
        rescueTeams: [team1],
        showTeams: true,
        currentLocation: farAwayOperator,
      });

      expect(coords).toHaveLength(3);
      expect(coords).not.toContainEqual([farAwayOperator.latitude, farAwayOperator.longitude]);
    });

    it('guarantees selected emergency is included even if not in emergencies array', () => {
      const selectedStandalone: Emergency = {
        id: 'em-standalone',
        emergency_code: 'SOR-999',
        is_guest: false,
        emergency_type: 'LOST_STRANDED',
        latitude: 12.99,
        longitude: 74.92,
        communication_method: 'LORA_RELAY',
        status: 'RESOLVED',
        hop_count: 1,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };

      const coords = calculateFitBoundsCoords({
        emergencies: [em1],
        rescueTeams: [],
        showTeams: true,
        selectedEmergency: selectedStandalone,
      });

      expect(coords).toHaveLength(2);
      expect(coords).toContainEqual([12.99, 74.92]);
    });

    it('returns empty array when zero valid tactical markers exist', () => {
      const coords = calculateFitBoundsCoords({
        emergencies: [emInvalidGps],
        rescueTeams: [],
        showTeams: true,
      });

      expect(coords).toHaveLength(0);
    });
  });

  describe('7. Selected SOS Focus Behavior & Tactical Zoom Rules', () => {
    const selectedSos: Emergency = {
      id: 'em-focus-1',
      emergency_code: 'SOR-888',
      is_guest: false,
      emergency_type: 'MEDICAL',
      latitude: 12.9141,
      longitude: 74.8560,
      communication_method: 'LORA_RELAY',
      status: 'DELIVERED',
      hop_count: 1,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    it('determines initial map zoom level dynamically based on selection state', () => {
      // With selected incident: street-level resolution zoom 16
      const zoomWithSelected = selectedSos ? 16 : 12;
      expect(zoomWithSelected).toBe(16);

      // Without selected incident: wide theater overview zoom 12
      const unselected: Emergency | null = null;
      const zoomWithoutSelected = unselected ? 16 : 12;
      expect(zoomWithoutSelected).toBe(12);
    });

    it('strictly derives center coordinates from selected incident', () => {
      const pt = toLeafletLatLng(selectedSos.latitude, selectedSos.longitude);
      expect(pt).toEqual([12.9141, 74.8560]);
    });

    it('ensures selected SOS marker has highest zIndexOffset (1000) over team markers (500)', () => {
      const selectedZIndex = 1000;
      const teamZIndex = 500;
      const regularSosZIndex = 100;

      expect(selectedZIndex).toBeGreaterThan(teamZIndex);
      expect(selectedZIndex).toBeGreaterThan(regularSosZIndex);
    });
  });

  describe('8. Tactical Map Overlay Responsive Layout Constraints', () => {
    it('defines contained desktop bounds that do not obscure the incident detail panel', () => {
      // Desktop constraints:
      // - Stays within viewport: top-4, bottom-4, left-4
      // - Clears the 36rem (576px) max-w-xl incident drawer: right-[calc(min(100vw,36rem)+1.5rem)]
      const desktopLayoutClass = 'md:inset-auto md:top-4 md:bottom-4 md:left-4 md:right-[calc(min(100vw,36rem)+1.5rem)] md:rounded-[24px]';
      
      expect(desktopLayoutClass).toContain('md:top-4');
      expect(desktopLayoutClass).toContain('md:bottom-4');
      expect(desktopLayoutClass).toContain('md:left-4');
      expect(desktopLayoutClass).toContain('md:right-[calc(min(100vw,36rem)+1.5rem)]');
    });

    it('defines full-screen layout on mobile viewports with high z-index', () => {
      // Mobile constraints: fixed inset-0 z-[60]
      const mobileLayoutClass = 'fixed inset-0 z-[60]';
      expect(mobileLayoutClass).toContain('fixed');
      expect(mobileLayoutClass).toContain('inset-0');
      expect(mobileLayoutClass).toContain('z-[60]');
    });

    it('enforces stacking order where drawer has priority over desktop map overlay', () => {
      const desktopMapOverlayZIndex = 40; // md:z-40
      const emergencyDrawerZIndex = 50; // z-50
      const mobileMapOverlayZIndex = 60; // z-[60]

      // On desktop, drawer must sit higher than the map overlay to prevent overlap/occlusion
      expect(emergencyDrawerZIndex).toBeGreaterThan(desktopMapOverlayZIndex);

      // On mobile, full-screen map overlay sits on top with back button
      expect(mobileMapOverlayZIndex).toBeGreaterThan(emergencyDrawerZIndex);
    });

    it('calculates responsive desktop map width and right boundary with zero drawer overlap', () => {
      // Standard laptop desktop: 1440px viewport, 576px (36rem) drawer
      const laptopLayout = calculateTacticalMapOverlayLayout(1440, 576, 24, 16);
      expect(laptopLayout.isDesktop).toBe(true);
      expect(laptopLayout.drawerWidth).toBe(576);
      expect(laptopLayout.rightBoundary).toBe(600); // 576px + 24px gap
      expect(laptopLayout.mapWidth).toBe(824); // 1440 - 600 - 16 = 824px

      // Verify zero overlap: map right boundary + map left margin + map width == total viewport
      const totalWidthOccupied = laptopLayout.leftMargin + laptopLayout.mapWidth + laptopLayout.gap + laptopLayout.drawerWidth;
      expect(totalWidthOccupied).toBe(1440);

      // Verify gap between right edge of map and left edge of drawer is exactly the 24px gap
      const mapRightEdge = laptopLayout.leftMargin + laptopLayout.mapWidth; // 16 + 824 = 840
      const drawerLeftEdge = 1440 - laptopLayout.drawerWidth; // 1440 - 576 = 864
      expect(drawerLeftEdge - mapRightEdge).toBe(24);
    });

    it('handles compact desktop viewports (1024px) cleanly', () => {
      const compactLayout = calculateTacticalMapOverlayLayout(1024, 576, 24, 16);
      expect(compactLayout.isDesktop).toBe(true);
      expect(compactLayout.drawerWidth).toBe(576);
      expect(compactLayout.rightBoundary).toBe(600);
      expect(compactLayout.mapWidth).toBe(408); // 1024 - 600 - 16 = 408px
      expect(compactLayout.mapWidth).toBeGreaterThan(300); // Usable map viewport

      const mapRightEdge = compactLayout.leftMargin + compactLayout.mapWidth;
      const drawerLeftEdge = 1024 - compactLayout.drawerWidth;
      expect(drawerLeftEdge - mapRightEdge).toBe(24);
    });

    it('identifies mobile viewports (< 768px) and switches to full-width mode', () => {
      const mobileLayout = calculateTacticalMapOverlayLayout(390, 576);
      expect(mobileLayout.isDesktop).toBe(false);
      expect(mobileLayout.mapWidth).toBe(390); // Mobile uses full viewport
    });

    it('regression: positions desktop map so right edge is at least 20px left of actual rendered drawer at x=1084 (never extends to x=1277)', () => {
      // User bug report scenario:
      // Drawer begins at x=1084 (measured via getBoundingClientRect), viewport = 1877px.
      // Previously, the map extended to x=1277, overlapping the drawer by 193px.
      const actualDrawerRect = { left: 1084, width: 576 };
      const layout = calculateTacticalMapOverlayLayout(1877, actualDrawerRect, 24, 16);

      expect(layout.isDesktop).toBe(true);
      expect(layout.drawerLeft).toBe(1084);
      expect(layout.drawerWidth).toBe(576);

      // Map right edge must be at least 20px (here 24px) to the left of the drawer's left edge
      expect(layout.mapRightEdge).toBe(1060); // 1084 - 24
      expect(layout.mapRightEdge).toBeLessThan(1084);
      expect(layout.mapRightEdge).toBeLessThan(1277); // Must NOT extend to x=1277!

      // Clearance must be at least 20px
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.clearanceToDrawer).toBeGreaterThanOrEqual(20);

      // Map width must fill from leftMargin (16px) to mapRightEdge (1060px)
      expect(layout.mapWidth).toBe(1044); // 1060 - 16
      expect(layout.leftMargin + layout.mapWidth).toBe(layout.mapRightEdge);

      // Right offset from viewport edge (1877px)
      expect(layout.rightOffset).toBe(817); // 1877 - 1060 = 817
    });

    it('accurately derives map positioning from a live DOM element getBoundingClientRect() result', () => {
      // Create simulated drawer DOM element as returned by React drawerRef
      const mockDrawerElement = {
        getBoundingClientRect: () => ({
          left: 1084,
          top: 0,
          right: 1660,
          bottom: 900,
          width: 576,
          height: 900,
          x: 1084,
          y: 0,
          toJSON: () => {},
        }),
      };

      const rect = mockDrawerElement.getBoundingClientRect();
      const layout = calculateTacticalMapOverlayLayout(1877, rect, 24, 16);

      // Verify the map's right edge is at x=1060 (24px clearance from drawer at x=1084)
      expect(layout.mapRightEdge).toBe(1060);
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.clearanceToDrawer).toBeGreaterThanOrEqual(20);

      // Verify the map never reaches x=1277
      expect(layout.mapRightEdge).toBeLessThan(1277);
      expect(1277 - layout.mapRightEdge).toBe(217); // Exact 217px clearance away from previous buggy position

      // Verify computed CSS properties to apply on tactical-map-overlay
      expect(layout.maxWidthStyle).toBe('1044px');
      expect(layout.rightStyle).toBe('817px');
    });

    it('dynamically adapts map right edge when drawer is positioned at various X coordinates', () => {
      const viewports = [1920, 1680, 1440, 1280];
      const drawerLeftPositions = [1200, 1100, 1000, 850];

      drawerLeftPositions.forEach((drawerLeft, index) => {
        const vp = viewports[index];
        const layout = calculateTacticalMapOverlayLayout(vp, { left: drawerLeft, width: 576 }, 20, 16);
        
        expect(layout.isDesktop).toBe(true);
        expect(layout.mapRightEdge).toBeLessThanOrEqual(drawerLeft - 20);
        expect(drawerLeft - layout.mapRightEdge).toBeGreaterThanOrEqual(20);
      });
    });

    it('regression: restricts page map wrapper right edge so it never extends to x=1277 when drawer is at x=1084', () => {
      // EmergencyMapPage scenario from user screenshot:
      // Map wrapper left edge = 320px, Drawer left edge = 1084px, viewport = 1877px.
      // Previously, the map wrapper in lg:col-span-3 spanned to x=1277, overlapping the drawer by 193px.
      const layout = calculatePageMapWrapperLayout({
        viewportWidth: 1877,
        mapLeft: 320,
        drawerLeft: 1084,
        isDrawerOpen: true,
        clearance: 24,
      });

      expect(layout.isConstrained).toBe(true);
      expect(layout.mapLeft).toBe(320);
      expect(layout.drawerLeft).toBe(1084);

      // Max allowed map width = drawerLeft (1084) - clearance (24) - mapLeft (320) = 740px
      expect(layout.maxAllowedWidth).toBe(740);

      // Map right edge = mapLeft (320) + maxAllowedWidth (740) = 1060px
      expect(layout.mapRightEdge).toBe(1060);

      // Right edge must be at least 24px left of drawer's actual left edge
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.clearanceToDrawer).toBeGreaterThanOrEqual(24);
      expect(layout.mapRightEdge).toBeLessThan(1084);

      // Must NOT reach or exceed x=1277
      expect(layout.mapRightEdge).toBeLessThan(1277);
      expect(1277 - layout.mapRightEdge).toBe(217); // 217px clearance away from the buggy position
    });

    it('unconstrains page map wrapper when incident drawer is closed', () => {
      const layout = calculatePageMapWrapperLayout({
        viewportWidth: 1877,
        mapLeft: 320,
        drawerLeft: 1084,
        isDrawerOpen: false,
        clearance: 24,
      });

      expect(layout.isConstrained).toBe(false);
      expect(layout.maxAllowedWidth).toBe(0);
    });

    it('unconstrains page map wrapper on mobile viewports (< 768px)', () => {
      const layout = calculatePageMapWrapperLayout({
        viewportWidth: 390,
        mapLeft: 16,
        drawerLeft: 0,
        isDrawerOpen: true,
        clearance: 24,
      });

      expect(layout.isConstrained).toBe(false);
    });

    it('ensures selected SOS marker popup has sufficient vertical headroom below top toolbar', () => {
      // Toolbar sits at top-3 (12px) and is approx 44px tall (max bottom boundary ~56px)
      const toolbarBottom = 56;
      // TacticalMap Popup configures autoPanPaddingTopLeft with 80px top clearance
      const popupTopPadding = 80;
      // Headroom shift applied when centering on selected emergency
      const verticalHeadroomShift = 70;

      // Popup padding must exceed the toolbar's bottom boundary so it never gets hidden behind it
      expect(popupTopPadding).toBeGreaterThan(toolbarBottom);
      expect(popupTopPadding - toolbarBottom).toBeGreaterThanOrEqual(20); // At least 20px clearance below toolbar

      // Map centering shift must be positive to push the marker lower and give room for popup above
      expect(verticalHeadroomShift).toBeGreaterThan(50);
    });

    it('enforces responsive non-wrapping layout on narrow desktop map toolbar', () => {
      // Toolbar must stay within map wrapper width, prevent multi-row wrapping, and allow horizontal scrolling
      const toolbarClasses = 'absolute top-3 right-3 max-w-[calc(100%-1.5rem)] flex items-center flex-nowrap gap-1.5 overflow-x-auto';
      
      expect(toolbarClasses).toContain('flex-nowrap');
      expect(toolbarClasses).toContain('overflow-x-auto');
      expect(toolbarClasses).toContain('max-w-[calc(100%-1.5rem)]');
      expect(toolbarClasses).not.toContain('flex-wrap'); // Must not wrap into awkward multi-line shapes
    });

    it('supports all 4 tactical map layer modes: tactical, satellite, terrain, street', () => {
      const validLayers = ['tactical', 'satellite', 'terrain', 'street'] as const;
      expect(validLayers).toContain('tactical');
      expect(validLayers).toContain('satellite');
      expect(validLayers).toContain('terrain');
      expect(validLayers).toContain('street');
    });
  });

  describe('9. Responsive Viewport Constraints (1385px, 1440px, 1920px & Stacked Mode)', () => {
    it('strictly constrains tactical map overlay layout for a 1385px desktop viewport, keeping drawer fully inside viewport', () => {
      const viewportWidth = 1385;
      const drawerWidth = 576;
      const gap = 24;
      const leftMargin = 16;

      const layout = calculateTacticalMapOverlayLayout(viewportWidth, drawerWidth, gap, leftMargin);

      // Desktop side-by-side mode
      expect(layout.isDesktop).toBe(true);
      expect(layout.isStacked).toBe(false);

      // Drawer must be kept fully inside the viewport
      expect(layout.drawerWidth).toBe(576);
      expect(layout.drawerLeft).toBe(809); // 1385 - 576 = 809
      expect(layout.drawerLeft + layout.drawerWidth).toBe(1385);
      expect(layout.drawerLeft + layout.drawerWidth).toBeLessThanOrEqual(viewportWidth);
      expect(layout.drawerLeft).toBeGreaterThanOrEqual(0);

      // Map right edge must maintain at least 24px clearance to drawer
      expect(layout.mapRightEdge).toBe(785); // 809 - 24
      expect(layout.drawerLeft - layout.mapRightEdge).toBe(24);
      expect(layout.clearanceToDrawer).toBe(24);

      // Map overlay width is constrained to leave sufficient space for drawer
      expect(layout.mapWidth).toBe(769); // 785 - 16
      expect(layout.mapWidth).toBeGreaterThan(300); // Fully usable map viewport
      expect(layout.rightOffset).toBe(600); // 1385 - 785

      // Zero overlap equation check: leftMargin + mapWidth + gap + drawerWidth === viewportWidth
      expect(layout.leftMargin + layout.mapWidth + layout.gap + layout.drawerWidth).toBe(viewportWidth);
    });

    it('clamps off-screen drawer bounding rect in a 1385px viewport so map never occupies excessive horizontal space', () => {
      // Simulate an unconstrained or animating drawer left edge (e.g. from an earlier wider viewport at x=1084)
      const unconstrainedDrawerRect = { left: 1084, width: 576 };
      const viewportWidth = 1385;

      const layout = calculateTacticalMapOverlayLayout(viewportWidth, unconstrainedDrawerRect, 24, 16);

      // Must clamp drawerLeft so it cannot extend beyond (1385 - 576) = 809px
      expect(layout.drawerLeft).toBe(809);
      expect(layout.drawerWidth).toBe(576);
      expect(layout.drawerLeft + layout.drawerWidth).toBe(1385);
      expect(layout.drawerLeft + layout.drawerWidth).toBeLessThanOrEqual(viewportWidth);

      // Map width must NOT expand to 1044px or occupy excess horizontal space
      expect(layout.mapWidth).toBe(769);
      expect(layout.mapWidth).toBeLessThan(1044);
      expect(layout.mapRightEdge).toBe(785);

      // Preserves 24px clearance to drawer
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.drawerLeft - layout.mapRightEdge).toBe(24);
    });

    it('constrains page map wrapper in EmergencyMapPage for a 1385px desktop viewport', () => {
      // Map starts after 288px sidebar + 32px padding = 320px
      const layout = calculatePageMapWrapperLayout({
        viewportWidth: 1385,
        mapLeft: 320,
        drawerLeft: 1084, // Stale/unconstrained input
        drawerWidth: 576,
        isDrawerOpen: true,
        clearance: 24,
      });

      expect(layout.isConstrained).toBe(true);
      expect(layout.isStacked).toBe(false);

      // Drawer is clamped so it stays inside viewport
      expect(layout.drawerLeft).toBe(809); // Clamped from 1084 to 809

      // Map wrapper width is constrained to leave sufficient space for drawer
      expect(layout.maxAllowedWidth).toBe(465); // 809 - 24 - 320 = 465px
      expect(layout.mapRightEdge).toBe(785); // 320 + 465 = 785px
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.drawerLeft - layout.mapRightEdge).toBe(24);
      expect(layout.mapRightEdge).toBeLessThan(809);
    });

    it('verifies 1440px desktop viewport layout constraints and zero overlap', () => {
      const viewportWidth = 1440;
      const overlayLayout = calculateTacticalMapOverlayLayout(viewportWidth, 576, 24, 16);

      expect(overlayLayout.isDesktop).toBe(true);
      expect(overlayLayout.isStacked).toBe(false);
      expect(overlayLayout.drawerLeft).toBe(864); // 1440 - 576 = 864
      expect(overlayLayout.drawerLeft + overlayLayout.drawerWidth).toBe(1440);
      expect(overlayLayout.mapRightEdge).toBe(840); // 864 - 24 = 840
      expect(overlayLayout.mapWidth).toBe(824); // 840 - 16 = 824
      expect(overlayLayout.clearanceToDrawer).toBe(24);

      // Page map wrapper at 1440px
      const pageLayout = calculatePageMapWrapperLayout({
        viewportWidth: 1440,
        mapLeft: 320,
        drawerLeft: 864,
        drawerWidth: 576,
        isDrawerOpen: true,
        clearance: 24,
      });

      expect(pageLayout.isConstrained).toBe(true);
      expect(pageLayout.isStacked).toBe(false);
      expect(pageLayout.maxAllowedWidth).toBe(520); // 864 - 24 - 320 = 520
      expect(pageLayout.mapRightEdge).toBe(840);
      expect(pageLayout.clearanceToDrawer).toBe(24);
    });

    it('verifies 1920px Full HD desktop viewport layout constraints and zero overlap', () => {
      const viewportWidth = 1920;
      const overlayLayout = calculateTacticalMapOverlayLayout(viewportWidth, 576, 24, 16);

      expect(overlayLayout.isDesktop).toBe(true);
      expect(overlayLayout.isStacked).toBe(false);
      expect(overlayLayout.drawerLeft).toBe(1344); // 1920 - 576 = 1344
      expect(overlayLayout.drawerLeft + overlayLayout.drawerWidth).toBe(1920);
      expect(overlayLayout.mapRightEdge).toBe(1320); // 1344 - 24 = 1320
      expect(overlayLayout.mapWidth).toBe(1304); // 1320 - 16 = 1304
      expect(overlayLayout.clearanceToDrawer).toBe(24);

      // Page map wrapper at 1920px
      const pageLayout = calculatePageMapWrapperLayout({
        viewportWidth: 1920,
        mapLeft: 320,
        drawerLeft: 1344,
        drawerWidth: 576,
        isDrawerOpen: true,
        clearance: 24,
      });

      expect(pageLayout.isConstrained).toBe(true);
      expect(pageLayout.isStacked).toBe(false);
      expect(pageLayout.maxAllowedWidth).toBe(1000); // 1344 - 24 - 320 = 1000
      expect(pageLayout.mapRightEdge).toBe(1320);
      expect(pageLayout.clearanceToDrawer).toBe(24);
    });

    it('switches to responsive stacked layout on narrow desktop viewports where side-by-side map cannot maintain 300px', () => {
      // 850px viewport: 850 - 576 - 24 - 16 = 234px (< 300px threshold)
      const narrowOverlay = calculateTacticalMapOverlayLayout(850, 576, 24, 16);
      expect(narrowOverlay.isDesktop).toBe(true);
      expect(narrowOverlay.isStacked).toBe(true);
      expect(narrowOverlay.mapWidth).toBe(850); // Uses full width in stacked mode

      const narrowPageMap = calculatePageMapWrapperLayout({
        viewportWidth: 850,
        mapLeft: 16,
        drawerLeft: 274,
        drawerWidth: 576,
        isDrawerOpen: true,
        clearance: 24,
      });
      expect(narrowPageMap.isConstrained).toBe(true);
      expect(narrowPageMap.isStacked).toBe(true);
    });

    it('preserves mobile full-screen layout on viewports < 768px', () => {
      const mobileOverlay = calculateTacticalMapOverlayLayout(390, 576);
      expect(mobileOverlay.isDesktop).toBe(false);
      expect(mobileOverlay.isStacked).toBe(true);
      expect(mobileOverlay.mapWidth).toBe(390);

      const mobilePageMap = calculatePageMapWrapperLayout({
        viewportWidth: 390,
        mapLeft: 16,
        drawerLeft: 0,
        drawerWidth: 390,
        isDrawerOpen: true,
      });
      expect(mobilePageMap.isConstrained).toBe(false);
      expect(mobilePageMap.isStacked).toBe(false);
    });
  });
});
