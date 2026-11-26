import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider } from './context/ThemeContext';
import { AuthProvider, useAuth } from './context/AuthContext';
import { EmergencyProvider } from './context/EmergencyContext';
import { ProtectedRoute } from './components/common/ProtectedRoute';
import { DashboardLayout } from './components/layout/DashboardLayout';

// Public Auth Page
import { LoginPage } from './pages/LoginPage';

// Super Admin Pages
import { OverviewPage } from './pages/OverviewPage';
import { ManageOperatorsPage } from './pages/admin/ManageOperatorsPage';
import { ManageGatewaysPage } from './pages/admin/ManageGatewaysPage';
import { AdminProfilePage } from './pages/admin/AdminProfilePage';
import { LiveEmergenciesPage } from './pages/LiveEmergenciesPage';
import { EmergencyMapPage } from './pages/EmergencyMapPage';
import { RelayNetworkPage } from './pages/RelayNetworkPage';
import { CommMonitorPage } from './pages/CommMonitorPage';
import { RescueTeamsPage } from './pages/RescueTeamsPage';
import { AnalyticsPage } from './pages/AnalyticsPage';
import { SettingsPage } from './pages/SettingsPage';

// Rescue Operator Pages
import { OperatorDashboardPage } from './pages/operator/OperatorDashboardPage';
import { OperatorProfilePage } from './pages/operator/OperatorProfilePage';
import { OperatorTeamsPage } from './pages/operator/OperatorTeamsPage';

/**
 * Intelligent Entry Route: Directs authenticated user to their role-specific dashboard
 */
const RootRoleRedirect: React.FC = () => {
  const { user, systemRole, isLoading } = useAuth();

  if (isLoading) {
    return <div className="min-h-screen bg-[#f2f2f7] dark:bg-black transition-colors" />;
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  if (systemRole === 'SUPER_ADMIN') {
    return <Navigate to="/admin" replace />;
  }

  return <Navigate to="/operator" replace />;
};

/**
 * Role-Aware Legacy Redirect: Directs users based on their active clearance level
 */
const RoleAwareRedirect: React.FC<{ adminPath: string; operatorPath?: string }> = ({ adminPath, operatorPath }) => {
  const { systemRole } = useAuth();
  if (systemRole === 'RESCUE_OPERATOR') {
    return <Navigate to={operatorPath || '/operator'} replace />;
  }
  return <Navigate to={adminPath} replace />;
};

export const App: React.FC = () => {
  return (
    <ThemeProvider>
      <BrowserRouter>
        <AuthProvider>
          <EmergencyProvider>
            <Routes>
              {/* Public Authentication Route */}
              <Route path="/login" element={<LoginPage />} />

              {/* Intelligent Root Entry Redirect */}
              <Route path="/" element={<RootRoleRedirect />} />

              {/* SUPER ADMIN WORKSPACE (Full Administrative Control) */}
              <Route
                path="/admin"
                element={
                  <ProtectedRoute allowedRoles={['SUPER_ADMIN']}>
                    <DashboardLayout />
                  </ProtectedRoute>
                }
              >
                <Route index element={<OverviewPage />} />
                <Route path="profile" element={<AdminProfilePage />} />
                <Route path="operators" element={<ManageOperatorsPage />} />
                <Route path="gateways" element={<ManageGatewaysPage />} />
                <Route path="emergencies" element={<LiveEmergenciesPage />} />
                <Route path="map" element={<EmergencyMapPage />} />
                <Route path="network" element={<RelayNetworkPage />} />
                <Route path="comms" element={<CommMonitorPage />} />
                <Route path="teams" element={<RescueTeamsPage />} />
                <Route path="analytics" element={<AnalyticsPage />} />
                <Route path="settings" element={<SettingsPage />} />
              </Route>

              {/* RESCUE OPERATOR WORKSPACE (Restricted Operational Station) */}
              <Route
                path="/operator"
                element={
                  <ProtectedRoute allowedRoles={['RESCUE_OPERATOR']}>
                    <DashboardLayout />
                  </ProtectedRoute>
                }
              >
                <Route index element={<OperatorDashboardPage />} />
                <Route path="emergencies" element={<LiveEmergenciesPage />} />
                <Route path="map" element={<EmergencyMapPage />} />
                <Route path="teams" element={<OperatorTeamsPage />} />
                <Route path="profile" element={<OperatorProfilePage />} />
              </Route>

              {/* Intelligent Legacy Route Redirects */}
              <Route path="/profile" element={<RoleAwareRedirect adminPath="/admin/profile" operatorPath="/operator/profile" />} />
              <Route path="/emergencies" element={<RoleAwareRedirect adminPath="/admin/emergencies" operatorPath="/operator/emergencies" />} />
              <Route path="/map" element={<RoleAwareRedirect adminPath="/admin/map" operatorPath="/operator/map" />} />
              <Route path="/teams" element={<RoleAwareRedirect adminPath="/admin/teams" operatorPath="/operator/teams" />} />
              <Route path="/gateways" element={<RoleAwareRedirect adminPath="/admin/gateways" operatorPath="/operator" />} />
              <Route path="/network" element={<RoleAwareRedirect adminPath="/admin/network" operatorPath="/operator" />} />
              <Route path="/comms" element={<RoleAwareRedirect adminPath="/admin/comms" operatorPath="/operator" />} />
              <Route path="/analytics" element={<RoleAwareRedirect adminPath="/admin/analytics" operatorPath="/operator" />} />
              <Route path="/settings" element={<RoleAwareRedirect adminPath="/admin/settings" operatorPath="/operator" />} />

              {/* Universal Catch-all */}
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </EmergencyProvider>
        </AuthProvider>
      </BrowserRouter>
    </ThemeProvider>
  );
};

export default App;
