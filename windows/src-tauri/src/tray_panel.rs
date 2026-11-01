//! Tray panel lifecycle and daily-allowance images. No credentials or provider I/O live here.
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WindowEvent,
};

#[derive(Clone, Copy, Debug, PartialEq)]
struct Placement {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

fn placement(anchor: (f64, f64), bounds: (i32, i32, u32, u32), scale: f64) -> Placement {
    let scale = if scale.is_finite() && scale > 0.0 {
        scale
    } else {
        1.0
    };
    let margin = (8.0 * scale).round() as i32;
    let (left, top, work_width, work_height) = bounds;
    let width = (920.0 * scale)
        .round()
        .min(f64::from(work_width.saturating_sub((margin * 2) as u32)))
        .max(1.0) as u32;
    let height = (760.0 * scale)
        .round()
        .min(f64::from(work_height.saturating_sub((margin * 2) as u32)))
        .max(1.0) as u32;
    let min_x = left + margin.min(work_width.saturating_sub(width) as i32);
    let min_y = top + margin.min(work_height.saturating_sub(height) as i32);
    let max_x = (i64::from(left) + i64::from(work_width) - i64::from(width) - i64::from(margin))
        .max(i64::from(min_x)) as i32;
    let max_y = (i64::from(top) + i64::from(work_height) - i64::from(height) - i64::from(margin))
        .max(i64::from(min_y)) as i32;
    let x = (anchor.0.round() as i32 - width as i32 / 2).clamp(min_x, max_x);
    let preferred_y = anchor.1.round() as i32 - height as i32 - margin;
    let y = if preferred_y < min_y {
        anchor.1.round() as i32 + margin
    } else {
        preferred_y
    }
    .clamp(min_y, max_y);
    Placement {
        x,
        y,
        width,
        height,
    }
}

pub fn show_panel(app: &AppHandle, anchor: Option<(f64, f64)>) -> Result<(), String> {
    let window = app
        .get_webview_window("widget")
        .ok_or("panel_unavailable")?;
    let anchor = anchor
        .or_else(|| window.cursor_position().ok().map(|p| (p.x, p.y)))
        .unwrap_or((0.0, 0.0));
    let monitor = window
        .monitor_from_point(anchor.0, anchor.1)
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten())
        .ok_or("monitor_unavailable")?;
    let work = monitor.work_area();
    let target = placement(
        anchor,
        (
            work.position.x,
            work.position.y,
            work.size.width,
            work.size.height,
        ),
        monitor.scale_factor(),
    );
    // A small screen must be allowed to host a smaller panel than its design-time minimum.
    window
        .set_min_size(Some(tauri::LogicalSize::new(1.0, 1.0)))
        .map_err(|_| "panel_size_failed")?;
    window
        .set_size(PhysicalSize::new(target.width, target.height))
        .map_err(|_| "panel_size_failed")?;
    window
        .set_position(PhysicalPosition::new(target.x, target.y))
        .map_err(|_| "panel_position_failed")?;
    window.show().map_err(|_| "panel_show_failed")?;
    window.set_focus().map_err(|_| "panel_focus_failed")?;
    let _ = app.emit_to("widget", "panel-shown", ());
    Ok(())
}

fn toggle_panel(app: &AppHandle, anchor: Option<(f64, f64)>) {
    if let Some(window) = app.get_webview_window("widget") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = show_panel(app, anchor);
        }
    }
}

#[tauri::command]
pub fn hide_panel(app: AppHandle) -> Result<(), String> {
    app.get_webview_window("widget")
        .ok_or("panel_unavailable")?
        .hide()
        .map_err(|_| "panel_hide_failed".into())
}

#[cfg(windows)]
fn foreground_belongs_to_this_process() -> bool {
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId,
    };
    // A native file picker belongs to this process; hiding its owner here would dismiss the panel.
    let mut process_id = 0;
    unsafe {
        GetWindowThreadProcessId(GetForegroundWindow(), &mut process_id);
    }
    process_id == std::process::id()
}
#[cfg(not(windows))]
fn foreground_belongs_to_this_process() -> bool {
    false
}

pub fn handle_window_event(window: &tauri::Window, event: &WindowEvent) {
    if window.label() != "widget" {
        return;
    }
    match event {
        WindowEvent::CloseRequested { api, .. } => {
            api.prevent_close();
            let _ = window.hide();
        }
        WindowEvent::Focused(false) => {
            let window = window.clone();
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(150)).await;
                if !window.is_focused().unwrap_or(true) && !foreground_belongs_to_this_process() {
                    let _ = window.hide();
                }
            });
        }
        _ => {}
    }
}

