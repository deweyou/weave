export interface DesktopApi {
  getAppInfo(): {
    name: string;
    runtime: string;
  };
}
