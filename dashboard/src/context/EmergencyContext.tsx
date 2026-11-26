import React, { createContext, useContext, useEffect, useState, useCallback, useMemo } from 'react';
import type { Emergency, RescueTeam, KpiStats, EmergencyStatus, EmergencyFilterOptions } from '../types';
import { EmergencyService } from '../services/emergencyService';
import { RescueTeamService } from '../services/rescueTeamService';
import { LoraService, type LoraNetworkStatus } from '../services/loraService';
import { LoraAdapter } from '../services/loraAdapter';

interface EmergencyContextType {
  emergencies: Emergency[];
  filteredEmergencies: Emergency[];
  rescueTeams: RescueTeam[];
  loraStatus: LoraNetworkStatus;
  kpis: KpiStats;
  isLoading: boolean;
  isBackendConnected: boolean;
  errorMessage: string | null;
  selectedEmergency: Emergency | null;
  filters: EmergencyFilterOptions;
  soundAlertEnabled: boolean;
  setSoundAlertEnabled: (enabled: boolean) => void;
  setSelectedEmergency: (emergency: Emergency | null) => void;
  setFilters: React.Dispatch<React.SetStateAction<EmergencyFilterOptions>>;
  updateEmergencyStatus: (id: string, status: EmergencyStatus, note?: string, teamId?: string) => Promise<boolean>;
  assignTeam: (emergencyId: string, teamId: string, note?: string) => Promise<boolean>;
  refreshAll: () => Promise<void>;
}

const defaultFilters: EmergencyFilterOptions = {
  searchQuery: '',
  status: 'ALL',
  emergencyType: 'ALL',
  communicationMethod: 'ALL',
  isGuest: 'ALL',
  sortBy: 'created_at_desc',
};

const EmergencyContext = createContext<EmergencyContextType | undefined>(undefined);

