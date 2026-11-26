import { useState, useEffect, useRef, useCallback } from 'react';
import { parseCoordinate } from '../utils/coordinateUtils';

export type GpsStatus = 
  | 'IDLE'
  | 'ACQUIRING'
  | 'LOCKED'
  | 'LOW_ACCURACY'
  | 'PERMISSION_DENIED'
  | 'POSITION_UNAVAILABLE'
  | 'TIMEOUT'
  | 'UNSUPPORTED'
  | 'ERROR';

export interface LiveLocationData {
  latitude: number;
  longitude: number;
  accuracy: number; // Uncertainty radius in metres
  altitude: number | null;
  speed: number | null;
  heading: number | null;
  timestamp: number;
}

export interface UseLiveLocationReturn {
  location: LiveLocationData | null;
  status: GpsStatus;
  errorMessage: string | null;
  retryInstructions: string | null;
  isAcquiring: boolean;
  isWatching: boolean;
  isPoorAccuracy: boolean;
  requestLocation: () => Promise<LiveLocationData | null>;
  startLiveTracking: () => void;
  stopLiveTracking: () => void;
  toggleLiveTracking: () => void;
  clearError: () => void;
}

export const POOR_ACCURACY_THRESHOLD_METERS = 100;

export const GEOLOCATION_CONFIG: PositionOptions = {
  enableHighAccuracy: true,
  maximumAge: 0, // Never use stale cached GPS coordinates
  timeout: 12000, // 12 seconds timeout for hardware satellite lock
};

/**
 * Production-ready hook for acquiring and tracking live GPS coordinates.
 * Strictly adheres to security & privacy:
 * - Location is NEVER auto-requested on mount; only user interactions initiate GPS queries.
 * - Does not send coordinates to remote backends without explicit authorization.
 * - Enforces HTTPS secure context and Geolocation API availability.
 * - Detects poor GPS accuracy and provides actionable retry instructions.
 * - Never labels location as 100% accurate; always states precision in metres (±X m).
 */
