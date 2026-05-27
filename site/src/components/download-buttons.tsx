const GITHUB_RELEASES_URL =
  "https://github.com/jacobaraujo7/remote_pi/releases";
const GOOGLE_PLAY_URL =
  "https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi";

export function DownloadButtons() {
  return (
    <div className="grid w-full max-w-3xl gap-3 sm:grid-cols-3">
      <StoreButton
        platform="Google Play"
        label="GET IT ON"
        icon={<GooglePlayIcon />}
        href={GOOGLE_PLAY_URL}
        sublabel="Now available"
      />
      <StoreButton
        platform="App Store"
        label="DOWNLOAD ON THE"
        icon={<AppStoreIcon />}
        disabled
        sublabel="Coming soon"
      />
      <StoreButton
        platform="Android APK"
        label="DIRECT DOWNLOAD"
        icon={<ApkIcon />}
        href={GITHUB_RELEASES_URL}
        sublabel="GitHub Releases"
      />
    </div>
  );
}

type StoreButtonProps = {
  platform: string;
  label: string;
  sublabel: string;
  icon: React.ReactNode;
  href?: string;
  disabled?: boolean;
};

function StoreButton({
  platform,
  label,
  sublabel,
  icon,
  href,
  disabled,
}: StoreButtonProps) {
  const className =
    "group flex items-center gap-3 rounded-2xl border border-border-soft bg-surface px-5 py-4 text-left transition-colors";
  const inner = (
    <>
      <div className="flex h-9 w-9 shrink-0 items-center justify-center text-fg">
        {icon}
      </div>
      <div className="flex flex-col leading-tight">
        <span className="text-[10px] font-semibold uppercase tracking-[0.15em] text-muted">
          {label}
        </span>
        <span className="text-base font-semibold text-fg">{platform}</span>
        <span className="text-xs text-muted">{sublabel}</span>
      </div>
    </>
  );

  if (disabled || !href) {
    return (
      <div
        className={`${className} cursor-not-allowed opacity-60`}
        aria-disabled="true"
        title="Coming soon"
      >
        {inner}
      </div>
    );
  }

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={`${className} hover:border-fg/40`}
    >
      {inner}
    </a>
  );
}

function GooglePlayIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      className="h-7 w-7"
      aria-hidden="true"
    >
      <path
        fill="#4FC3F7"
        d="m3.61 1.81-.06.04A2 2 0 0 0 3 3.27v17.46a2 2 0 0 0 .55 1.42l.06.05 9.78-9.78v-.86L3.61 1.81z"
      />
      <path
        fill="#FFCB39"
        d="m16.65 15.7-3.26-3.26v-.88l3.26-3.26.07.04 3.86 2.2c1.1.63 1.1 1.66 0 2.28l-3.86 2.2-.07.07z"
      />
      <path
        fill="#ff4f60"
        d="m16.72 15.63-3.33-3.33L3.61 22.2c.36.4.97.45 1.66.06l11.45-6.63"
      />
      <path
        fill="#22c55e"
        d="M16.72 8.37 5.27 1.74C4.58 1.35 3.97 1.4 3.61 1.8l9.78 9.78z"
      />
    </svg>
  );
}

function AppStoreIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      className="h-7 w-7"
      aria-hidden="true"
    >
      <path d="M16.37 12.42c-.02-2.21 1.81-3.27 1.89-3.32-1.03-1.5-2.63-1.71-3.21-1.73-1.36-.14-2.66.8-3.35.8-.7 0-1.76-.78-2.9-.76-1.48.02-2.85.86-3.62 2.19-1.55 2.68-.39 6.65 1.1 8.83.74 1.07 1.61 2.27 2.76 2.23 1.11-.05 1.53-.71 2.86-.71 1.33 0 1.7.71 2.87.68 1.18-.02 1.93-1.09 2.65-2.17.84-1.24 1.18-2.45 1.2-2.51-.03-.01-2.29-.88-2.32-3.51zM14.21 5.91c.61-.74 1.03-1.78.92-2.81-.89.04-1.96.59-2.6 1.33-.57.66-1.07 1.71-.94 2.72.99.08 2 -.5 2.62-1.24z" />
    </svg>
  );
}

function ApkIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-6 w-6"
      aria-hidden="true"
    >
      <path d="M12 3v12" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 21h14" />
    </svg>
  );
}
