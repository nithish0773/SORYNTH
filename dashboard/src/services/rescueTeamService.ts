import { supabase } from './supabaseClient';
import { parseCoordinate } from '../utils/coordinateUtils';
import type { RescueTeam, RescueTeamStatus } from '../types';

export class RescueTeamService {
  /**
   * Fetches all registered rescue teams from Supabase
   */
  static async getRescueTeams(): Promise<RescueTeam[]> {
    try {
      const { data, error } = await supabase
        .from('rescue_teams')
        .select('*')
        .order('team_name', { ascending: true });

      if (error) {
        console.warn('Error querying rescue_teams:', error.message);
        throw error;
      }

      return (data as RescueTeam[]) || [];
    } catch (err) {
      console.error('Failed to get rescue teams:', err);
      return [];
    }
  }

  /**
   * Registers a new rescue team in Supabase
   */
  static async createRescueTeam(team: {
    team_name: string;
    jurisdiction_zone: string;
    contact_phone: string;
    status: RescueTeamStatus;
    latitude?: number;
    longitude?: number;
  }): Promise<RescueTeam> {
    try {
      const parsed = parseCoordinate(team.latitude, team.longitude);
      const { data, error } = await supabase
        .from('rescue_teams')
        .insert({
          team_name: team.team_name,
          jurisdiction_zone: team.jurisdiction_zone,
          contact_phone: team.contact_phone,
          status: team.status,
          latitude: parsed ? parsed.latitude : null,
          longitude: parsed ? parsed.longitude : null,
        })
        .select()
        .single();

      if (error) throw error;
      return data as RescueTeam;
    } catch (err) {
      console.error('Failed to create rescue team:', err);
      throw err;
    }
  }

  /**
   * Updates a rescue team's readiness status.
   * Uses dedicated operator_set_team_readiness RPC for operators, falling back to direct update for Super Admin.
   */
  static async updateTeamStatus(teamId: string, status: RescueTeamStatus): Promise<boolean> {
    try {
      // 1. Try dedicated operator readiness RPC
      const { data: rpcRes, error: rpcErr } = await supabase.rpc('operator_set_team_readiness', {
        p_team_id: teamId,
        p_status: status,
      });

      if (!rpcErr && (rpcRes as { success?: boolean })?.success !== false) {
        return true;
      }

      // 2. Direct table update fallback (Super Admin)
      const { error } = await supabase
        .from('rescue_teams')
        .update({ status })
        .eq('id', teamId);

      if (error) throw error;
      return true;
    } catch (err) {
      console.error('Failed to update team status:', err);
      throw err;
    }
  }

  /**
   * Realtime subscription for rescue teams table
   */
  static subscribeToTeams(onChange: () => void) {
    const channel = supabase
      .channel('command_teams_realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rescue_teams' },
        () => onChange()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }
}

