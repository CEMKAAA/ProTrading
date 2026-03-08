import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(value: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatPercent(value: number): string {
  return `${value.toFixed(1)}%`;
}

export function formatNumber(value: number, decimals = 2): string {
  return value.toFixed(decimals);
}

export function formatDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function formatDateTime(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function formatTime(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function formatDuration(minutes: number): string {
  if (minutes < 60) {
    return `${Math.round(minutes)}m`;
  }
  const hours = Math.floor(minutes / 60);
  const mins = Math.round(minutes % 60);
  return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
}

export function getMetricColor(value: number, isNegativeBetter = false): string {
  if (isNegativeBetter) {
    return value <= 0 ? 'text-success-500' : 'text-danger-500';
  }
  return value >= 0 ? 'text-success-500' : 'text-danger-500';
}

export function classifyWinRate(rate: number): { label: string; color: string } {
  if (rate >= 60) return { label: 'Excellent', color: 'text-success-500' };
  if (rate >= 50) return { label: 'Good', color: 'text-primary-500' };
  if (rate >= 40) return { label: 'Fair', color: 'text-warning-500' };
  return { label: 'Poor', color: 'text-danger-500' };
}

export function classifyProfitFactor(pf: number): { label: string; color: string } {
  if (pf >= 2.0) return { label: 'Excellent', color: 'text-success-500' };
  if (pf >= 1.5) return { label: 'Good', color: 'text-primary-500' };
  if (pf >= 1.0) return { label: 'Breakeven', color: 'text-warning-500' };
  return { label: 'Losing', color: 'text-danger-500' };
}

export function classifyDrawdown(dd: number): { label: string; color: string } {
  if (dd <= 10) return { label: 'Low', color: 'text-success-500' };
  if (dd <= 20) return { label: 'Moderate', color: 'text-primary-500' };
  if (dd <= 30) return { label: 'High', color: 'text-warning-500' };
  return { label: 'Critical', color: 'text-danger-500' };
}

export function debounce<T extends (...args: unknown[]) => unknown>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}

export function throttle<T extends (...args: unknown[]) => unknown>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean;
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args);
      inThrottle = true;
      setTimeout(() => (inThrottle = false), limit);
    }
  };
}
