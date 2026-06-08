import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react';
import {
  createBrowserRouter,
  RouterProvider,
  Navigate,
  useNavigate,
} from 'react-router-dom';
import { getAuth } from './auth/storage';
import { SetupWizard } from './auth/SetupWizard';
import { AppShell } from './components/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';

const Treatment = lazy(() => import('./routes/Treatment'));
const BloodTests = lazy(() => import('./routes/BloodTests'));
const KB = lazy(() => import('./routes/KB'));
const Inventory = lazy(() => import('./routes/Inventory'));
const Fitness = lazy(() => import('./routes/Fitness'));
const Chat = lazy(() => import('./routes/Chat'));

function AuthGuard({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    getAuth().then(a => {
      if (!a) navigate('/setup', { replace: true });
      else setChecked(true);
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  if (!checked) return <div className="p-4 text-slate-400">Loading…</div>;
  return <>{children}</>;
}

function SetupRoute() {
  const navigate = useNavigate();
  return (
    <SetupWizard
      onSaved={() => navigate('/treatment', { replace: true })}
    />
  );
}

const router = createBrowserRouter([
  { path: '/setup', element: <SetupRoute /> },
  {
    element: (
      <AuthGuard>
        <AppShell />
      </AuthGuard>
    ),
    children: [
      { index: true, element: <Navigate to="/treatment" replace /> },
      {
        path: '/treatment/*',
        element: (
          <ErrorBoundary>
            <Suspense fallback={<div className="p-4 text-slate-400">Loading…</div>}>
              <Treatment />
            </Suspense>
          </ErrorBoundary>
        ),
      },
      {
        path: '/blood-tests',
        element: (
          <ErrorBoundary>
            <Suspense fallback={<div className="p-4 text-slate-400">Loading…</div>}>
              <BloodTests />
            </Suspense>
          </ErrorBoundary>
        ),
      },
      { path: '/kb', element: <Suspense fallback={null}><KB /></Suspense> },
      { path: '/inventory', element: <Suspense fallback={null}><Inventory /></Suspense> },
      { path: '/fitness', element: <Suspense fallback={null}><Fitness /></Suspense> },
      { path: '/chat', element: <Suspense fallback={null}><Chat /></Suspense> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
