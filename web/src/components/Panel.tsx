import type { ReactNode } from "react";

export function Panel({
  title,
  subtitle,
  children,
  className = "",
  bodyClassName = "panel-b",
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
}) {
  return (
    <section className={`panel ${className}`.trim()}>
      {(title || subtitle) && (
        <header className="panel-h">
          {title && <h2 className="panel-t">{title}</h2>}
          {subtitle && <span className="panel-s">{subtitle}</span>}
        </header>
      )}
      <div className={bodyClassName}>{children}</div>
    </section>
  );
}

export function PageHead({
  crumb,
  title,
  children,
  aside,
}: {
  crumb?: string;
  title: ReactNode;
  children?: ReactNode;
  aside?: ReactNode;
}) {
  return (
    <header className="page-head">
      <div>
        {crumb && <div className="crumb">{crumb}</div>}
        <h1>{title}</h1>
        {children && <p>{children}</p>}
      </div>
      {aside}
    </header>
  );
}

export function Kpi({
  label,
  hint,
  value,
  foot,
  planned = false,
}: {
  label: string;
  hint?: string;
  value: ReactNode;
  foot?: ReactNode;
  planned?: boolean;
}) {
  return (
    <div className={`panel kpi${planned ? " planned" : ""}`}>
      <div className="kpi-l">
        <span>{label}</span>
        {hint && <span>{hint}</span>}
      </div>
      <div className="kpi-v">{value}</div>
      {foot && <div className="kpi-f">{foot}</div>}
    </div>
  );
}
