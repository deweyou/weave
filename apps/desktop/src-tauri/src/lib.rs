mod commands;
mod storage;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::get_app_info,
            commands::get_runtime_status,
            commands::get_local_paths,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
