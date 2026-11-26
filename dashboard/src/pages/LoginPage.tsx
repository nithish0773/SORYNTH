import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Shield, Lock, Mail, ArrowRight, AlertCircle, Eye, EyeOff, Sun, Moon } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useTheme } from '../context/ThemeContext';

export const LoginPage: React.FC = () => {
  const { signIn, error: authError } = useAuth();
  const { isDark, toggleTheme } = useTheme();
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLocalError(null);

    if (!email.trim() || !password) {
      setLocalError('Please enter both email address and password.');
      return;
    }

    setLoading(true);

    try {
      const res = await signIn(email.trim(), password);

      if (res.success) {
        if (res.systemRole === 'SUPER_ADMIN') {
          navigate('/admin');
        } else {
          navigate('/operator');
        }
      } else {
        setLocalError(res.error || 'Authentication failed. Please verify credentials.');
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Authentication failed';
      setLocalError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-[#f2f2f7] dark:bg-black text-[#1c1c1e] dark:text-[#f5f5f7] relative overflow-hidden transition-colors duration-200">
      {/* Top Floating Theme Switcher */}
      <div className="absolute top-5 right-5 z-20">
        <button
          onClick={toggleTheme}
          type="button"
          aria-label={isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'}
          className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-black/[0.08] dark:border-white/[0.12] bg-white/80 dark:bg-[#1c1c1e]/80 backdrop-blur-xl shadow-ios-pill text-xs font-medium text-slate-700 dark:text-slate-200 hover:text-slate-900 dark:hover:text-white transition-all active:scale-95"
        >
          {isDark ? (
            <>
              <Sun className="w-3.5 h-3.5 text-amber-400" />
              <span>Light Mode</span>
            </>
          ) : (
            <>
              <Moon className="w-3.5 h-3.5 text-indigo-500" />
              <span>Dark Mode</span>
            </>
          )}
        </button>
      </div>

      {/* Background ambient lighting */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[600px] h-[350px] bg-ios-blue/10 rounded-full blur-[120px] pointer-events-none" />

      {/* Apple Centered Card Surface */}
      <div className="relative w-full max-w-[440px] z-10">
        <div className="p-8 sm:p-9 rounded-[28px] border border-black/[0.08] dark:border-white/[0.12] bg-white dark:bg-[#161619] shadow-2xl transition-colors duration-200">
          
          {/* Brand Header */}
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-14 h-14 rounded-[18px] bg-gradient-to-b from-[#2997ff] to-ios-blue text-white shadow-ios-pill mb-4">
              <Shield className="w-7 h-7" />
            </div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-white">
              SORYNTH CAD
            </h1>
            <p className="text-xs text-slate-500 dark:text-ios-secondary mt-1">
              Rescue Command & Field Operator Portal
            </p>
          </div>

          {/* Error Banner */}
          {(localError || authError) && (
            <div className="mb-6 p-3.5 rounded-[16px] border border-ios-red/30 bg-ios-red/10 text-xs text-ios-red flex items-start gap-2.5 animate-in fade-in duration-200">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <div className="leading-relaxed">
                {localError || authError}
              </div>
            </div>
          )}

          {/* Sign In Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-[11px] font-semibold text-slate-600 dark:text-[#a1a1a6] mb-1.5 uppercase tracking-wider">
                Official Email
              </label>
              <div className="relative">
                <Mail className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@sorynth.org or operator email"
                  autoComplete="email"
                  className="w-full pl-10 pr-3.5 py-3 rounded-[14px] border border-black/[0.1] dark:border-white/[0.12] bg-slate-50 dark:bg-black/40 text-slate-900 dark:text-white text-xs placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-ios-blue/40 transition-all"
                />
              </div>
            </div>

            <div>
              <label className="block text-[11px] font-semibold text-slate-600 dark:text-[#a1a1a6] mb-1.5 uppercase tracking-wider">
                Password
              </label>
              <div className="relative">
                <Lock className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type={showPassword ? 'text' : 'password'}
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter security password"
                  autoComplete="current-password"
                  className="w-full pl-10 pr-10 py-3 rounded-[14px] border border-black/[0.1] dark:border-white/[0.12] bg-slate-50 dark:bg-black/40 text-slate-900 dark:text-white text-xs placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-ios-blue/40 transition-all"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-white transition-colors"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full mt-2 py-3.5 px-4 rounded-[14px] bg-ios-blue hover:bg-ios-blue/90 active:scale-[0.98] text-white font-semibold text-xs shadow-ios-card flex items-center justify-center gap-2 transition-all disabled:opacity-50"
            >
              {loading ? (
                <>
                  <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  <span>Verifying Credentials...</span>
                </>
              ) : (
                <>
                  <span>Sign In to Console</span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          {/* Access Policy Footer Notice */}
          <div className="mt-7 pt-5 border-t border-black/[0.06] dark:border-white/[0.08] text-center">
            <p className="text-[11px] text-slate-500 dark:text-ios-secondary leading-relaxed">
              Operator accounts are provisioned exclusively by Super Administrators. Unregistered users cannot self-enroll.
            </p>
            <div className="mt-3 flex items-center justify-center gap-2 text-[10px] text-slate-400 dark:text-neutral-500 font-mono">
              <span className="w-1.5 h-1.5 rounded-full bg-ios-green" />
              <span>RBAC Policy Active • Supabase Auth</span>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
};
