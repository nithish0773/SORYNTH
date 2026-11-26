import { supabase } from './supabaseClient';
import { OperatorService } from './operatorService';
import { parseCoordinate } from '../utils/coordinateUtils';
import type { Emergency, EmergencyUpdate, EmergencyStatus, KpiStats, EmergencyFilterOptions, RelayLog } from '../types';

export class EmergencyService {
  /**
   * Fetches all emergencies from Supabase with assigned team info
   */
  static async getEmergencies(filters?: Partial<EmergencyFilterOptions>): Promise<Emergency[]> {
    try {
      let query = supabase
        .from('emergencies')
        .select(`
          *,
          assigned_team:rescue_teams(*)
        `);

      // Apply search query
      if (filters?.searchQuery && filters.searchQuery.trim() !== '') {
        const q = filters.searchQuery.trim();
        query = query.or(`emergency_code.ilike.%${q}%,sender_name.ilike.%${q}%,sender_phone.ilike.%${q}%,custom_message.ilike.%${q}%`);
      }

      // Apply status filter
      if (filters?.status && filters.status !== 'ALL') {
        if (filters.status === 'RECEIVED') {
          query = query.in('status', ['PENDING', 'STORED', 'TRANSMITTING', 'RELAYED', 'DELIVERED']);
        } else if (filters.status === 'RESPONDING') {
          query = query.eq('status', 'IN_ACTION');
        } else {
          query = query.eq('status', filters.status);
        }
      }

      // Apply emergency type filter
      if (filters?.emergencyType && filters.emergencyType !== 'ALL') {
        query = query.eq('emergency_type', filters.emergencyType);
      }

      // Apply communication method filter
      if (filters?.communicationMethod && filters.communicationMethod !== 'ALL') {
        query = query.eq('communication_method', filters.communicationMethod);
      }

      // Apply guest filter
      if (filters?.isGuest && filters.isGuest !== 'ALL') {
        query = query.eq('is_guest', filters.isGuest === 'GUEST');
      }

      // Apply sorting
      if (filters?.sortBy === 'created_at_asc') {
        query = query.order('created_at', { ascending: true });
      } else {
        query = query.order('created_at', { ascending: false });
      }

      const { data, error } = await query;

      if (error) {
        console.warn('Emergencies fetch error:', error.message);
        throw error;
      }

      return (data as Emergency[]) || [];
    } catch (err) {
      console.error('Failed to get emergencies:', err);
      throw err;
    }
  }

  /**
   * Fetches a single emergency by ID with full timeline updates and associated LoRa relay logs
   */
  static async getEmergencyById(id: string): Promise<{ emergency: Emergency; updates: EmergencyUpdate[]; relayLogs: RelayLog[] }> {
    try {
      const { data: emergency, error: emergencyError } = await supabase
        .from('emergencies')
        .select(`
          *,
          assigned_team:rescue_teams(*)
        `)
        .eq('id', id)
        .single();

      if (emergencyError) throw emergencyError;

      const { data: updates, error: updatesError } = await supabase
        .from('emergency_updates')
        .select('*')
        .eq('emergency_id', id)
        .order('created_at', { ascending: true });

      if (updatesError) {
        console.warn('Could not fetch emergency updates:', updatesError.message);
      }

      const { data: relayLogs, error: relayLogsError } = await supabase
        .from('relay_logs')
        .select('*')
        .eq('emergency_id', id)
        .order('received_at', { ascending: false });

      if (relayLogsError) {
        console.warn('Could not fetch emergency relay logs:', relayLogsError.message);
      }

      return {
        emergency: emergency as Emergency,
        updates: (updates as EmergencyUpdate[]) || [],
        relayLogs: (relayLogs as RelayLog[]) || [],
      };
    } catch (err) {
      console.error('Error fetching emergency details:', err);
      throw err;
    }
  }

  /**
   * Updates an emergency status with audit logging.
   * Tries the secure operator RPC first, falling back to direct table update.
   */
  static async updateStatus(
    emergencyId: string,
    newStatus: EmergencyStatus,
    note?: string,
    assignedTeamId?: string
  ): Promise<boolean> {
    try {
      // 1. Try dedicated operator RPC function
      const { data: rpcRes, error: rpcError } = await supabase.rpc('update_emergency_status_operator', {
        p_emergency_id: emergencyId,
        p_new_status: newStatus,
        p_note: note || `Status updated to ${newStatus}`,
        p_assigned_team_id: assignedTeamId || null,
      });

      if (!rpcError && rpcRes?.success) {
        return true;
      }

      // 2. Fallback to direct table update if RPC not installed
      const updatePayload: Partial<Emergency> = {
        status: newStatus,
        updated_at: new Date().toISOString(),
      };

      if (newStatus === 'ACKNOWLEDGED') {
        updatePayload.acknowledged_at = new Date().toISOString();
      } else if (newStatus === 'RESOLVED') {
        updatePayload.resolved_at = new Date().toISOString();
      }

      if (assignedTeamId) {
        updatePayload.assigned_team_id = assignedTeamId;
      }

      const { error: updateErr } = await supabase
        .from('emergencies')
        .update(updatePayload)
        .eq('id', emergencyId);

      if (updateErr) throw updateErr;

      // Log update note in emergency_updates
      const user = (await supabase.auth.getUser()).data.user;
      await supabase.from('emergency_updates').insert({
        emergency_id: emergencyId,
        new_status: newStatus,
        note: note || `Status changed to ${newStatus} by command operator`,
        updated_by_user_id: user?.id || null,
      });

      // Record immutable audit event
      const actionType = newStatus === 'ACKNOWLEDGED' 
        ? 'SOS_ACCEPTED' 
        : newStatus === 'RESOLVED' 
        ? 'EMERGENCY_RESOLVED' 
        : assignedTeamId 
        ? 'EMERGENCY_ASSIGNED' 
        : 'STATUS_CHANGED';

      await OperatorService.logAuditEvent(actionType, 'EMERGENCY', emergencyId, {
        new_status: newStatus,
        note: note || `Status changed to ${newStatus}`,
        assigned_team_id: assignedTeamId || null,
      });

      return true;
    } catch (err) {
      console.error('Failed to update emergency status:', err);
      throw err;
    }
  }

