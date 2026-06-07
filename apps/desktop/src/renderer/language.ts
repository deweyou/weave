export type AppLanguage = "zh-CN" | "en-US";

const languageStorageKey = "weave:language";

export function isAppLanguage(value: string | null): value is AppLanguage {
  return value === "zh-CN" || value === "en-US";
}

export function readStoredLanguage(): AppLanguage | null {
  try {
    const storedLanguage = window.localStorage.getItem(languageStorageKey);
    return isAppLanguage(storedLanguage) ? storedLanguage : null;
  } catch {
    return null;
  }
}

export function storeLanguage(language: AppLanguage): void {
  try {
    window.localStorage.setItem(languageStorageKey, language);
  } catch {
    // Language selection still applies for this session when localStorage is unavailable.
  }
}

export function clearStoredLanguage(): void {
  try {
    window.localStorage.removeItem(languageStorageKey);
  } catch {
    // Resetting the current session state is enough when localStorage is unavailable.
  }
}
