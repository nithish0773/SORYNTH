import React from 'react';
import { KpiGrid } from '../components/dashboard/KpiGrid';
import { RecentSosTable } from '../components/dashboard/RecentSosTable';
import { CategoryChart } from '../components/dashboard/CategoryChart';
import { StatusChart } from '../components/dashboard/StatusChart';
import { CommStatusWidget } from '../components/dashboard/CommStatusWidget';
import { SystemActivityTimeline } from '../components/dashboard/SystemActivityTimeline';
import { EmergencyDetailDrawer } from '../components/emergencies/EmergencyDetailDrawer';
import { useEmergencies } from '../context/EmergencyContext';
import { useNavigate } from 'react-router-dom';

export const OverviewPage: React.FC = () => {
  const { selectedEmergency, setSelectedEmergency } = useEmergencies();
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      {/* 6 Key Performance Indicator Cards */}
      <KpiGrid />

      {/* Main Grid: Live Emergency Feed & System Activity */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <RecentSosTable onSelectEmergency={setSelectedEmergency} />
        </div>
        <div className="lg:col-span-1">
          <SystemActivityTimeline />
        </div>
      </div>

      {/* Charts Grid: Categories & Lifecycle Status */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <CategoryChart />
        <StatusChart />
      </div>

      {/* Communication Health & Protocol Monitoring */}
      <CommStatusWidget />

      {/* Slide-over Detail Drawer */}
      <EmergencyDetailDrawer
        emergency={selectedEmergency}
        onClose={() => setSelectedEmergency(null)}
        onViewOnMap={(em) => {
          setSelectedEmergency(em);
          navigate('/admin/map');
        }}
      />
    </div>
  );
};