  /**
   * Assigns a rescue team to an emergency
   */
  static async assignTeam(emergencyId: string, teamId: string, note?: string): Promise<boolean> {
    try {
      const { error } = await supabase
        .from('emergencies')
        .update({
          assigned_team_id: teamId,
          status: 'IN_ACTION',
          updated_at: new Date().toISOString(),
        })
        .eq('id', emergencyId);

      if (error) throw error;

      const user = (await supabase.auth.getUser()).data.user;
      await supabase.from('emergency_updates').insert({
        emergency_id: emergencyId,
        new_status: 'IN_ACTION',
        note: note || `Assigned to rescue team`,
        updated_by_user_id: user?.id || null,
      });

      return true;
    } catch (err) {
      console.error('Failed to assign team:', err);
      throw err;
    }
  }

  /**
   * Creates an emergency record in the Supabase backend.
   * Strictly enforces genuine records: throws on database/network error without fabricating fallback beacons.
   */
  static async createEmergency(payload: Partial<Emergency>): Promise<Emergency> {
    const code = payload.emergency_code || `SOS-${Math.floor(1000 + Math.random() * 9000)}`;
    const parsedCoords = parseCoordinate(payload.latitude, payload.longitude);
    const newEmergency = {
      ...payload,
      emergency_code: code,
      emergency_type: payload.emergency_type || 'OTHER',
      status: payload.status || 'PENDING',
      latitude: parsedCoords ? parsedCoords.latitude : null,
      longitude: parsedCoords ? parsedCoords.longitude : null,
      accuracy_meters: typeof payload.accuracy_meters === 'number' ? payload.accuracy_meters : null,
      communication_method: payload.communication_method || 'INTERNET',
      sender_name: payload.sender_name || null,
      sender_phone: payload.sender_phone || null,
      custom_message: payload.custom_message || null,
      is_guest: payload.is_guest ?? false,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await supabase
      .from('emergencies')
      .insert(newEmergency)
      .select(`
        *,
        assigned_team:rescue_teams(*)
      `)
      .single();

    if (error) {
      console.error('Failed to create emergency record in Supabase:', error.message);
      throw error;
    }
    return data as Emergency;
  }

  /**
   * Calculates KPI stats from actual backend data
   */
  static calculateKpis(emergencies: Emergency[], teamsCount: number, relayNodesCount: number): KpiStats {
    const total = emergencies.length;
    let active = 0;
    let resolved = 0;
    let totalResponseTimeMs = 0;
    let responseCount = 0;

    for (const em of emergencies) {
      if (em.status === 'RESOLVED') {
        resolved++;
      } else if (em.status !== 'CANCELLED' && em.status !== 'FAILED') {
        active++;
      }

      // Calculate response time from created_at to acknowledged_at (or resolved_at)
      if (em.acknowledged_at) {
        const created = new Date(em.created_at).getTime();
        const acked = new Date(em.acknowledged_at).getTime();
        if (acked >= created) {
          totalResponseTimeMs += (acked - created);
          responseCount++;
        }
      }
    }

    const avgMinutes = responseCount > 0 
      ? Math.round(totalResponseTimeMs / responseCount / 60000 * 10) / 10 
      : 0;

    return {
      activeEmergencies: active,
      totalEmergencies: total,
      resolvedEmergencies: resolved,
      availableRescueTeams: teamsCount,
      verifiedRelayNodes: relayNodesCount,
      averageResponseTimeMinutes: avgMinutes,
    };
  }

  /**
   * Subscribes to real-time events for emergencies
   */
  static subscribeToEmergencies(
    onInsert: (emergency: Emergency) => void,
    onUpdate: (emergency: Emergency) => void,
    onDelete: (id: string) => void
  ) {
    const channel = supabase
      .channel('command_emergencies_realtime')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'emergencies' },
        (payload) => onInsert(payload.new as Emergency)
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'emergencies' },
        (payload) => onUpdate(payload.new as Emergency)
      )
      .on(
        'postgres_changes',
        { event: 'DELETE', schema: 'public', table: 'emergencies' },
        (payload) => onDelete(payload.old.id)
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }
}

