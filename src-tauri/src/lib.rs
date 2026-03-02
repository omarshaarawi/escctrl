mod diag;
mod hidutil;
mod keyboard;
mod permissions;

use keyboard::KeyboardEngine;
use std::sync::Mutex;
use std::time::Duration;
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tauri_plugin_store::StoreExt;

struct EngineState(Mutex<KeyboardEngine>);
struct EngineStarted(Mutex<bool>);

fn try_start_engine(app: &AppHandle, log: bool) -> bool {
    let started_state = app.state::<EngineStarted>();
    let mut started = started_state.0.lock().unwrap();
    if *started {
        return true;
    }

    let engine_state = app.state::<EngineState>();
    let mut engine = engine_state.0.lock().unwrap();

    match engine.start() {
        Ok(()) => {
            diag::log("engine started, running hidutil remap...");
            match hidutil::remap_capslock() {
                Ok(()) => diag::log("hidutil remap OK"),
                Err(e) => diag::log(&format!("hidutil remap FAILED: {e}")),
            }
            *started = true;
            true
        }
        Err(e) => {
            if log {
                diag::log(&format!("engine start failed: {e}"));
            }
            false
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .manage(EngineState(Mutex::new(KeyboardEngine::new())))
        .manage(EngineStarted(Mutex::new(false)))
        .setup(|app| {
            diag::log("=== escctrl setup starting ===");

            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let store = app.store("settings.json")?;
            let escape_enabled = store
                .get("escape_on_tap")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            let enabled = store
                .get("enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);

            {
                let state = app.state::<EngineState>();
                let engine = state.0.lock().unwrap();
                engine.set_escape_on_tap(escape_enabled);
                engine.set_enabled(enabled);
            }

            let toggle_item = MenuItem::with_id(
                app,
                "toggle",
                if enabled { "Disable" } else { "Enable" },
                true,
                None::<&str>,
            )?;

            let escape_item = CheckMenuItem::with_id(
                app,
                "escape_toggle",
                "Escape on Tap",
                true,
                escape_enabled,
                None::<&str>,
            )?;

            let autostart_enabled = app.autolaunch().is_enabled()?;
            let autostart_item = CheckMenuItem::with_id(
                app,
                "autostart",
                "Launch at Login",
                true,
                autostart_enabled,
                None::<&str>,
            )?;

            let sep = PredefinedMenuItem::separator(app)?;

            let perm_item = MenuItem::with_id(
                app,
                "open_accessibility",
                "Accessibility: Open Settings...",
                true,
                None::<&str>,
            )?;

            let update_item =
                MenuItem::with_id(app, "check_update", "Check for Updates", true, None::<&str>)?;

            let sep2 = PredefinedMenuItem::separator(app)?;

            let quit_item =
                MenuItem::with_id(app, "quit", "Quit escctrl", true, None::<&str>)?;

            let menu = Menu::with_items(
                app,
                &[
                    &toggle_item,
                    &escape_item,
                    &autostart_item,
                    &sep,
                    &perm_item,
                    &update_item,
                    &sep2,
                    &quit_item,
                ],
            )?;

            let perm_item_bg = perm_item.clone();

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(move |app, event| {
                    match event.id.as_ref() {
                        "toggle" => {
                            let state = app.state::<EngineState>();
                            let engine = state.0.lock().unwrap();
                            let now_enabled = !engine.is_enabled();
                            engine.set_enabled(now_enabled);

                            let _ = toggle_item.set_text(if now_enabled {
                                "Disable"
                            } else {
                                "Enable"
                            });

                            if let Ok(store) = app.store("settings.json") {
                                let _ = store.set("enabled", serde_json::json!(now_enabled));
                            }
                        }

                        "escape_toggle" => {
                            let state = app.state::<EngineState>();
                            let engine = state.0.lock().unwrap();
                            let new_val = !engine.is_escape_on_tap();
                            engine.set_escape_on_tap(new_val);
                            let _ = escape_item.set_checked(new_val);

                            if let Ok(store) = app.store("settings.json") {
                                let _ = store.set("escape_on_tap", serde_json::json!(new_val));
                            }
                        }

                        "autostart" => {
                            let manager = app.autolaunch();
                            let currently = manager.is_enabled().unwrap_or(false);
                            if currently {
                                let _ = manager.disable();
                            } else {
                                let _ = manager.enable();
                            }
                            let _ = autostart_item.set_checked(!currently);
                        }

                        "open_accessibility" => {
                            let _ = std::process::Command::new("open")
                                .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                                .spawn();
                        }

                        "check_update" => {
                            let handle = app.clone();
                            let item = update_item.clone();
                            tauri::async_runtime::spawn(async move {
                                let updater = match tauri_plugin_updater::UpdaterExt::updater(&handle) {
                                    Ok(u) => u,
                                    Err(e) => {
                                        log::error!("Updater init failed: {e}");
                                        return;
                                    }
                                };
                                match updater.check().await {
                                    Ok(Some(update)) => {
                                        let _ = item.set_text("Downloading...");
                                        let _ = item.set_enabled(false);
                                        if let Err(e) = update.download_and_install(|_, _| {}, || {}).await {
                                            log::error!("Update failed: {e}");
                                            let _ = item.set_text("Update failed");
                                            let _ = item.set_enabled(true);
                                        }
                                    }
                                    Ok(None) => {
                                        let _ = item.set_text("Up to date");
                                    }
                                    Err(e) => {
                                        log::error!("Update check failed: {e}");
                                        let _ = item.set_text("Check failed");
                                    }
                                }
                            });
                        }

                        "quit" => {
                            app.exit(0);
                        }

                        _ => {}
                    }
                })
                .build(app)?;

            permissions::request_accessibility();

            let handle = app.handle().clone();
            if try_start_engine(&handle, true) {
                let _ = perm_item.set_text("Accessibility: Granted");
                let _ = perm_item.set_enabled(false);
            } else {
                std::thread::spawn(move || {
                    diag::log("waiting for accessibility permission...");
                    loop {
                        std::thread::sleep(Duration::from_secs(2));
                        if try_start_engine(&handle, false) {
                            let _ = perm_item_bg.set_text("Accessibility: Granted");
                            let _ = perm_item_bg.set_enabled(false);
                            diag::log("engine started after permission granted");
                            break;
                        }
                    }
                });
            }

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app, event| {
            if let tauri::RunEvent::Exit = event {
                if let Err(e) = hidutil::restore_capslock() {
                    log::error!("Failed to restore Caps Lock: {}", e);
                }
            }
        });
}