export function useLiveLocation(): UseLiveLocationReturn {
  const [location, setLocation] = useState<LiveLocationData | null>(null);
  const [status, setStatus] = useState<GpsStatus>('IDLE');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [retryInstructions, setRetryInstructions] = useState<string | null>(null);
  const [isWatching, setIsWatching] = useState<boolean>(false);

  const watchIdRef = useRef<number | null>(null);
  const isMountedRef = useRef<boolean>(true);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      if (watchIdRef.current !== null && typeof navigator !== 'undefined' && navigator.geolocation) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, []);

  const handlePositionSuccess = useCallback((pos: GeolocationPosition): LiveLocationData | null => {
    if (!isMountedRef.current) return null;

    const { latitude, longitude, accuracy, altitude, speed, heading } = pos.coords;
    const validated = parseCoordinate(latitude, longitude);

    if (!validated) {
      setStatus('ERROR');
      setErrorMessage('Acquired GPS coordinates failed validation (invalid range or Null Island fix).');
      setRetryInstructions('Wait for a reliable satellite fix with clear sky visibility and retry.');
      return null;
    }

    const safeAccuracy = Number.isFinite(accuracy) ? Math.max(1, accuracy) : 50;
    const isPoor = safeAccuracy > POOR_ACCURACY_THRESHOLD_METERS;

    const locationData: LiveLocationData = {
      latitude: validated.latitude,
      longitude: validated.longitude,
      accuracy: safeAccuracy,
      altitude: altitude ?? null,
      speed: speed ?? null,
      heading: heading ?? null,
      timestamp: pos.timestamp || Date.now(),
    };

    setLocation(locationData);

    if (isPoor) {
      setStatus('LOW_ACCURACY');
      setErrorMessage(`Low GPS accuracy: ±${Math.round(safeAccuracy)}m (satellite lock is imprecise).`);
      setRetryInstructions('Move near a window or outdoors for better satellite reception, and click Retry.');
    } else {
      setStatus('LOCKED');
      setErrorMessage(null);
      setRetryInstructions(null);
    }

    return locationData;
  }, []);

  const handlePositionError = useCallback((err: GeolocationPositionError) => {
    if (!isMountedRef.current) return;

    switch (err.code) {
      case 1: // PERMISSION_DENIED
        setStatus('PERMISSION_DENIED');
        setErrorMessage('Location permission was denied.');
        setRetryInstructions('Click the lock/settings icon in your browser address bar, allow Location access, and click Retry.');
        break;
      case 2: // POSITION_UNAVAILABLE
        setStatus('POSITION_UNAVAILABLE');
        setErrorMessage('GPS satellites or location provider is unavailable.');
        setRetryInstructions('Ensure device GPS/location services are turned on in system settings, and move outdoors with clear sky visibility.');
        break;
      case 3: // TIMEOUT
        setStatus('TIMEOUT');
        setErrorMessage('GPS location request timed out.');
        setRetryInstructions('Hardware satellite lock took longer than 12 seconds. Ensure location services are active and click Retry.');
        break;
      default:
        setStatus('ERROR');
        setErrorMessage(err.message || 'An unexpected error occurred while acquiring GPS coordinates.');
        setRetryInstructions('Check device location settings and try again.');
        break;
    }
  }, []);

  const verifyEnvironment = useCallback((): boolean => {
    // Check secure context (Geolocation requires HTTPS or localhost)
    if (typeof window !== 'undefined' && window.isSecureContext === false) {
      setStatus('UNSUPPORTED');
      setErrorMessage('Geolocation requires a secure context (HTTPS or localhost).');
      setRetryInstructions('Please access this dashboard over HTTPS or localhost to enable GPS hardware access.');
      return false;
    }

    // Check Geolocation API support
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      setStatus('UNSUPPORTED');
      setErrorMessage('Geolocation API is not supported by this browser.');
      setRetryInstructions('Please use a modern browser such as Chrome, Safari, Firefox, or Edge.');
      return false;
    }

    return true;
  }, []);

  const requestLocation = useCallback(async (): Promise<LiveLocationData | null> => {
    if (!verifyEnvironment()) {
      return null;
    }

    setStatus('ACQUIRING');
    setErrorMessage(null);
    setRetryInstructions(null);

    return new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          const result = handlePositionSuccess(pos);
          resolve(result);
        },
        (err) => {
          handlePositionError(err);
          resolve(null);
        },
        GEOLOCATION_CONFIG
      );
    });
  }, [verifyEnvironment, handlePositionSuccess, handlePositionError]);

  const startLiveTracking = useCallback(() => {
    if (!verifyEnvironment()) {
      return;
    }

    if (watchIdRef.current !== null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }

    setStatus('ACQUIRING');
    setIsWatching(true);

    const id = navigator.geolocation.watchPosition(
      (pos) => {
        handlePositionSuccess(pos);
      },
      (err) => {
        handlePositionError(err);
      },
      GEOLOCATION_CONFIG
    );

    watchIdRef.current = id;
  }, [verifyEnvironment, handlePositionSuccess, handlePositionError]);

  const stopLiveTracking = useCallback(() => {
    if (watchIdRef.current !== null && typeof navigator !== 'undefined' && navigator.geolocation) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    setIsWatching(false);
  }, []);

  const toggleLiveTracking = useCallback(() => {
    if (isWatching) {
      stopLiveTracking();
    } else {
      startLiveTracking();
    }
  }, [isWatching, startLiveTracking, stopLiveTracking]);

  const clearError = useCallback(() => {
    setErrorMessage(null);
    setRetryInstructions(null);
  }, []);

  return {
    location,
    status,
    errorMessage,
    retryInstructions,
    isAcquiring: status === 'ACQUIRING',
    isWatching,
    isPoorAccuracy: status === 'LOW_ACCURACY',
    requestLocation,
    startLiveTracking,
    stopLiveTracking,
    toggleLiveTracking,
    clearError,
  };
}

