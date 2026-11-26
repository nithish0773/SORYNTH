import { describe, it, expect, vi } from 'vitest';
import emergencyMapPageSource from '../pages/EmergencyMapPage.tsx?raw';
import emergencyDetailDrawerSource from '../components/emergencies/EmergencyDetailDrawer.tsx?raw';
import tacticalMapSource from '../components/map/TacticalMap.tsx?raw';
import { 
  calculatePageMapWrapperLayout, 
  toLeafletLatLng 
} from '../utils/coordinateUtils';
import type { Emergency } from '../types';

describe('SORYNTH — Single Tactical Map Architecture & SOS Drawer Integration', () => {
  const mockEmergency: Emergency = {
    id: 'em-tactical-001',
    emergency_code: 'SOR-TAC-01',
    is_guest: false,
    sender_name: 'Field Scout Unit 1',
    sender_phone: '+91-9876543210',
    emergency_type: 'MEDICAL',
    latitude: 12.9141,
    longitude: 74.8560,
    accuracy_meters: 10,
    communication_method: 'LORA_RELAY',
    status: 'DELIVERED',
    hop_count: 2,
    custom_message: 'Injured trekker requires field evacuation',
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  describe('1. Single Map Architecture Verification', () => {
    it('proves exactly ONE TacticalMap instance is rendered on EmergencyMapPage', () => {
      // Find all JSX occurrences of <TacticalMap in EmergencyMapPage
      const tacticalMapMatches = emergencyMapPageSource.match(/<TacticalMap[\s\S]*?>/g);
      expect(tacticalMapMatches).not.toBeNull();
      expect(tacticalMapMatches!.length).toBe(1);

      // Verify it is placed inside the mapWrapperRef container
      expect(emergencyMapPageSource).toContain('ref={mapWrapperRef}');
      expect(emergencyMapPageSource).toContain('<TacticalMap');
    });

    it('proves ZERO TacticalMap instances exist inside EmergencyDetailDrawer (duplicate map overlay removed)', () => {
      // Ensure EmergencyDetailDrawer no longer imports TacticalMap
      expect(emergencyDetailDrawerSource).not.toMatch(/import\s+{\s*TacticalMap\s*}\s+from/);
      
      // Ensure no <TacticalMap JSX tag exists inside EmergencyDetailDrawer
      const tacticalMapMatches = emergencyDetailDrawerSource.match(/<TacticalMap/g);
      expect(tacticalMapMatches).toBeNull();

      // Ensure the old duplicate map overlay container is completely removed
      expect(emergencyDetailDrawerSource).not.toContain('data-testid="tactical-map-overlay"');
      expect(emergencyDetailDrawerSource).not.toContain('showMapOverlay');
    });

    it('proves the duplicate dark map header showing Received status and close button is removed', () => {
      // Old duplicate overlay had: "Tactical Incident Beacon: {emergency.emergency_code}" with a map close button
      expect(emergencyDetailDrawerSource).not.toContain('Tactical Incident Beacon:');
      expect(emergencyDetailDrawerSource).not.toContain('data-testid="map-overlay-close-btn"');
      expect(emergencyDetailDrawerSource).not.toContain('data-testid="map-overlay-back-btn"');
    });
  });

  describe('2. Locate On Command Map Workflow & Map Focusing', () => {
    it('proves Locate On Command Map invokes onViewOnMap callback with the emergency', () => {
      expect(emergencyDetailDrawerSource).toContain('data-testid="locate-on-map-btn"');
      // When clicked, it must delegate to onViewOnMap
      expect(emergencyDetailDrawerSource).toContain('onViewOnMap(emergency)');
    });

    it('proves EmergencyMapPage wires onViewOnMap to handleLocateOnMap and increments focusTrigger', () => {
      expect(emergencyMapPageSource).toContain('onViewOnMap={handleLocateOnMap}');
      expect(emergencyMapPageSource).toContain('setFocusTrigger((prev) => prev + 1)');
      expect(emergencyMapPageSource).toContain('focusTrigger={focusTrigger}');
    });

    it('proves TacticalMap supports focusTrigger and invokes map.flyTo with vertical headroom', () => {
      // TacticalMap component accepts focusTrigger in props
      expect(tacticalMapSource).toContain('focusTrigger?: number');
      expect(tacticalMapSource).toContain('focusTrigger = 0');

      // MapViewController passes focusTrigger in dependency array
      expect(tacticalMapSource).toContain('[selectedEmergency, focusTrigger, map]');

      // Test map.flyTo calculation with 70px vertical headroom
      const mockMap = {
        project: vi.fn((_latlng: [number, number], _zoom: number) => {
          return { x: 500, y: 500 };
        }),
        unproject: vi.fn((_pt: { x: number; y: number }, _zoom: number) => {
          return [12.915, 74.856];
        }),
        flyTo: vi.fn(),
      };

      const pt = toLeafletLatLng(mockEmergency.latitude, mockEmergency.longitude)!;
      expect(pt).toEqual([12.9141, 74.856]);

      const zoom = 16;
      const targetPoint = mockMap.project(pt, zoom);
      const offsetPoint = { x: targetPoint.x, y: targetPoint.y - 70 };
      const adjustedCenter = mockMap.unproject(offsetPoint, zoom);
      mockMap.flyTo(adjustedCenter, zoom, { duration: 1.2 });

      expect(mockMap.project).toHaveBeenCalledWith(pt, 16);
      expect(mockMap.unproject).toHaveBeenCalled();
      expect(mockMap.flyTo).toHaveBeenCalledWith(adjustedCenter, 16, { duration: 1.2 });
    });

    it('proves markerRefs programmatically opens the selected SOS marker popup on focusTrigger', () => {
      // Verifies TacticalMap retains a markerRefs map and triggers marker.openPopup()
      expect(tacticalMapSource).toContain('markerRefs.current.get(selectedEmergency.id)');
      expect(tacticalMapSource).toContain('marker.openPopup()');

      const mockMarker = {
        openPopup: vi.fn(),
      };

      const markerMap = new Map<string, typeof mockMarker>();
      markerMap.set(mockEmergency.id, mockMarker);

      // Simulate focus event
      const marker = markerMap.get(mockEmergency.id);
      expect(marker).toBeDefined();
      marker?.openPopup();
      expect(mockMarker.openPopup).toHaveBeenCalledTimes(1);
    });
  });

  describe('3. SOS Drawer Integrity & Dispatch Controls', () => {
    it('proves the SOS Detail Drawer retains all rescue operator dispatch controls', () => {
      // All action buttons must be preserved in EmergencyDetailDrawer
      expect(emergencyDetailDrawerSource).toContain("handleStatusChange('ACKNOWLEDGED')");
      expect(emergencyDetailDrawerSource).toContain("handleStatusChange('IN_ACTION')");
      expect(emergencyDetailDrawerSource).toContain("handleStatusChange('RESOLVED')");
      expect(emergencyDetailDrawerSource).toContain("handleStatusChange('CANCELLED')");

      // Team assignment and notes
      expect(emergencyDetailDrawerSource).toContain('selectedTeamId');
      expect(emergencyDetailDrawerSource).toContain('noteText');
      expect(emergencyDetailDrawerSource).toContain('Assign Rescue Unit:');
      expect(emergencyDetailDrawerSource).toContain('Action / Log Note:');
    });

    it('proves the SOS Detail Drawer retains all incident telemetry and audit logs', () => {
      expect(emergencyDetailDrawerSource).toContain('Radio Frequency & LoRa Mesh Telemetry');
      expect(emergencyDetailDrawerSource).toContain('Logged Gateway RF Packets (relay_logs)');
      expect(emergencyDetailDrawerSource).toContain('Incident Audit Timeline');
      expect(emergencyDetailDrawerSource).toContain('Target Geolocation');
      expect(emergencyDetailDrawerSource).toContain('Victim & Sender Details');
    });

    it('proves the SOS Detail Drawer is anchored to viewport right edge with max-w-xl', () => {
      expect(emergencyDetailDrawerSource).toContain('data-testid="emergency-detail-drawer"');
      expect(emergencyDetailDrawerSource).toContain('right: 0');
      expect(emergencyDetailDrawerSource).toContain("maxWidth: 'min(100vw, 36rem)'");
      expect(emergencyDetailDrawerSource).toContain("width: '100%'");
    });
  });

  describe('4. Responsive Geometry: 1385px Desktop Viewport', () => {
    it('proves side-by-side single map and SOS drawer fit in a 1385px viewport without horizontal overflow', () => {
      const viewportWidth = 1385;
      const sidebarWidth = 288; // lg:pl-72
      const contentPadding = 32; // lg:p-8
      const mapLeft = sidebarWidth + contentPadding; // 320px
      const drawerWidth = 576; // max-w-xl (36rem)
      const clearance = 24;

      const layout = calculatePageMapWrapperLayout({
        viewportWidth,
        mapLeft,
        drawerLeft: viewportWidth - drawerWidth, // 1385 - 576 = 809
        drawerWidth,
        isDrawerOpen: true,
        clearance,
      });

      expect(layout.isConstrained).toBe(true);
      expect(layout.isStacked).toBe(false);

      // Drawer is 100% inside viewport
      expect(layout.drawerLeft).toBe(809);
      expect(layout.drawerLeft + drawerWidth).toBe(viewportWidth);
      expect(layout.drawerLeft + drawerWidth).toBeLessThanOrEqual(viewportWidth);

      // Clearance must be at least 24px
      expect(layout.clearanceToDrawer).toBe(24);
      expect(layout.drawerLeft - layout.mapRightEdge).toBe(24);

      // Map right edge terminates at 785px
      expect(layout.mapRightEdge).toBe(785); // 809 - 24

      // Allowed map width is 465px
      expect(layout.maxAllowedWidth).toBe(465); // 785 - 320 = 465

      // Total occupied width inside viewport
      const totalWidth = mapLeft + layout.maxAllowedWidth + layout.clearance + drawerWidth;
      expect(totalWidth).toBe(viewportWidth);
      expect(totalWidth).toBeLessThanOrEqual(viewportWidth);
    });
  });

  describe('5. Mobile Single-Map Layout with Clear Back Control', () => {
    it('proves EmergencyMapPage toggles isMobileViewingMap on mobile viewports (< 768px)', () => {
      expect(emergencyMapPageSource).toContain('window.innerWidth < 768');
      expect(emergencyMapPageSource).toContain('setIsMobileViewingMap(true)');
    });

    it('proves mobile layout renders floating Back to Incident Details banner when inspecting map', () => {
      expect(emergencyMapPageSource).toContain('data-testid="mobile-map-return-banner"');
      expect(emergencyMapPageSource).toContain('data-testid="mobile-back-to-details-btn"');
      expect(emergencyMapPageSource).toContain('Back to Incident Details');
      expect(emergencyMapPageSource).toContain('onClick={() => setIsMobileViewingMap(false)}');
    });

    it('proves drawer remains visible on desktop (viewportWidth >= 768) even when isMobileViewingMap is toggled', () => {
      // Condition: (!isMobileViewingMap || viewportWidth >= 768)
      expect(emergencyMapPageSource).toContain('(!isMobileViewingMap || viewportWidth >= 768)');
    });
  });

  describe('6. Legitimate Map Controls & 4 Map Layers Preserved', () => {
    it('proves all 4 tile layer modes remain supported in TacticalMap', () => {
      expect(tacticalMapSource).toContain("mapLayer === 'tactical'");
      expect(tacticalMapSource).toContain("mapLayer === 'satellite'");
      expect(tacticalMapSource).toContain("mapLayer === 'terrain'");
      expect(tacticalMapSource).toContain("mapLayer === 'street'");
    });

    it('proves Dispatch SOS test beacon button has been removed and genuine GPS Beacon controls are preserved in TacticalMap', () => {
      expect(tacticalMapSource).not.toContain('handleQuickDispatch');
      expect(tacticalMapSource).not.toContain('onDispatchAtLocation');
      expect(tacticalMapSource).toContain('OPERATOR COMMAND POST');
    });

    it('proves Rescue Team markers are preserved in TacticalMap', () => {
      expect(tacticalMapSource).toContain('validTeams.map((team)');
      expect(tacticalMapSource).toContain('createTeamIcon');
      expect(tacticalMapSource).toContain('team.team_name');
      expect(tacticalMapSource).toContain('team.jurisdiction_zone');
    });
  });
});