// Web Audio API emergency alert sound generator
const playTacticalAlarm = () => {
  try {
    const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();

    // Oscillators for tactical two-tone emergency chime
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(880, ctx.currentTime); // A5
    osc.frequency.setValueAtTime(1174.66, ctx.currentTime + 0.15); // D6
    osc.frequency.setValueAtTime(880, ctx.currentTime + 0.3);

    gain.gain.setValueAtTime(0.2, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start();
    osc.stop(ctx.currentTime + 0.5);
  } catch (e) {
    console.debug('Audio play blocked or unavailable:', e);
  }
};

export const EmergencyProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [emergencies, setEmergencies] = useState<Emergency[]>([]);
  const [rescueTeams, setRescueTeams] = useState<RescueTeam[]>([]);
  const [loraStatus, setLoraStatus] = useState<LoraNetworkStatus>({
    isHardwarePending: true,
    gatewayConnected: false,
    totalPackets: 0,
    activeNodesCount: 0,
    averageRssi: null,
    averageSnr: null,
    nodes: [],
    recentLogs: [],
  });
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isBackendConnected, setIsBackendConnected] = useState<boolean>(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [selectedEmergency, setSelectedEmergency] = useState<Emergency | null>(null);
  const [filters, setFilters] = useState<EmergencyFilterOptions>(defaultFilters);
  const [soundAlertEnabled, setSoundAlertEnabled] = useState<boolean>(() => {
    return localStorage.getItem('sorynth_sound_enabled') === 'true';
  });

  const handleSetSoundAlert = (enabled: boolean) => {
    setSoundAlertEnabled(enabled);
    localStorage.setItem('sorynth_sound_enabled', enabled ? 'true' : 'false');
  };

  const loadData = useCallback(async () => {
    await Promise.resolve();
    setIsLoading(true);
    setErrorMessage(null);
    try {
      // 1. Fetch genuine emergencies from Supabase
      const fetchedEmergencies = await EmergencyService.getEmergencies();
      setEmergencies(fetchedEmergencies);
      setIsBackendConnected(true);

      // 2. Fetch rescue teams
      const fetchedTeams = await RescueTeamService.getRescueTeams();
      setRescueTeams(fetchedTeams);

      // 3. Fetch LoRa relay logs and analyze network state via genuine LoraAdapter
      const logs = await LoraService.getRelayLogs();
      const analyzed = LoraAdapter.analyze(logs);
      setLoraStatus({
        ...analyzed,
        recentLogs: logs,
      });

    } catch (err: unknown) {
      const errorObj = typeof err === 'object' && err !== null ? (err as Record<string, unknown>) : {};
      const msg = typeof errorObj.message === 'string'
        ? errorObj.message
        : err instanceof Error
        ? err.message
        : 'Error connecting to database';
      const code = typeof errorObj.code === 'string' ? errorObj.code : '';
      console.warn('Backend data load notice:', msg, code);
      if (msg.includes('permission denied') || code === '42501') {
        setErrorMessage('Database RLS active: Operator permissions required. Run rbac_schema_setup.sql in Supabase SQL Editor.');
      } else {
        setErrorMessage(msg);
      }
      setIsBackendConnected(false);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();

    // Realtime subscriptions
    const unsubscribeEmergencies = EmergencyService.subscribeToEmergencies(
      (newEmergency) => {
        setEmergencies((prev) => [newEmergency, ...prev]);
        if (soundAlertEnabled) {
          playTacticalAlarm();
        }
      },
      (updatedEmergency) => {
        setEmergencies((prev) =>
          prev.map((e) => (e.id === updatedEmergency.id ? updatedEmergency : e))
        );
        setSelectedEmergency((current) =>
          current && current.id === updatedEmergency.id ? updatedEmergency : current
        );
      },
      (deletedId) => {
        setEmergencies((prev) => prev.filter((e) => e.id !== deletedId));
        setSelectedEmergency((current) => (current && current.id === deletedId ? null : current));
      }
    );

    const unsubscribeTeams = RescueTeamService.subscribeToTeams(() => {
      RescueTeamService.getRescueTeams().then(setRescueTeams);
    });

    const unsubscribeLogs = LoraService.subscribeToRelayLogs(() => {
      LoraService.getRelayLogs().then((logs) => {
        const analyzed = LoraAdapter.analyze(logs);
        setLoraStatus({
          ...analyzed,
          recentLogs: logs,
        });
      });
    });

    return () => {
      unsubscribeEmergencies();
      unsubscribeTeams();
      unsubscribeLogs();
    };
  }, [loadData, soundAlertEnabled]);

  // Status updates
  const updateEmergencyStatus = async (
    id: string,
    status: EmergencyStatus,
    note?: string,
    teamId?: string
  ): Promise<boolean> => {
    try {
      const success = await EmergencyService.updateStatus(id, status, note, teamId);
      if (success) {
        setEmergencies((prev) =>
          prev.map((e) => (e.id === id ? { ...e, status, updated_at: new Date().toISOString() } : e))
        );
        return true;
      }
      return false;
    } catch (err) {
      console.error('Update status error:', err);
      throw err;
    }
  };

  // Team assignment
  const assignTeam = async (emergencyId: string, teamId: string, note?: string): Promise<boolean> => {
    try {
      const success = await EmergencyService.assignTeam(emergencyId, teamId, note);
      if (success) {
        setEmergencies((prev) =>
          prev.map((e) => (e.id === emergencyId ? { ...e, assigned_team_id: teamId, status: 'IN_ACTION' } : e))
        );
        return true;
      }
      return false;
    } catch (err) {
      console.error('Assign team error:', err);
      throw err;
    }
  };

  // Filtered emergencies
  const filteredEmergencies = useMemo(() => {
    return emergencies.filter((em) => {
      // Search
      if (filters.searchQuery.trim() !== '') {
        const q = filters.searchQuery.toLowerCase();
        const matchCode = em.emergency_code.toLowerCase().includes(q);
        const matchName = (em.sender_name || '').toLowerCase().includes(q);
        const matchPhone = (em.sender_phone || '').includes(q);
        const matchMsg = (em.custom_message || '').toLowerCase().includes(q);
        if (!matchCode && !matchName && !matchPhone && !matchMsg) return false;
      }

      // Status
      if (filters.status !== 'ALL') {
        if (filters.status === 'RECEIVED') {
          if (!['PENDING', 'STORED', 'TRANSMITTING', 'RELAYED', 'DELIVERED'].includes(em.status)) return false;
        } else if (filters.status === 'RESPONDING') {
          if (em.status !== 'IN_ACTION') return false;
        } else if (em.status !== filters.status) {
          return false;
        }
      }

      // Emergency Type
      if (filters.emergencyType !== 'ALL' && em.emergency_type !== filters.emergencyType) {
        return false;
      }

      // Communication Method
      if (filters.communicationMethod !== 'ALL' && em.communication_method !== filters.communicationMethod) {
        return false;
      }

      // Guest / Registered
      if (filters.isGuest !== 'ALL') {
        if (filters.isGuest === 'GUEST' && !em.is_guest) return false;
        if (filters.isGuest === 'REGISTERED' && em.is_guest) return false;
      }

      return true;
    }).sort((a, b) => {
      if (filters.sortBy === 'created_at_asc') {
        return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
      }
      if (filters.sortBy === 'status') {
        return a.status.localeCompare(b.status);
      }
      if (filters.sortBy === 'type') {
        return a.emergency_type.localeCompare(b.emergency_type);
      }
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });
  }, [emergencies, filters]);

  // Dynamic KPIs from actual Supabase data
  const kpis = useMemo(() => {
    return EmergencyService.calculateKpis(
      emergencies,
      rescueTeams.length,
      loraStatus.activeNodesCount
    );
  }, [emergencies, rescueTeams, loraStatus]);

  return (
    <EmergencyContext.Provider
      value={{
        emergencies,
        filteredEmergencies,
        rescueTeams,
        loraStatus,
        kpis,
        isLoading,
        isBackendConnected,
        errorMessage,
        selectedEmergency,
        filters,
        soundAlertEnabled,
        setSoundAlertEnabled: handleSetSoundAlert,
        setSelectedEmergency,
        setFilters,
        updateEmergencyStatus,
        assignTeam,
        refreshAll: loadData,
      }}
    >
      {children}
    </EmergencyContext.Provider>
  );
};

export const useEmergencies = () => {
  const context = useContext(EmergencyContext);
  if (!context) {
    throw new Error('useEmergencies must be used within an EmergencyProvider');
  }
  return context;
};
