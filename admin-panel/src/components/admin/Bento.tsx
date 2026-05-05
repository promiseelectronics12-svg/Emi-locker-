import React from 'react';
import { AlertTriangle, Boxes, Loader2, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

type BentoPanelProps = React.HTMLAttributes<HTMLDivElement> & {
  tone?: 'default' | 'emerald' | 'warning' | 'danger';
};

const toneClasses = {
  default: 'glass-panel',
  emerald: 'border-emerald-200/70 bg-emerald-50/70 shadow-[0_18px_55px_rgba(16,185,129,0.14)]',
  warning: 'border-amber-200/70 bg-amber-50/75 shadow-[0_18px_55px_rgba(245,158,11,0.12)]',
  danger: 'border-red-200/70 bg-red-50/75 shadow-[0_18px_55px_rgba(220,38,38,0.10)]',
};

export function BentoPanel({ className, tone = 'default', ...props }: BentoPanelProps) {
  return (
    <div
      className={cn('rounded-lg p-5 backdrop-blur-xl', toneClasses[tone], className)}
      {...props}
    />
  );
}

type PageHeaderProps = {
  title: string;
  description?: string;
  action?: React.ReactNode;
};

export function PageHeader({ title, description, action }: PageHeaderProps) {
  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0">
        <h1 className="text-2xl font-semibold tracking-normal text-emerald-950 sm:text-3xl">
          {title}
        </h1>
        {description ? (
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{description}</p>
        ) : null}
      </div>
      {action ? <div className="flex shrink-0 flex-wrap gap-2">{action}</div> : null}
    </div>
  );
}

type MetricTileProps = {
  title: string;
  value: React.ReactNode;
  icon: React.ElementType;
  helper?: string;
  tone?: 'emerald' | 'sky' | 'amber' | 'rose' | 'slate';
};

const metricTones = {
  emerald: 'from-emerald-500/15 text-emerald-700',
  sky: 'from-sky-500/15 text-sky-700',
  amber: 'from-amber-500/20 text-amber-700',
  rose: 'from-rose-500/15 text-rose-700',
  slate: 'from-slate-500/12 text-slate-700',
};

export function MetricTile({ title, value, icon: Icon, helper, tone = 'emerald' }: MetricTileProps) {
  return (
    <BentoPanel className={cn('bg-gradient-to-br to-white/70', metricTones[tone])}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-medium text-muted-foreground">{title}</p>
          <div className="mt-3 text-3xl font-semibold text-emerald-950">{value}</div>
          {helper ? <p className="mt-2 text-xs text-muted-foreground">{helper}</p> : null}
        </div>
        <div className="rounded-lg border border-white/70 bg-white/80 p-2 shadow-sm">
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </BentoPanel>
  );
}

export function LoadingState({ title = 'Loading workspace', rows = 4 }: { title?: string; rows?: number }) {
  return (
    <BentoPanel className="min-h-56">
      <div className="flex items-center gap-3 text-sm font-medium text-emerald-800">
        <Loader2 className="h-4 w-4 animate-spin" />
        {title}
      </div>
      <div className="mt-6 grid gap-3">
        {Array.from({ length: rows }).map((_, index) => (
          <div
            key={index}
            className="h-12 animate-pulse rounded-lg bg-gradient-to-r from-emerald-100/80 via-white/80 to-emerald-50/80"
          />
        ))}
      </div>
    </BentoPanel>
  );
}

type EmptyStateProps = {
  title: string;
  description?: string;
  icon?: React.ElementType;
  action?: React.ReactNode;
};

export function EmptyState({ title, description, icon: Icon = Boxes, action }: EmptyStateProps) {
  return (
    <BentoPanel className="flex min-h-60 flex-col items-center justify-center text-center">
      <div className="state-pulse rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-emerald-700">
        <Icon className="h-7 w-7" />
      </div>
      <h2 className="mt-5 text-lg font-semibold text-emerald-950">{title}</h2>
      {description ? <p className="mt-2 max-w-md text-sm text-muted-foreground">{description}</p> : null}
      {action ? <div className="mt-5">{action}</div> : null}
    </BentoPanel>
  );
}

type ErrorStateProps = {
  title?: string;
  description?: string;
  onRetry?: () => void;
};

export function ErrorState({
  title = 'This section could not be loaded',
  description = 'The server did not return usable data. Try again, and check the API logs if it repeats.',
  onRetry,
}: ErrorStateProps) {
  return (
    <BentoPanel tone="danger" className="min-h-52">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex gap-3">
          <div className="rounded-lg bg-white/80 p-2 text-red-600">
            <AlertTriangle className="h-5 w-5" />
          </div>
          <div>
            <h2 className="font-semibold text-red-950">{title}</h2>
            <p className="mt-1 max-w-2xl text-sm text-red-900/70">{description}</p>
          </div>
        </div>
        {onRetry ? (
          <Button variant="outline" onClick={onRetry} className="border-red-200 bg-white/70 text-red-700 hover:bg-white">
            <RefreshCw className="mr-2 h-4 w-4" />
            Retry
          </Button>
        ) : null}
      </div>
    </BentoPanel>
  );
}

export function normalizeList<T>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[];
  if (value && typeof value === 'object' && Array.isArray((value as { data?: unknown }).data)) {
    return (value as { data: T[] }).data;
  }
  return [];
}
