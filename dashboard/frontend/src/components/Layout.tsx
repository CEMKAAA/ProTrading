import { ReactNode } from 'react';
import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  TestTube2,
  Settings2,
  Activity,
  TrendingUp,
  Menu,
  X,
} from 'lucide-react';
import { useState } from 'react';
import clsx from 'clsx';

interface LayoutProps {
  children: ReactNode;
}

const navigation = [
  { name: 'Dashboard', href: '/', icon: LayoutDashboard },
  { name: 'Backtests', href: '/backtests', icon: TestTube2 },
  { name: 'Configurations', href: '/configurations', icon: Settings2 },
  { name: 'Live Trading', href: '/live', icon: Activity },
];

export default function Layout({ children }: LayoutProps) {
  const location = useLocation();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="min-h-screen bg-dark-950">
      {/* Mobile sidebar backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={clsx(
          'fixed top-0 left-0 z-50 h-full w-64 bg-dark-900 border-r border-dark-800',
          'transform transition-transform duration-200 ease-in-out',
          'lg:translate-x-0',
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        {/* Logo */}
        <div className="h-16 flex items-center justify-between px-4 border-b border-dark-800">
          <Link to="/" className="flex items-center gap-2">
            <TrendingUp className="w-8 h-8 text-primary-500" />
            <span className="text-lg font-bold text-white">ProTrading</span>
          </Link>
          <button
            onClick={() => setSidebarOpen(false)}
            className="lg:hidden p-2 text-dark-400 hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Navigation */}
        <nav className="p-4 space-y-1">
          {navigation.map((item) => {
            const isActive = location.pathname === item.href ||
              (item.href !== '/' && location.pathname.startsWith(item.href));

            return (
              <Link
                key={item.name}
                to={item.href}
                onClick={() => setSidebarOpen(false)}
                className={clsx(
                  'flex items-center gap-3 px-3 py-2.5 rounded-lg',
                  'transition-all duration-200',
                  isActive
                    ? 'bg-primary-500/10 text-primary-400'
                    : 'text-dark-400 hover:bg-dark-800 hover:text-white'
                )}
              >
                <item.icon className="w-5 h-5" />
                <span className="font-medium">{item.name}</span>
              </Link>
            );
          })}
        </nav>

        {/* Version info */}
        <div className="absolute bottom-0 left-0 right-0 p-4 border-t border-dark-800">
          <div className="text-xs text-dark-500">
            <div>ProTrading Dashboard v1.0.0</div>
            <div className="mt-1">ICT Strategy Engine</div>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <div className="lg:pl-64">
        {/* Top bar */}
        <header className="sticky top-0 z-30 h-16 bg-dark-900/80 backdrop-blur border-b border-dark-800">
          <div className="flex items-center justify-between h-full px-4">
            <button
              onClick={() => setSidebarOpen(true)}
              className="lg:hidden p-2 text-dark-400 hover:text-white"
            >
              <Menu className="w-6 h-6" />
            </button>

            <div className="flex items-center gap-4">
              {/* Connection status indicator */}
              <div className="flex items-center gap-2 text-sm">
                <span className="w-2 h-2 rounded-full bg-success-500 animate-pulse" />
                <span className="text-dark-400">MT5 Connected</span>
              </div>
            </div>
          </div>
        </header>

        {/* Page content */}
        <main className="p-6">
          {children}
        </main>
      </div>
    </div>
  );
}
