import React from 'react';
import { LoraRelayDashboard } from '../components/network/LoraRelayDashboard';

export const RelayNetworkPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <LoraRelayDashboard />
    </div>
  );
};