fn validate_remaining(percent: Option<f64>, weekly: Option<f64>, mode: &str) -> Result<(), String> {
    if !matches!(mode, "percent" | "bar" | "circle") {
        return Err("invalid_tray_mode".into());
    }
    match (percent, weekly) {
        (None, None) => Ok(()),
        (Some(p), Some(w))
            if p.is_finite() && (0.0..=100.0).contains(&p) && w.is_finite() && w >= 0.0 =>
        {
            Ok(())
        }
        _ => Err("invalid_daily_allowance".into()),
    }
}

fn tooltip(
    percent: Option<f64>,
    weekly: Option<f64>,
    upper: bool,
    stale: bool,
    english: bool,
) -> String {
    let qualifier = format!(
        "{}{}",
        if stale { "≈" } else { "" },
        if upper { "≤" } else { "" }
    );
    let daily = percent
        .map(|v| format!("{qualifier}{v:.1}%"))
        .unwrap_or_else(|| "—".into());
    let weekly = weekly
        .map(|v| format!("{qualifier}{v:.1}%"))
        .unwrap_or_else(|| "—".into());
    if english {
        format!("CodexBar Cockpit · Available today {daily} · Weekly equivalent {weekly}")
    } else {
        format!("CodexBar Cockpit · 今日还能用 {daily} · 相当于周额度 {weekly}")
    }
}

// Small bitmap glyphs remain legible when Windows scales the 36px tray image down.
const DIGITS: [[u8; 5]; 11] = [
    [7, 5, 5, 5, 7],
    [2, 6, 2, 2, 7],
    [7, 1, 7, 4, 7],
    [7, 1, 7, 1, 7],
    [5, 5, 7, 1, 1],
    [7, 4, 7, 1, 7],
    [7, 4, 7, 5, 7],
    [7, 1, 1, 1, 1],
    [7, 5, 7, 5, 7],
    [7, 5, 7, 1, 7],
    [7, 1, 3, 0, 2],
];

fn meter_image(percent: Option<f64>, mode: &str) -> tauri::image::Image<'static> {
    let size = 36usize;
    let mut rgba = vec![0u8; size * size * 4];
    let mut ink = |x: usize, y: usize| {
        let offset = (y * size + x) * 4;
        rgba[offset..offset + 4].copy_from_slice(&[57, 122, 224, 255]);
    };
    if mode == "percent" || percent.is_none() {
        let text = percent
            .map(|p| format!("{:.0}", p))
            .unwrap_or_else(|| "?".into());
        let scale = if text.len() == 3 { 3 } else { 4 };
        let width = text.len() * 4 * scale - scale;
        let left = (size - width) / 2;
        for (i, c) in text.bytes().enumerate() {
            let digit = if c == b'?' { 10 } else { (c - b'0') as usize };
            for (row, bits) in DIGITS[digit].iter().enumerate() {
                for col in 0..3 {
                    if bits & (1 << (2 - col)) != 0 {
                        for dy in 0..scale {
                            for dx in 0..scale {
                                ink(
                                    left + i * 4 * scale + col * scale + dx,
                                    (size - 5 * scale) / 2 + row * scale + dy,
                                );
                            }
                        }
                    }
                }
            }
        }
    } else {
        let fraction = percent.unwrap_or(0.0) / 100.0;
        for y in 0..size {
            for x in 0..size {
                let dx = x as f64 + 0.5 - 18.0;
                let dy = y as f64 + 0.5 - 18.0;
                let filled = if mode == "circle" {
                    let radius = dx.hypot(dy);
                    (14.0..=16.0).contains(&radius)
                        || (radius < 12.0 && (y as f64 + 0.5) >= 30.0 - 24.0 * fraction)
                } else {
                    let border = (2..34).contains(&x)
                        && (11..25).contains(&y)
                        && (!(4..32).contains(&x) || !(13..23).contains(&y));
                    border
                        || ((5..31).contains(&x)
                            && (14..22).contains(&y)
                            && ((x - 5) as f64) < 26.0 * fraction)
                };
                if filled {
                    ink(x, y);
                }
            }
        }
    }
    tauri::image::Image::new_owned(rgba, size as u32, size as u32)
}

