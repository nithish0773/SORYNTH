import React from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertCircle, RefreshCw } from 'lucide-react';
import { EmergencyFilterBar } from '../components/emergencies/EmergencyFilterBar';
import { EmergencyTable } from '../components/emergencies/EmergencyTable';
import { EmergencyDetailDrawer } from '../components/emergencies/EmergencyDetailDrawer';
import { EmptyState } from '../components/common/EmptyState';
import { useEmergencies } from '../context/EmergencyContext';

export const LiveEmergenciesPage: React.FC = () => {
  const { 
    filteredEmergencies, 
    emergencies, 
    selectedEmergency, 
    setSelectedEmergency, 
    isLoading,
    refreshAll 
  } = useEmergencies();
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      {/* Page Title & Stats */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-[20px] border border-slate-200/90 dark:border-white/[0.1] bg-white dark:bg-[#161619] shadow-sm dark:shadow-md">
        <div>
          <h2 className="text-lg font-bold text-slate-900 dark:text-white tracking-tight flex items-center gap-2">
            <span className="w-8 h-8 rounded-full bg-ios-red/15 flex items-center justify-center text-ios-red">
              <AlertCircle className="w-4 h-4" />
            </span>
            Live Emergency Incident Registry
          </h2>
          <p className="text-xs text-slate-600 dark:text-[#a1a1a6] mt-1 font-normal">
            Active and archived distress calls synchronized from citizen devices via cellular and off-grid LoRa mesh.
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          <button
            onClick={() => refreshAll()}
            disabled={isLoading}
            className="inline-flex items-center gap-1.5 px-4 py-2 rounded-full bg-slate-100 hover:bg-slate-200 dark:bg-white/[0.08] dark:hover:bg-white/[0.14] text-slate-700 dark:text-white border border-black/[0.06] dark:border-white/[0.08] text-xs font-medium transition-all active:scale-95"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Filter Bar */}
      <EmergencyFilterBar />

      {/* Table or Empty State */}
      {filteredEmergencies.length === 0 ? (
        <EmptyState
          type="emergencies"
          title={emergencies.length === 0 ? "NO SOS ALERTS LOGGED IN BACKEND" : "NO MATCHING INCIDENTS FOUND"}
          description={
            emergencies.length === 0
              ? "The public.emergencies table is currently empty. Incoming alerts submitted via the SORYNTH mobile app will appear automatically via Realtime."
              : "No emergency records matched the current filter criteria. Try adjusting or clearing search filters."
          }
        />
      ) : (
        <EmergencyTable
          emergencies={filteredEmergencies}
          onSelectEmergency={setSelectedEmergency}
          selectedId={selectedEmergency?.id}
        />
      )}

      {/* Slide-over Detail Drawer */}
      <EmergencyDetailDrawer
        emergency={selectedEmergency}
        onClose={() => setSelectedEmergency(null)}
        onViewOnMap={(em) => {
          setSelectedEmergency(em);
          navigate('/map');
        }}
      />
    </div>
  );
};
