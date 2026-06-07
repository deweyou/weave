export type AppTheme = "light" | "dark" | "system";

const themeStorageKey = "weave:theme";

export function isAppTheme(value: string | null): value is AppTheme {
  return value === "light" || value === "dark" || value === "system";
}

export function readStoredTheme(): AppTheme {
  try {
    const storedTheme = window.localStorage.getItem(themeStorageKey);
    return isAppTheme(storedTheme) ? storedTheme : "system";
  } catch {
    return "system";
  }
}

export function storeTheme(theme: AppTheme): void {
  try {
    window.localStorage.setItem(themeStorageKey, theme);
  } catch {
    // Theme selection still applies for this session when localStorage is unavailable.
  }
}

export function applyTheme(theme: AppTheme): void {
  document.documentElement.dataset.theme = theme;
}

export function syncSystemIconTheme(theme: AppTheme): void {
  if (!window.weave) {
    return;
  }

  void window.weave.setThemePreference(theme);
}
