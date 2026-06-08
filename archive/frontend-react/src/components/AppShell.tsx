import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { Activity, FlaskConical, BookOpen, Package, Dumbbell, MessageSquare } from 'lucide-react';
import { clearAuth } from '../auth/storage';
import { useKeyboardAvoidance } from '../hooks/useKeyboardAvoidance';
import { ErrorBoundary } from './ErrorBoundary';

const TABS = [
  { to: '/treatment', label: 'Treatment', Icon: Activity },
  { to: '/blood-tests', label: 'Tests', Icon: FlaskConical },
  { to: '/kb', label: 'KB', Icon: BookOpen },
  { to: '/inventory', label: 'Inv', Icon: Package },
  { to: '/fitness', label: 'Fitness', Icon: Dumbbell },
  { to: '/chat', label: 'Chat', Icon: MessageSquare },
];

export function AppShell() {
  const navigate = useNavigate();
  useKeyboardAvoidance();

  async function handleResetAuth() {
    if (!confirm('Clear all saved credentials on this device?')) return;
    await clearAuth();
    navigate('/setup');
  }

  const tabClass = ({ isActive }: { isActive: boolean }) =>
    `flex flex-col items-center gap-0.5 px-3 py-2 text-xs transition-colors ${
      isActive ? 'text-accent' : 'text-slate-500 hover:text-slate-300'
    }`;

  return (
    <div className="flex flex-col min-h-screen">
      {/* Top bar (desktop) */}
      <nav className="hidden md:flex items-center border-b border-slate-700 bg-panel px-4 gap-1">
        <span className="text-sm font-semibold text-slate-300 mr-4">Home HD</span>
        {TABS.map(({ to, label }) => (
          <NavLink key={to} to={to} className={tabClass}>
            {label}
          </NavLink>
        ))}
        <button
          type="button"
          onClick={handleResetAuth}
          className="ml-auto text-xs text-slate-500 hover:text-slate-300 py-2"
        >
          Settings
        </button>
      </nav>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto main-scroll">
        <ErrorBoundary>
          <Outlet />
        </ErrorBoundary>
      </main>

      {/* Bottom tab bar (mobile) */}
      <nav className="fixed bottom-0 left-0 right-0 flex md:hidden border-t border-slate-700 bg-panel safe-area-inset-bottom">
        {TABS.map(({ to, label, Icon }) => (
          <NavLink key={to} to={to} className={({ isActive }) =>
            `flex-1 flex flex-col items-center gap-0.5 py-2 text-xs transition-colors ${
              isActive ? 'text-accent' : 'text-slate-500 hover:text-slate-300'
            }`
          }>
            <Icon size={20} />
            {label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
