import React, { useState, useEffect, useRef } from 'react';
import { MapPin, ShieldAlert, Crosshair, Navigation, ArrowLeft } from 'lucide-react';
import { TacticalMap } from '../components/map/TacticalMap';
import { EmergencyDetailDrawer } from '../components/emergencies/EmergencyDetailDrawer';
import { EmergencyStatusBadge, EmergencyTypeBadge } from '../components/common/StatusBadge';
import { useEmergencies } from '../context/EmergencyContext';
import { 
  isValidCoordinate, 
  formatCoordinate, 
  calculatePageMapWrapperLayout,
  type DrawerBoundingRect 
} from '../utils/coordinateUtils';
import type { Emergency } from '../types';

export const EmergencyMapPage: React.FC = () => {
  const { 
    emergencies, 
    rescueTeams, 
    selectedEmergency, 
    setSelectedEmergency,
  } = useEmergencies();

  const [drawerRect, setDrawerRect] = useState<DrawerBoundingRect | null>(null);
  const mapWrapperRef = useRef<HTMLDivElement>(null);
  const [mapLeft, setMapLeft] = useState<number>(0);
  const [viewportWidth, setViewportWidth] = useState<number>(
    typeof window !== 'undefined' ? window.innerWidth : 1200
  );
  const [focusTrigger, setFocusTrigger] = useState<number>(0);
  const [isMobileViewingMap, setIsMobileViewingMap] = useState<boolean>(false);

  useEffect(() => {
    if (!selectedEmergency) {
      setDrawerRect(null);
      setIsMobileViewingMap(false);
    }
  }, [selectedEmergency]);

  useEffect(() => {
    const updateDimensions = () => {
      const currentVp = typeof window !== 'undefined' ? window.innerWidth : 1200;
      setViewportWidth(currentVp);

      if (mapWrapperRef.current) {
        const rect = mapWrapperRef.current.getBoundingClientRect();
        if (rect.left > 0) {
          setMapLeft(rect.left);
        }
      }
      // Directly query the rendered drawer in the DOM if mounted
      const drawerEl = document.querySelector('[data-testid="emergency-detail-drawer"]');
      if (drawerEl) {
        const dRect = drawerEl.getBoundingClientRect();
        if (dRect.width > 0) {
          const effectiveW = Math.min(dRect.width, currentVp);
          const clampedL = Math.max(0, Math.min(dRect.left > 0 ? dRect.left : currentVp - effectiveW, currentVp - effectiveW));
          setDrawerRect({
            left: clampedL,
            width: effectiveW,
            right: clampedL + effectiveW,
          });
        }
      }
    };

    updateDimensions();

    const rafId = requestAnimationFrame(updateDimensions);
    const timerId = setTimeout(updateDimensions, 220);

    window.addEventListener('resize', updateDimensions);
    return () => {
      cancelAnimationFrame(rafId);
      clearTimeout(timerId);
      window.removeEventListener('resize', updateDimensions);
    };
  }, [selectedEmergency?.id]);

  const pageMapLayout = calculatePageMapWrapperLayout({
    viewportWidth,
    mapLeft: mapLeft > 0 ? mapLeft : (viewportWidth >= 1024 ? 320 : 16),
    drawerLeft: drawerRect?.left ?? Math.max(0, viewportWidth - 576),
    drawerWidth: drawerRect?.width ?? 576,
    isDrawerOpen: selectedEmergency !== null,
    clearance: 24,
  });

  const mapWrapperStyle: React.CSSProperties = pageMapLayout.isConstrained && !pageMapLayout.isStacked
    ? {
        maxWidth: `${pageMapLayout.maxAllowedWidth}px`,
        width: `${pageMapLayout.maxAllowedWidth}px`,
        flex: 'none',
      }
    : {};

  const activeEmergencies = emergencies.filter(
    e => e.status !== 'RESOLVED' && e.status !== 'CANCELLED' && isValidCoordinate(e.latitude, e.longitude)
  );

  const handleLocateOnMap = (emergency: Emergency) => {
    setSelectedEmergency(emergency);
    setFocusTrigger((prev) => prev + 1);
    if (typeof window !== 'undefined' && window.innerWidth < 768) {
      setIsMobileViewingMap(true);
    }
  };

  return (
    <div className="space-y-6">
      {/* Apple Header Card */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-[20px] border border-slate-200/90 dark:border-white/[0.1] bg-white dark:bg-[#161619] shadow-sm dark:shadow-md transition-colors">
        <div>
          <h2 className="text-lg font-bold text-slate-900 dark:text-white tracking-tight flex items-center gap-2">
            <span className="w-8 h-8 rounded-full bg-ios-blue/15 flex items-center justify-center text-ios-blue">
              <MapPin className="w-4 h-4" />
            </span>
            Geospatial Incident Command Map
          </h2>
          <p className="text-xs text-slate-600 dark:text-[#a1a1a6] mt-1 font-normal">
            Real-time geospatial plotting of verified SOS distress signals, command beacon, and field rescue teams.
          </p>
        </div>

        <div className="flex items-center gap-2 text-xs">
          <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400 border border-rose-500/25 font-semibold">
            <span className="w-2 h-2 rounded-full bg-rose-500 animate-ping" />
            {activeEmergencies.length} Active Pins
          </span>
          <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-blue-500/15 text-blue-600 dark:text-blue-400 border border-blue-500/25 font-semibold">
            <Navigation className="w-3.5 h-3.5" />
            {rescueTeams.length} Field Teams
          </span>
        </div>
      </div>

      {/* Map + Side Incident Quick-Selector */}
      <div className="flex flex-col lg:flex-row gap-6 items-start">
        {/* Interactive Apple-Styled Leaflet Map */}
        <div 
          ref={mapWrapperRef}
          style={mapWrapperStyle}
          className="w-full flex-1 rounded-[20px] overflow-hidden border border-slate-200/90 dark:border-white/[0.1] shadow-sm dark:shadow-md transition-all duration-200"
        >
          <TacticalMap
            emergencies={emergencies}
            rescueTeams={rescueTeams}
            selectedEmergency={selectedEmergency}
            onSelectEmergency={setSelectedEmergency}
            heightClass="h-[650px]"
            focusTrigger={focusTrigger}
          />
        </div>

        {/* Side Panel: Active Incident Quick Focus */}
        <div className={`w-full lg:w-80 shrink-0 rounded-[20px] border border-slate-200/90 dark:border-white/[0.1] bg-white dark:bg-[#161619] p-4 flex flex-col h-[650px] shadow-sm dark:shadow-md transition-colors ${
          selectedEmergency ? 'hidden' : 'flex'
        }`}>
          <div className="flex items-center justify-between border-b border-black/[0.06] dark:border-white/[0.06] pb-3 mb-3">
            <h3 className="text-xs font-semibold text-slate-900 dark:text-white flex items-center gap-1.5">
              <Crosshair className="w-3.5 h-3.5 text-ios-blue" />
              Target Queue ({activeEmergencies.length})
            </h3>
            <span className="text-[10px] text-slate-500 dark:text-ios-secondary font-medium uppercase tracking-wider">Tap to pan</span>
          </div>

          <div className="flex-1 overflow-y-auto space-y-2 pr-1 custom-scrollbar">
            {activeEmergencies.length === 0 ? (
              <div className="p-6 text-center text-xs text-slate-500 dark:text-ios-secondary flex flex-col items-center justify-center h-full">
                <div className="w-12 h-12 rounded-full bg-ios-green/15 flex items-center justify-center text-ios-green mb-3">
                  <ShieldAlert className="w-6 h-6" />
                </div>
                <p className="font-semibold text-slate-900 dark:text-white">No Active SOS Signals</p>
                <span className="text-[11px] text-slate-500 dark:text-ios-secondary mt-1 block">Monitored sector is currently clear</span>
              </div>
            ) : (
              activeEmergencies.map((em) => {
                const isSelected = selectedEmergency?.id === em.id;
                return (
                  <div
                    key={em.id}
                    onClick={() => setSelectedEmergency(em)}
                    className={`p-3.5 rounded-[14px] border cursor-pointer transition-all ${
                      isSelected
                        ? 'border-ios-blue bg-ios-blue/15 shadow-sm'
                        : 'border-black/[0.06] dark:border-white/[0.06] bg-black/[0.02] dark:bg-white/[0.03] hover:bg-black/[0.04] dark:hover:bg-white/[0.06]'
                    }`}
                  >
                    <div className="flex items-center justify-between mb-1.5">
                      <span className="font-semibold text-xs text-ios-blue">
                        {em.emergency_code}
                      </span>
                      <EmergencyStatusBadge status={em.status} size="sm" />
                    </div>

                    <div className="flex items-center gap-1.5 mb-1.5">
                      <EmergencyTypeBadge type={em.emergency_type} />
                    </div>

                    <div className="text-xs font-medium text-slate-800 dark:text-slate-200 truncate">
                      {em.sender_name || (em.is_guest ? 'Guest SOS User' : 'Registered User')}
                    </div>

                    <div className="text-[11px] text-slate-500 dark:text-ios-secondary mt-1.5 flex items-center justify-between">
                      <span>{formatCoordinate(em.latitude, em.longitude, 4)}</span>
                      <span className="text-[10px] px-2 py-0.5 rounded-full bg-black/[0.05] dark:bg-white/[0.05]">{em.communication_method}</span>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      {/* Mobile Single-Map Layout: Floating Return to Details Control */}
      {isMobileViewingMap && selectedEmergency && viewportWidth < 768 && (
        <div 
          data-testid="mobile-map-return-banner"
          className="fixed top-4 left-4 right-4 z-40 md:hidden flex items-center justify-between p-3 rounded-full bg-white/95 dark:bg-[#1c1c1e]/95 backdrop-blur-xl border border-black/[0.08] dark:border-white/[0.1] shadow-2xl animate-in fade-in slide-in-from-top-3 duration-200"
        >
          <button
            type="button"
            data-testid="mobile-back-to-details-btn"
            onClick={() => setIsMobileViewingMap(false)}
            className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-ios-blue text-white shadow-ios-pill text-xs font-semibold active:scale-95 transition-all"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>Back to Incident Details</span>
          </button>
          <div className="flex items-center gap-2 pr-1.5">
            <span className="font-mono text-xs font-bold text-slate-900 dark:text-white">
              {selectedEmergency.emergency_code}
            </span>
            <EmergencyStatusBadge status={selectedEmergency.status} size="sm" />
          </div>
        </div>
      )}

      {/* Slide-over Detail Drawer: On desktop always visible side-by-side; on mobile hidden when operator inspects single map */}
      {(!isMobileViewingMap || viewportWidth >= 768) && (
        <EmergencyDetailDrawer
          emergency={selectedEmergency}
          onClose={() => {
            setSelectedEmergency(null);
            setIsMobileViewingMap(false);
          }}
          onViewOnMap={handleLocateOnMap}
          onDrawerRectChange={setDrawerRect}
          hasBackdrop={false}
        />
      )}
    </div>
  );
};