#[tauri::command]
pub fn update_tray(
    app: AppHandle,
    percent: Option<f64>,
    weekly_percent: Option<f64>,
    mode: String,
    is_upper_bound: bool,
    is_stale: bool,
    english: bool,
) -> Result<(), String> {
    validate_remaining(percent, weekly_percent, &mode)?;
    let tray = app.tray_by_id("main").ok_or("tray_unavailable")?;
    tray.set_icon(Some(meter_image(percent, &mode)))
        .map_err(|_| "tray_update_failed")?;
    tray.set_tooltip(Some(tooltip(
        percent,
        weekly_percent,
        is_upper_bound,
        is_stale,
        english,
    )))
    .map_err(|_| "tray_update_failed")?;
    Ok(())
}

pub fn setup(app: &tauri::App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "CodexBar Cockpit", true, None::<&str>)?;
    let refresh = MenuItem::with_id(app, "refresh", "Refresh / 刷新", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings / 设置", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit / 退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &refresh, &settings, &quit])?;
    TrayIconBuilder::with_id("main")
        .icon(meter_image(None, "circle"))
        .tooltip("CodexBar Cockpit · —")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => toggle_panel(app, None),
            "refresh" => {
                let _ = app.emit_to("widget", "refresh-requested", ());
            }
            "settings" => {
                let _ = show_panel(app, None);
                let _ = app.emit_to("widget", "open-settings", ());
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                position,
                ..
            } = event
            {
                toggle_panel(tray.app_handle(), Some((position.x, position.y)));
            }
        })
        .build(app)?;
    Ok(())
}

pub fn run_smoke_test() {
    // This separate builder has no plugins, invoke handlers, state loaders, collectors or HTTP clients.
    // Frontend calls therefore cannot read provider credentials or start cloud synchronization.
    let app = tauri::Builder::default().setup(|app| {
        setup(app)?;
        show_panel(app.handle(), None).map_err(std::io::Error::other)?;
        let handle = app.handle().clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            let healthy = handle.tray_by_id("main").is_some()
                && handle.get_webview_window("widget").is_some_and(|window| window.is_visible().unwrap_or(false));
            if healthy {
                if let Some(path) = std::env::var_os("COCKPIT_SMOKE_OUTPUT") {
                    let value = serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,"tray":true,"panel":true,"isolated":true});
                    if std::fs::write(path, value.to_string()).is_err() { handle.exit(2); return; }
                }
            }
            handle.exit(if healthy { 0 } else { 1 });
        });
        Ok(())
    }).build(crate::app_context()).expect("failed to build isolated tray smoke test");
    app.run(|_, _| {});
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn panel_stays_inside_dpi_scaled_work_area_on_negative_monitor() {
        for scale in [1.0, 1.5, 2.0] {
            for anchor in [(-1900.0, 0.0), (-10.0, 1080.0), (-960.0, 30.0)] {
                let p = placement(anchor, (-1920, 30, 1920, 1010), scale);
                assert!(p.x >= -1920 && p.y >= 30);
                assert!(i64::from(p.x) + i64::from(p.width) <= 0);
                assert!(i64::from(p.y) + i64::from(p.height) <= 1040);
            }
        }
    }
    #[test]
    fn very_small_work_area_shrinks_the_panel() {
        let p = placement((200.0, 200.0), (0, 0, 320, 240), 2.0);
        assert!(p.width <= 320 && p.height <= 240);
        assert!(p.x >= 0 && p.y >= 0);
    }
    #[test]
    fn malformed_values_cannot_become_known_zero() {
        assert!(validate_remaining(None, None, "circle").is_ok());
        assert!(validate_remaining(Some(0.0), Some(0.0), "bar").is_ok());
        for value in [f64::NAN, f64::INFINITY, -1.0, 101.0] {
            assert!(validate_remaining(Some(value), Some(10.0), "circle").is_err());
        }
        assert!(validate_remaining(Some(50.0), None, "bar").is_err());
        assert!(validate_remaining(None, None, "ring").is_err());
    }
    #[test]
    fn meters_increase_continuously_and_unknown_is_distinct() {
        for mode in ["bar", "circle", "percent"] {
            let unknown = meter_image(None, mode);
            let zero = meter_image(Some(0.0), mode);
            assert_ne!(unknown.rgba(), zero.rgba());
            if mode != "percent" {
                let counts: Vec<_> = [0.0, 25.0, 75.0, 100.0]
                    .into_iter()
                    .map(|p| {
                        meter_image(Some(p), mode)
                            .rgba()
                            .chunks_exact(4)
                            .filter(|p| p[3] > 0)
                            .count()
                    })
                    .collect();
                assert!(counts.windows(2).all(|pair| pair[0] < pair[1]));
            }
        }
        assert!(tooltip(Some(75.0), Some(15.0), true, true, true).contains("≈≤75.0%"));
        assert!(tooltip(None, None, false, false, false).contains("今日还能用 —"));
    }
}
