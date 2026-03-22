import { signal } from '@preact/signals';
import { useEffect } from 'preact/hooks';

interface ToastItem {
  id: number;
  message: string;
  fadingOut: boolean;
}

let nextId = 0;
const AUTO_DISMISS_MS = 6000;
const FADE_MS = 280;

export const toasts = signal<ToastItem[]>([]);

export function showError(message: string) {
  const id = ++nextId;
  toasts.value = [...toasts.value, { id, message, fadingOut: false }];
  setTimeout(() => dismissToast(id), AUTO_DISMISS_MS);
}

function dismissToast(id: number) {
  // Start fade-out, then remove after animation
  toasts.value = toasts.value.map((t) =>
    t.id === id ? { ...t, fadingOut: true } : t,
  );
  setTimeout(() => {
    toasts.value = toasts.value.filter((t) => t.id !== id);
  }, FADE_MS);
}

export function ErrorToast() {
  const items = toasts.value;
  if (items.length === 0) return null;

  return (
    <div class="error-toast-container" role="alert" aria-live="assertive">
      {items.map((t) => (
        <div key={t.id} class={`error-toast${t.fadingOut ? ' error-toast--out' : ''}`}>
          <span class="error-toast-icon" aria-hidden="true">⚠</span>
          <span class="error-toast-msg">{t.message}</span>
          <button
            class="error-toast-close"
            aria-label="Dismiss"
            onClick={() => dismissToast(t.id)}
          >
            ✕
          </button>
        </div>
      ))}
    </div>
  );
}
