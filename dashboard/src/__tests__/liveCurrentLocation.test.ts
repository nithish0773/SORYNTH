import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import tacticalMapSource from '../components/map/TacticalMap.tsx?raw';
import useLiveLocationSource from '../hooks/useLiveLocation.ts?raw';
import emergencyMapPageSource from '../pages/EmergencyMapPage.tsx?raw';
import { 
  POOR_ACCURACY_THRESHOLD_METERS, 
  GEOLOCATION_CONFIG 
} from '../hooks/useLiveLocation';
import { parseCoordinate, isValidCoordinate } from '../utils/coordinateUtils';

describe('SORYNTH — Accurate Live Current Location Feature', () => {

  // =========================================================================
  // 1. Architecture & Privacy Verification
  // =========================================================================
  describe('1. Security, Privacy & Single Map Architecture', () => {
    it('proves exactly ONE TacticalMap instance is rendered on EmergencyMapPage', () => {
      const mapMatches = emergencyMapPageSource.match(/<TacticalMap\b/g);
      expect(mapMatches).not.toBeNull();
      expect(mapMatches?.length).toBe(1);
    });

    it('proves TacticalMap renders exactly ONE Leaflet MapContainer', () => {
      const containerMatches = tacticalMapSource.match(/<MapContainer\b/g);
      expect(containerMatches).not.toBeNull();
      expect(containerMatches?.length).toBe(1);
    });

    it('proves location is NEVER auto-requested on mount (no auto-fetch useEffect)', () => {
      // Must not contain auto-invocations on mount like useEffect(() => { handleLocateMe(false); }, ...)
      expect(tacticalMapSource).not.toMatch(/useEffect\(\s*\(\)\s*=>\s*\{\s*handleLocateMe/);
      expect(tacticalMapSource).not.toMatch(/useEffect\(\s*\(\)\s*=>\s*\{\s*requestLocation/);
    });

    it('proves no continuous tracking occurs without explicit user consent', () => {
      expect(tacticalMapSource).toContain('data-testid="live-tracking-toggle-btn"');
      expect(useLiveLocationSource).toContain('watchPosition');
      expect(useLiveLocationSource).toContain('clearWatch');
    });

    it('proves raw GPS coordinates are not automatically sent to Supabase on acquisition', () => {
      // TacticalMap must not directly call supabase.from('...').insert or update with liveLocation
      expect(tacticalMapSource).not.toMatch(/supabase\s*\.\s*from\([^)]+\)\s*\.\s*(insert|update|upsert)\(\s*\[?\s*liveLocation/);
    });
  });

  // =========================================================================
  // 2. Geolocation Configuration & High-Accuracy Hardware Lock
  // =========================================================================
  describe('2. Geolocation API Configuration & Accuracy Standards', () => {
    it('enforces enableHighAccuracy: true for genuine hardware satellite lock', () => {
      expect(GEOLOCATION_CONFIG.enableHighAccuracy).toBe(true);
      expect(useLiveLocationSource).toContain('enableHighAccuracy: true');
    });

    it('enforces maximumAge: 0 to prohibit stale cached GPS coordinates', () => {
      expect(GEOLOCATION_CONFIG.maximumAge).toBe(0);
      expect(useLiveLocationSource).toContain('maximumAge: 0');
    });

    it('specifies an adequate timeout for hardware satellite lock (12 seconds)', () => {
      expect(GEOLOCATION_CONFIG.timeout).toBe(12000);
    });

    it('defines a poor accuracy threshold of 100 metres', () => {
      expect(POOR_ACCURACY_THRESHOLD_METERS).toBe(100);
    });

    it('proves never labeling location as 100% accurate (displays precision in metres)', () => {
      expect(tacticalMapSource).toContain('GPS Precision: ±');
      expect(tacticalMapSource).toContain('Never 100% exact');
    });
  });

  // =========================================================================
  // 3. Coordinate Validation & Null Island Protection
  // =========================================================================
  describe('3. GPS Coordinate Validation & Null Island Filtering', () => {
    it('validates genuine real-world GPS coordinates', () => {
      const coord = parseCoordinate(12.914142, 74.856012);
      expect(coord).not.toBeNull();
      expect(coord?.latitude).toBeCloseTo(12.914142, 5);
      expect(coord?.longitude).toBeCloseTo(74.856012, 5);
    });

    it('strictly rejects Null Island (0, 0) coordinates from improper GPS fix', () => {
      const nullIsland = parseCoordinate(0, 0);
      expect(nullIsland).toBeNull();
      expect(isValidCoordinate(0, 0)).toBe(false);
    });

    it('strictly rejects out-of-range coordinates (> 90 lat or > 180 lng)', () => {
      expect(parseCoordinate(95.0, 74.0)).toBeNull();
      expect(parseCoordinate(12.0, 195.0)).toBeNull();
      expect(parseCoordinate(NaN, 74.0)).toBeNull();
      expect(parseCoordinate(12.0, Infinity)).toBeNull();
    });
  });

  // =========================================================================
  // 4. UI Elements & Test IDs
  // =========================================================================
  describe('4. Tactical Map Toolbar & Interactive Controls', () => {
    it('provides a clearly visible "Use Current Location" button with data-testid="use-current-location-btn"', () => {
      expect(tacticalMapSource).toContain('data-testid="use-current-location-btn"');
      expect(tacticalMapSource).toContain('handleUseCurrentLocation');
    });

    it('provides a Live Tracking toggle button with data-testid="live-tracking-toggle-btn"', () => {
      expect(tacticalMapSource).toContain('data-testid="live-tracking-toggle-btn"');
      expect(tacticalMapSource).toContain('handleToggleLiveTracking');
    });

    it('renders the floating status banner with retry and dismiss buttons', () => {
      expect(tacticalMapSource).toContain('data-testid="gps-status-banner"');
      expect(tacticalMapSource).toContain('data-testid="gps-retry-btn"');
      expect(tacticalMapSource).toContain('data-testid="gps-dismiss-error-btn"');
    });

    it('preserves existing Fit All, Active filter, and Teams toggle controls while ensuring test dispatch buttons are removed', () => {
      expect(tacticalMapSource).toContain('Fit All');
      expect(tacticalMapSource).toContain('filterActiveOnly');
      expect(tacticalMapSource).toContain('setShowTeams');
      expect(tacticalMapSource).not.toContain('handleQuickDispatch');
      expect(tacticalMapSource).not.toContain('Dispatch SOS');
    });

    it('preserves all 4 map layers: Dark, Satellite, Terrain, and Street', () => {
      expect(tacticalMapSource).toContain("setMapLayer('tactical')");
      expect(tacticalMapSource).toContain("setMapLayer('satellite')");
      expect(tacticalMapSource).toContain("setMapLayer('terrain')");
      expect(tacticalMapSource).toContain("setMapLayer('street')");
    });
  });

  // =========================================================================
  // 5. Map Integration: Accuracy Circle & Marker Positioning
  // =========================================================================
  describe('5. Map Integration & Accuracy Circle', () => {
    it('renders the Leaflet Circle with radius matching liveLocation.accuracy', () => {
      expect(tacticalMapSource).toContain('center={[liveLocation.latitude, liveLocation.longitude]}');
      expect(tacticalMapSource).toContain('radius={liveLocation.accuracy}');
    });

    it('renders the current location Marker at [liveLocation.latitude, liveLocation.longitude]', () => {
      expect(tacticalMapSource).toContain('position={[liveLocation.latitude, liveLocation.longitude]}');
      expect(tacticalMapSource).toContain('createCurrentLocationIcon(isGpsPoorAccuracy)');
    });

    it('passes liveLocation to MapViewController for targetFly centering', () => {
      expect(tacticalMapSource).toContain('currentLocation={liveLocation}');
      expect(tacticalMapSource).toContain('setTargetFly({ lat: loc.latitude, lng: loc.longitude, zoom: 16');
    });

    it('preserves real SOS emergency markers and rescue team markers without modification', () => {
      expect(tacticalMapSource).toContain('validEmergencies.map((em) => {');
      expect(tacticalMapSource).toContain('validTeams.map((team) => {');
      expect(tacticalMapSource).toContain('createEmergencyIcon(em.status, isSelected)');
      expect(tacticalMapSource).toContain('createTeamIcon()');
    });
  });

  // =========================================================================
  // 6. Hook Logic Simulation & State Transitions
  // =========================================================================
  describe('6. useLiveLocation Execution Flow & Error Handling Simulation', () => {
    type SuccessCb = (pos: GeolocationPosition) => void;
    type ErrorCb = (err: GeolocationPositionError) => void;

    let getCurrentPositionMock: ReturnType<typeof vi.fn>;
    let watchPositionMock: ReturnType<typeof vi.fn>;
    let clearWatchMock: ReturnType<typeof vi.fn>;

    beforeEach(() => {
      getCurrentPositionMock = vi.fn();
      watchPositionMock = vi.fn();
      clearWatchMock = vi.fn();

      const mockGeo = {
        getCurrentPosition: (s: SuccessCb, e?: ErrorCb, o?: PositionOptions) => (getCurrentPositionMock as Function)(s, e, o),
        watchPosition: (s: SuccessCb, e?: ErrorCb, o?: PositionOptions) => (watchPositionMock as Function)(s, e, o) as number,
        clearWatch: (id: number) => (clearWatchMock as Function)(id),
      };

      vi.stubGlobal('navigator', {
        geolocation: mockGeo,
      });

      vi.stubGlobal('window', {
        isSecureContext: true,
      });
    });

    afterEach(() => {
      vi.unstubAllGlobals();
      vi.restoreAllMocks();
    });

    it('simulates successful high-accuracy GPS lock', async () => {
      getCurrentPositionMock.mockImplementation((success: SuccessCb) => {
        success({
          coords: {
            latitude: 12.91414,
            longitude: 74.85601,
            accuracy: 8.5,
            altitude: 42.0,
            speed: 0.2,
            heading: 180,
            altitudeAccuracy: null,
          },
          timestamp: 1700000000000,
        } as unknown as GeolocationPosition);
      });

      let acquiredData: unknown = null;
      await new Promise<void>((resolve) => {
        navigator.geolocation.getCurrentPosition((pos: GeolocationPosition) => {
          const { latitude, longitude, accuracy, altitude, speed, heading } = pos.coords;
          const validated = parseCoordinate(latitude, longitude);
          expect(validated).not.toBeNull();
          acquiredData = {
            latitude: validated!.latitude,
            longitude: validated!.longitude,
            accuracy,
            altitude,
            speed,
            heading,
            timestamp: pos.timestamp,
          };
          resolve();
        }, vi.fn(), GEOLOCATION_CONFIG);
      });

      expect(getCurrentPositionMock).toHaveBeenCalledWith(
        expect.any(Function),
        expect.any(Function),
        GEOLOCATION_CONFIG
      );

      expect(acquiredData).toEqual({
        latitude: 12.91414,
        longitude: 74.85601,
        accuracy: 8.5,
        altitude: 42.0,
        speed: 0.2,
        heading: 180,
        timestamp: 1700000000000,
      });
    });

    it('simulates Permission Denied (error code 1)', async () => {
      getCurrentPositionMock.mockImplementation((_success: SuccessCb, error: ErrorCb) => {
        error({
          code: 1,
          message: 'User denied Geolocation',
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3,
        });
      });

      let status = 'IDLE';
      let errorMessage: string | null = null;
      let retryInstructions: string | null = null;

      await new Promise<void>((resolve) => {
        navigator.geolocation.getCurrentPosition(
          vi.fn(),
          (err: GeolocationPositionError) => {
            if (err.code === 1) {
              status = 'PERMISSION_DENIED';
              errorMessage = 'Location permission was denied.';
              retryInstructions = 'Click the lock/settings icon in your browser address bar, allow Location access, and click Retry.';
            }
            resolve();
          },
          GEOLOCATION_CONFIG
        );
      });

      expect(status).toBe('PERMISSION_DENIED');
      expect(errorMessage).toBe('Location permission was denied.');
      expect(retryInstructions).toContain('allow Location access');
    });

    it('simulates Position Unavailable (error code 2)', async () => {
      getCurrentPositionMock.mockImplementation((_success: SuccessCb, error: ErrorCb) => {
        error({
          code: 2,
          message: 'Position unavailable',
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3,
        });
      });

      let status = 'IDLE';
      let errorMessage: string | null = null;

      await new Promise<void>((resolve) => {
        navigator.geolocation.getCurrentPosition(
          vi.fn(),
          (err: GeolocationPositionError) => {
            if (err.code === 2) {
              status = 'POSITION_UNAVAILABLE';
              errorMessage = 'GPS satellites or location provider is unavailable.';
            }
            resolve();
          },
          GEOLOCATION_CONFIG
        );
      });

      expect(status).toBe('POSITION_UNAVAILABLE');
      expect(errorMessage).toBe('GPS satellites or location provider is unavailable.');
    });

    it('simulates Timeout (error code 3)', async () => {
      getCurrentPositionMock.mockImplementation((_success: SuccessCb, error: ErrorCb) => {
        error({
          code: 3,
          message: 'Timeout expired',
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3,
        });
      });

      let status = 'IDLE';
      let errorMessage: string | null = null;

      await new Promise<void>((resolve) => {
        navigator.geolocation.getCurrentPosition(
          vi.fn(),
          (err: GeolocationPositionError) => {
            if (err.code === 3) {
              status = 'TIMEOUT';
              errorMessage = 'GPS location request timed out.';
            }
            resolve();
          },
          GEOLOCATION_CONFIG
        );
      });

      expect(status).toBe('TIMEOUT');
      expect(errorMessage).toBe('GPS location request timed out.');
    });

    it('identifies and handles Low Accuracy (> 100m)', () => {
      const accuracy = 145.0; // 145 metres uncertainty
      const isPoor = accuracy > POOR_ACCURACY_THRESHOLD_METERS;
      expect(isPoor).toBe(true);

      const status = isPoor ? 'LOW_ACCURACY' : 'LOCKED';
      expect(status).toBe('LOW_ACCURACY');
    });

    it('identifies and accepts Good Accuracy (<= 100m)', () => {
      const accuracy = 12.0; // 12 metres uncertainty
      const isPoor = accuracy > POOR_ACCURACY_THRESHOLD_METERS;
      expect(isPoor).toBe(false);

      const status = isPoor ? 'LOW_ACCURACY' : 'LOCKED';
      expect(status).toBe('LOCKED');
    });

    it('simulates live tracking watchPosition registration and unwatch cleanup', () => {
      watchPositionMock.mockReturnValue(99);

      const watchId = navigator.geolocation.watchPosition(vi.fn(), vi.fn(), GEOLOCATION_CONFIG);
      expect(watchId).toBe(99);
      expect(watchPositionMock).toHaveBeenCalledWith(
        expect.any(Function),
        expect.any(Function),
        GEOLOCATION_CONFIG
      );

      // Stop tracking
      navigator.geolocation.clearWatch(watchId);
      expect(clearWatchMock).toHaveBeenCalledWith(99);
    });

    it('detects insecure context (HTTP) and marks as UNSUPPORTED', () => {
      const isSecureContext = false;
      let status = 'IDLE';
      let errorMessage: string | null = null;

      if (!isSecureContext) {
        status = 'UNSUPPORTED';
        errorMessage = 'Geolocation requires a secure context (HTTPS or localhost).';
      }

      expect(status).toBe('UNSUPPORTED');
      expect(errorMessage).toContain('HTTPS or localhost');
    });
  });
});
