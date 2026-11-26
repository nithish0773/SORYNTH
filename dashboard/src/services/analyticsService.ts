import type { Emergency } from '../types';

export interface DailyTrendPoint {
  date: string;
  total: number;
  active: number;
  resolved: number;
}

export interface CategoryBreakdown {
  name: string;
  count: number;
  color: string;
}

export interface MethodBreakdown {
  name: string;
  count: number;
  color: string;
}

export class AnalyticsService {
  /**
   * Aggregates emergencies into daily trend points for the past N days
   */
  static getDailyTrends(emergencies: Emergency[], days = 14): DailyTrendPoint[] {
    const pointsMap = new Map<string, { total: number; active: number; resolved: number }>();

    // Initialize all past N days with 0
    const now = new Date();
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date();
      d.setDate(now.getDate() - i);
      const key = d.toISOString().split('T')[0];
      pointsMap.set(key, { total: 0, active: 0, resolved: 0 });
    }

    // Populate with real emergency counts
    for (const em of emergencies) {
      const dateKey = em.created_at.split('T')[0];
      if (pointsMap.has(dateKey)) {
        const item = pointsMap.get(dateKey)!;
        item.total++;
        if (em.status === 'RESOLVED') {
          item.resolved++;
        } else if (em.status !== 'CANCELLED' && em.status !== 'FAILED') {
          item.active++;
        }
      }
    }

    return Array.from(pointsMap.entries()).map(([date, data]) => ({
      date: new Date(date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
      ...data,
    }));
  }

  /**
   * Aggregates emergency category distribution
   */
  static getCategoryBreakdown(emergencies: Emergency[]): CategoryBreakdown[] {
    const counts: Record<string, number> = {
      MEDICAL: 0,
      ACCIDENT: 0,
      FIRE: 0,
      NATURAL_DISASTER: 0,
      LOST_STRANDED: 0,
      OTHER: 0,
    };

    for (const em of emergencies) {
      if (counts[em.emergency_type] !== undefined) {
        counts[em.emergency_type]++;
      } else {
        counts.OTHER++;
      }
    }

    const colors: Record<string, string> = {
      MEDICAL: '#ef4444', // Red
      ACCIDENT: '#f59e0b', // Amber
      FIRE: '#f97316', // Orange
      NATURAL_DISASTER: '#8b5cf6', // Violet
      LOST_STRANDED: '#06b6d4', // Cyan
      OTHER: '#64748b', // Slate
    };

    const labels: Record<string, string> = {
      MEDICAL: 'Medical',
      ACCIDENT: 'Accident',
      FIRE: 'Fire Alert',
      NATURAL_DISASTER: 'Disaster',
      LOST_STRANDED: 'Lost / Stranded',
      OTHER: 'Other Urgent',
    };

    return Object.entries(counts).map(([type, count]) => ({
      name: labels[type] || type,
      count,
      color: colors[type] || '#64748b',
    })).filter(c => c.count > 0 || emergencies.length === 0);
  }

  /**
   * Aggregates communication methods breakdown
   */
  static getMethodBreakdown(emergencies: Emergency[]): MethodBreakdown[] {
    const counts: Record<string, number> = {
      INTERNET: 0,
      BLUETOOTH_LORA: 0,
      LORA_RELAY: 0,
      HYBRID: 0,
    };

    for (const em of emergencies) {
      if (counts[em.communication_method] !== undefined) {
        counts[em.communication_method]++;
      }
    }

    const labels: Record<string, string> = {
      INTERNET: 'Cellular / Wi-Fi',
      BLUETOOTH_LORA: 'BLE ESP32 Direct',
      LORA_RELAY: 'LoRa Mesh Relay',
      HYBRID: 'Hybrid Failover',
    };

    const colors: Record<string, string> = {
      INTERNET: '#0ea5e9', // Sky blue
      BLUETOOTH_LORA: '#00e5ff', // Electric cyan
      LORA_RELAY: '#10b981', // Emerald
      HYBRID: '#a855f7', // Purple
    };

    return Object.entries(counts).map(([method, count]) => ({
      name: labels[method] || method,
      count,
      color: colors[method] || '#64748b',
    }));
  }

  /**
   * Generates a downloadable CSV string of emergencies
   */
  static exportToCsv(emergencies: Emergency[]): string {
    const headers = [
      'Emergency Code',
      'Status',
      'Type',
      'Sender Name',
      'Sender Phone',
      'Is Guest',
      'Latitude',
      'Longitude',
      'Accuracy (m)',
      'Communication Method',
      'Hop Count',
      'Message',
      'Created At',
      'Acknowledged At',
      'Resolved At'
    ];

    const rows = emergencies.map(e => [
      e.emergency_code,
      e.status,
      e.emergency_type,
      `"${(e.sender_name || '').replace(/"/g, '""')}"`,
      `"${e.sender_phone || ''}"`,
      e.is_guest ? 'Yes' : 'No',
      e.latitude,
      e.longitude,
      e.accuracy_meters ?? '',
      e.communication_method,
      e.hop_count,
      `"${(e.custom_message || '').replace(/"/g, '""')}"`,
      e.created_at,
      e.acknowledged_at || '',
      e.resolved_at || ''
    ]);

    return [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
  }
}

