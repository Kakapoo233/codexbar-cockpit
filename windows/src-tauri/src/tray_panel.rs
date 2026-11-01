//! Tray panel lifecycle and daily-allowance images. No credentials or provider I/O live here.
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WindowEvent,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DisplayMode {
    Tray,
    Floating,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum PanelSurface {
    Compact,
    Panel,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WindowVisibility {
    Preserve,
    Reveal,
}

fn apply_visibility(
    visibility: WindowVisibility,
    reveal: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    if visibility == WindowVisibility::Reveal {
        reveal()?;
    }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelPresentation {
    display_mode: DisplayMode,
    surface: PanelSurface,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_page: Option<String>,
}

#[derive(Clone, Copy, Debug)]
struct DisplayPreferences {
    mode: DisplayMode,
    font_scale: f64,
    always_on_top: bool,
}

impl From<&crate::models::WidgetPreferences> for DisplayPreferences {
    fn from(value: &crate::models::WidgetPreferences) -> Self {
        Self {
            mode: if value.display_mode == "floating" {
                DisplayMode::Floating
            } else {
                DisplayMode::Tray
            },
            font_scale: if value.font_scale.is_finite() {
                value.font_scale.clamp(1.0, 2.0)
            } else {
                1.0
            },
            always_on_top: value.always_on_top,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct FloatingPosition {
    x: i32,
    y: i32,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedFloatingPosition {
    version: u8,
    x: i32,
    y: i32,
}

#[derive(Clone, Debug)]
struct PanelState {
    preferences: DisplayPreferences,
    surface: PanelSurface,
    target_page: Option<String>,
    position: Option<FloatingPosition>,
}

impl PanelState {
    fn presentation(&self) -> PanelPresentation {
        PanelPresentation {
            display_mode: self.preferences.mode,
            surface: self.surface,
            target_page: self.target_page.clone(),
        }
    }
}

struct PanelController {
    state: Mutex<PanelState>,
    operation: Mutex<()>,
    generation: AtomicU64,
    move_generation: AtomicU64,
    position_path: Option<PathBuf>,
    position_write: Mutex<()>,
}

fn load_position(path: &Path) -> Option<FloatingPosition> {
    if fs::metadata(path).ok()?.len() > 1024 {
        return None;
    }
    let saved: SavedFloatingPosition = serde_json::from_slice(&fs::read(path).ok()?).ok()?;
    (saved.version == 1).then_some(FloatingPosition {
        x: saved.x,
        y: saved.y,
    })
}

fn persist_position(path: &Path, position: FloatingPosition) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|_| "floating_position_directory_failed")?;
    }
    if path.exists() && load_position(path).is_none() {
        // An unknown or damaged document is retained; it must not become a fresh empty position.
        return Err("floating_position_document_unreadable".into());
    }
    let value = SavedFloatingPosition {
        version: 1,
        x: position.x,
        y: position.y,
    };
    let bytes = serde_json::to_vec(&value).map_err(|_| "floating_position_serialize_failed")?;
    let temporary = path.with_extension("json.tmp");
    let mut file = fs::File::create(&temporary).map_err(|_| "floating_position_write_failed")?;
    file.write_all(&bytes)
        .and_then(|_| file.sync_all())
        .map_err(|_| "floating_position_write_failed")?;
    drop(file);
    fs::rename(&temporary, path).map_err(|_| "floating_position_replace_failed".to_string())
}

pub fn initialize(
    app: &tauri::App,
    preferences: &crate::models::WidgetPreferences,
    position_path: Option<PathBuf>,
) -> Result<(), String> {
    if app.try_state::<PanelController>().is_some() {
        return Err("panel_already_initialized".into());
    }
    let preferences = DisplayPreferences::from(preferences);
    let position = position_path.as_deref().and_then(load_position);
    app.manage(PanelController {
        state: Mutex::new(PanelState {
            preferences,
            surface: if preferences.mode == DisplayMode::Floating {
                PanelSurface::Compact
            } else {
                PanelSurface::Panel
            },
            target_page: None,
            position,
        }),
        operation: Mutex::new(()),
        generation: AtomicU64::new(0),
        move_generation: AtomicU64::new(0),
        position_path,
        position_write: Mutex::new(()),
    });
    Ok(())
}

#[tauri::command]
pub fn get_panel_presentation(app: AppHandle) -> Result<PanelPresentation, String> {
    snapshot(&app)
}

fn snapshot(app: &AppHandle) -> Result<PanelPresentation, String> {
    app.try_state::<PanelController>()
        .ok_or("panel_state_unavailable")?
        .state
        .lock()
        .map(|state| state.presentation())
        .map_err(|_| "panel_state_unavailable".into())
}

fn floating_placement(
    position: Option<FloatingPosition>,
    bounds: (i32, i32, u32, u32),
    scale: f64,
    font_scale: f64,
) -> Placement {
    let scale = if scale.is_finite() && scale > 0.0 {
        scale
    } else {
        1.0
    };
    let font_scale = if font_scale.is_finite() {
        font_scale.clamp(1.0, 2.0)
    } else {
        1.0
    };
    let margin = (8.0 * scale).round() as i64;
    let (left, top, work_width, work_height) = bounds;
    let width = (340.0 * scale * font_scale)
        .round()
        .min(f64::from(work_width.saturating_sub((margin * 2) as u32)))
        .max(1.0) as u32;
    let height = (170.0 * scale * font_scale)
        .round()
        .min(f64::from(work_height.saturating_sub((margin * 2) as u32)))
        .max(1.0) as u32;
    let min_x = i64::from(left) + margin.min(i64::from(work_width.saturating_sub(width)));
    let min_y = i64::from(top) + margin.min(i64::from(work_height.saturating_sub(height)));
    let max_x = (i64::from(left) + i64::from(work_width) - i64::from(width) - margin).max(min_x);
    let max_y = (i64::from(top) + i64::from(work_height) - i64::from(height) - margin).max(min_y);
    let x = position
        .map(|point| i64::from(point.x))
        .unwrap_or(max_x)
        .clamp(min_x, max_x);
    let y = position
        .map(|point| i64::from(point.y))
        .unwrap_or(min_y)
        .clamp(min_y, max_y);
    Placement {
        x: x as i32,
        y: y as i32,
        width,
        height,
    }
}

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

fn apply_surface_locked(
    app: &AppHandle,
    controller: &PanelController,
    surface: PanelSurface,
    target_page: Option<String>,
    anchor: Option<(f64, f64)>,
    visibility: WindowVisibility,
) -> Result<PanelPresentation, String> {
    let before = controller
        .state
        .lock()
        .map_err(|_| "panel_state_unavailable")?
        .clone();
    if surface == PanelSurface::Compact && before.preferences.mode != DisplayMode::Floating {
        return Err("floating_display_disabled".into());
    }
    let window = app
        .get_webview_window("widget")
        .ok_or("panel_unavailable")?;
    let anchor = if surface == PanelSurface::Compact {
        before
            .position
            .map(|point| (f64::from(point.x), f64::from(point.y)))
    } else {
        anchor.or_else(|| {
            window
                .cursor_position()
                .ok()
                .map(|point| (point.x, point.y))
        })
    };
    let monitor = anchor
        .and_then(|point| window.monitor_from_point(point.0, point.1).ok().flatten())
        .or_else(|| window.primary_monitor().ok().flatten())
        .ok_or("monitor_unavailable")?;
    let work = monitor.work_area();
    let bounds = (
        work.position.x,
        work.position.y,
        work.size.width,
        work.size.height,
    );
    let target = if surface == PanelSurface::Compact {
        floating_placement(
            before.position,
            bounds,
            monitor.scale_factor(),
            before.preferences.font_scale,
        )
    } else {
        placement(anchor.unwrap_or((0.0, 0.0)), bounds, monitor.scale_factor())
    };
    controller.generation.fetch_add(1, Ordering::SeqCst);
    {
        let mut state = controller
            .state
            .lock()
            .map_err(|_| "panel_state_unavailable")?;
        state.surface = surface;
        state.target_page = target_page;
        if surface == PanelSurface::Compact {
            state.position = Some(FloatingPosition {
                x: target.x,
                y: target.y,
            });
        }
    }
    let apply = || -> Result<(), String> {
        window
            .set_min_size(Some(tauri::LogicalSize::new(1.0, 1.0)))
            .map_err(|_| "panel_size_failed")?;
        window
            .set_always_on_top(before.preferences.always_on_top)
            .map_err(|_| "panel_level_failed")?;
        window
            .set_size(PhysicalSize::new(target.width, target.height))
            .map_err(|_| "panel_size_failed")?;
        window
            .set_position(PhysicalPosition::new(target.x, target.y))
            .map_err(|_| "panel_position_failed")?;
        apply_visibility(visibility, || {
            window.show().map_err(|_| "panel_show_failed")?;
            if surface == PanelSurface::Panel {
                window.set_focus().map_err(|_| "panel_focus_failed")?;
            }
            Ok(())
        })?;
        Ok(())
    };
    if let Err(error) = apply() {
        if let Ok(mut state) = controller.state.lock() {
            *state = before;
        }
        return Err(error);
    }
    let presentation = snapshot(app)?;
    let _ = app.emit_to("widget", "panel-presentation-changed", presentation.clone());
    if surface == PanelSurface::Panel {
        let _ = app.emit_to("widget", "panel-shown", ());
    }
    Ok(presentation)
}

fn show_surface(
    app: &AppHandle,
    surface: PanelSurface,
    target_page: Option<String>,
    anchor: Option<(f64, f64)>,
) -> Result<PanelPresentation, String> {
    let controller = app
        .try_state::<PanelController>()
        .ok_or("panel_state_unavailable")?;
    let _operation = controller
        .operation
        .lock()
        .map_err(|_| "panel_operation_unavailable")?;
    apply_surface_locked(
        app,
        &controller,
        surface,
        target_page,
        anchor,
        WindowVisibility::Reveal,
    )
}

pub fn show_panel(app: &AppHandle, anchor: Option<(f64, f64)>) -> Result<(), String> {
    show_surface(app, PanelSurface::Panel, None, anchor).map(|_| ())
}

#[tauri::command(async)]
pub fn show_full_panel(
    app: AppHandle,
    target_page: Option<String>,
) -> Result<PanelPresentation, String> {
    if target_page
        .as_deref()
        .is_some_and(|page| !matches!(page, "usage" | "settings"))
    {
        return Err("invalid_panel_page".into());
    }
    show_surface(&app, PanelSurface::Panel, target_page, None)
}

#[tauri::command(async)]
pub fn show_floating_panel(app: AppHandle) -> Result<PanelPresentation, String> {
    show_surface(&app, PanelSurface::Compact, None, None)
}

#[tauri::command(async)]
pub fn hide_panel(app: AppHandle) -> Result<(), String> {
    let controller = app
        .try_state::<PanelController>()
        .ok_or("panel_state_unavailable")?;
    let _operation = controller
        .operation
        .lock()
        .map_err(|_| "panel_operation_unavailable")?;
    controller.generation.fetch_add(1, Ordering::SeqCst);
    app.get_webview_window("widget")
        .ok_or("panel_unavailable")?
        .hide()
        .map_err(|_| "panel_hide_failed".into())
}

#[tauri::command(async)]
pub fn compact_panel(app: AppHandle) -> Result<PanelPresentation, String> {
    if snapshot(&app)?.display_mode == DisplayMode::Floating {
        return show_floating_panel(app);
    }
    hide_panel(app.clone())?;
    snapshot(&app)
}

#[tauri::command(async)]
pub fn begin_floating_drag(app: AppHandle) -> Result<(), String> {
    let presentation = snapshot(&app)?;
    if presentation.display_mode != DisplayMode::Floating
        || presentation.surface != PanelSurface::Compact
    {
        return Err("floating_drag_unavailable".into());
    }
    let controller = app
        .try_state::<PanelController>()
        .ok_or("panel_state_unavailable")?;
    controller.generation.fetch_add(1, Ordering::SeqCst);
    app.get_webview_window("widget")
        .ok_or("panel_unavailable")?
        .start_dragging()
        .map_err(|_| "floating_drag_failed".into())
}

pub fn restore_on_startup(app: &AppHandle) -> Result<(), String> {
    if snapshot(app)?.display_mode == DisplayMode::Floating {
        show_floating_panel(app.clone())?;
    }
    Ok(())
}

fn surface_after_preferences(
    previous: DisplayMode,
    next: DisplayMode,
    surface: PanelSurface,
) -> (PanelSurface, WindowVisibility) {
    if previous == next {
        (surface, WindowVisibility::Preserve)
    } else if next == DisplayMode::Floating {
        (PanelSurface::Compact, WindowVisibility::Reveal)
    } else {
        (PanelSurface::Panel, WindowVisibility::Reveal)
    }
}

pub fn apply_display_preferences(
    app: &AppHandle,
    preferences: &crate::models::WidgetPreferences,
) -> Result<(), String> {
    let controller = app
        .try_state::<PanelController>()
        .ok_or("panel_state_unavailable")?;
    let _operation = controller
        .operation
        .lock()
        .map_err(|_| "panel_operation_unavailable")?;
    let next = DisplayPreferences::from(preferences);
    let (changed, (surface, visibility)) = {
        let mut state = controller
            .state
            .lock()
            .map_err(|_| "panel_state_unavailable")?;
        let changed = state.preferences.mode != next.mode;
        let surface = surface_after_preferences(state.preferences.mode, next.mode, state.surface);
        state.preferences = next;
        (changed, surface)
    };
    if changed || surface == PanelSurface::Compact {
        apply_surface_locked(app, &controller, surface, None, None, visibility)?;
    } else {
        // Font and pin changes in full Settings must not dismiss that page.
        app.get_webview_window("widget")
            .ok_or("panel_unavailable")?
            .set_always_on_top(next.always_on_top)
            .map_err(|_| "panel_level_failed")?;
    }
    Ok(())
}

fn toggle_panel(app: &AppHandle, anchor: Option<(f64, f64)>) {
    let Some(window) = app.get_webview_window("widget") else {
        return;
    };
    let Ok(presentation) = snapshot(app) else {
        return;
    };
    if !window.is_visible().unwrap_or(false) {
        if presentation.display_mode == DisplayMode::Floating {
            let _ = show_floating_panel(app.clone());
        } else {
            let _ = show_panel(app, anchor);
        }
    } else if presentation.surface == PanelSurface::Compact {
        let _ = show_panel(app, anchor);
    } else {
        let _ = compact_panel(app.clone());
    }
}

#[cfg(windows)]
fn foreground_belongs_to_this_process() -> bool {
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId,
    };
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum BlurAction {
    Keep,
    Compact,
    Hide,
}

fn blur_action(mode: DisplayMode, surface: PanelSurface) -> BlurAction {
    if surface == PanelSurface::Compact {
        BlurAction::Keep
    } else if mode == DisplayMode::Floating {
        BlurAction::Compact
    } else {
        BlurAction::Hide
    }
}

fn blur_is_current(expected: u64, actual: u64, surface: PanelSurface) -> bool {
    expected == actual && surface == PanelSurface::Panel
}

fn remember_floating_position(window: &tauri::Window, position: PhysicalPosition<i32>) {
    let app = window.app_handle();
    let Some(controller) = app.try_state::<PanelController>() else {
        return;
    };
    let point = FloatingPosition {
        x: position.x,
        y: position.y,
    };
    let Ok(mut state) = controller.state.lock() else {
        return;
    };
    if state.surface != PanelSurface::Compact {
        return;
    }
    state.position = Some(point);
    drop(state);
    let generation = controller.move_generation.fetch_add(1, Ordering::SeqCst) + 1;
    if controller.position_path.is_none() {
        return;
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        let Some(controller) = app.try_state::<PanelController>() else {
            return;
        };
        if controller.move_generation.load(Ordering::SeqCst) != generation {
            return;
        }
        let Ok(_write) = controller.position_write.lock() else {
            return;
        };
        if controller.move_generation.load(Ordering::SeqCst) != generation {
            return;
        }
        if let Some(path) = controller.position_path.as_deref() {
            if persist_position(path, point).is_err() {
                eprintln!("floating position could not be saved");
            }
        }
    });
}

pub fn flush_position(app: &AppHandle) {
    let Some(controller) = app.try_state::<PanelController>() else {
        return;
    };
    let (Some(path), Ok(state)) = (controller.position_path.as_deref(), controller.state.lock())
    else {
        return;
    };
    let position = state.position;
    drop(state);
    let Some(position) = position else {
        return;
    };
    let Ok(_write) = controller.position_write.lock() else {
        return;
    };
    if persist_position(path, position).is_err() {
        eprintln!("floating position could not be saved at exit");
    }
}

pub fn handle_window_event(window: &tauri::Window, event: &WindowEvent) {
    if window.label() != "widget" {
        return;
    }
    let Some(controller) = window.app_handle().try_state::<PanelController>() else {
        return;
    };
    match event {
        WindowEvent::CloseRequested { api, .. } => {
            api.prevent_close();
            let generation = controller.generation.load(Ordering::SeqCst);
            let app = window.app_handle().clone();
            tauri::async_runtime::spawn(async move {
                let Some(controller) = app.try_state::<PanelController>() else {
                    return;
                };
                let Ok(_operation) = controller.operation.lock() else {
                    return;
                };
                if controller.generation.load(Ordering::SeqCst) != generation {
                    return;
                }
                let Ok(presentation) = snapshot(&app) else {
                    return;
                };
                if presentation.surface == PanelSurface::Panel
                    && presentation.display_mode == DisplayMode::Floating
                {
                    let _ = apply_surface_locked(
                        &app,
                        &controller,
                        PanelSurface::Compact,
                        None,
                        None,
                        WindowVisibility::Reveal,
                    );
                } else {
                    controller.generation.fetch_add(1, Ordering::SeqCst);
                    if let Some(window) = app.get_webview_window("widget") {
                        let _ = window.hide();
                    }
                }
            });
        }
        WindowEvent::Moved(position) => remember_floating_position(window, *position),
        WindowEvent::Focused(true) => {
            controller.generation.fetch_add(1, Ordering::SeqCst);
        }
        WindowEvent::Focused(false) => {
            let Ok(presentation) = snapshot(window.app_handle()) else {
                return;
            };
            if blur_action(presentation.display_mode, presentation.surface) == BlurAction::Keep {
                return;
            }
            let generation = controller.generation.load(Ordering::SeqCst);
            let window = window.clone();
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(150)).await;
                if window.is_focused().unwrap_or(true) || foreground_belongs_to_this_process() {
                    return;
                }
                let app = window.app_handle();
                let Some(controller) = app.try_state::<PanelController>() else {
                    return;
                };
                let Ok(_operation) = controller.operation.lock() else {
                    return;
                };
                let Ok(presentation) = snapshot(app) else {
                    return;
                };
                if !blur_is_current(
                    generation,
                    controller.generation.load(Ordering::SeqCst),
                    presentation.surface,
                ) || !window.is_visible().unwrap_or(false)
                {
                    return;
                }
                match blur_action(presentation.display_mode, presentation.surface) {
                    BlurAction::Keep => {}
                    BlurAction::Compact => {
                        let _ = apply_surface_locked(
                            app,
                            &controller,
                            PanelSurface::Compact,
                            None,
                            None,
                            WindowVisibility::Reveal,
                        );
                    }
                    BlurAction::Hide => {
                        controller.generation.fetch_add(1, Ordering::SeqCst);
                        let _ = window.hide();
                    }
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
    if app.try_state::<PanelController>().is_none() {
        initialize(app, &crate::models::WidgetPreferences::default(), None)
            .map_err(std::io::Error::other)?;
    }
    let show = MenuItem::with_id(app, "show", "CodexBar Cockpit", true, None::<&str>)?;
    let summary = MenuItem::with_id(
        app,
        "summary",
        "Floating window / 悬浮窗",
        true,
        None::<&str>,
    )?;
    let refresh = MenuItem::with_id(app, "refresh", "Refresh / 刷新", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings / 设置", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit / 退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &summary, &refresh, &settings, &quit])?;
    TrayIconBuilder::with_id("main")
        .icon(meter_image(None, "circle"))
        .tooltip("CodexBar Cockpit · —")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            let app = app.clone();
            let id = event.id.as_ref().to_string();
            tauri::async_runtime::spawn(async move {
                let app = &app;
                match id.as_str() {
                    "show" => {
                        let _ = show_full_panel(app.clone(), Some("usage".into()));
                    }
                    "summary" => {
                        if snapshot(app)
                            .is_ok_and(|value| value.display_mode == DisplayMode::Floating)
                        {
                            let _ = show_floating_panel(app.clone());
                        } else {
                            let _ = show_full_panel(app.clone(), Some("settings".into()));
                        }
                    }
                    "refresh" => {
                        let _ = app.emit_to("widget", "refresh-requested", ());
                    }
                    "settings" => {
                        let _ = show_full_panel(app.clone(), Some("settings".into()));
                    }
                    "quit" => app.exit(0),
                    _ => {}
                }
            });
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                position,
                ..
            } = event
            {
                let app = tray.app_handle().clone();
                tauri::async_runtime::spawn(async move {
                    toggle_panel(&app, Some((position.x, position.y)));
                });
            }
        })
        .build(app)?;
    Ok(())
}

/// A persistent, visible WebView2 window for synthetic UI checks. Unlike normal startup it has no
/// collectors, app state, credentials, command handlers, plugins, tray, or single-instance callback.
pub fn run_ui_preview() {
    let profile = PreviewProfile::create().expect("failed to create temporary UI preview profile");
    let mut context = crate::app_context();
    let mut window_config = context
        .config()
        .app
        .windows
        .iter()
        .find(|window| window.label == "widget")
        .cloned()
        .expect("missing panel configuration for UI preview");
    window_config.label = "ui-preview".into();
    let compact = std::env::args().any(|arg| arg == "--floating-preview");
    window_config.url = tauri::WebviewUrl::App(if compact {
        "index.html?synthetic-preview=1&surface=compact&sample=usage".into()
    } else {
        "index.html?synthetic-preview=1".into()
    });
    if compact {
        window_config.min_width = Some(1.0);
        window_config.min_height = Some(1.0);
        window_config.width = 340.0;
        window_config.height = 170.0;
    }
    window_config.title = "CodexBar Cockpit - Synthetic UI Preview".into();
    window_config.visible = true;
    window_config.focus = true;
    window_config.skip_taskbar = false;
    window_config.always_on_top = false;
    window_config.decorations = true;
    window_config.resizable = true;
    context.config_mut().app.windows.clear();
    context.config_mut().identifier.push_str(".ui-preview");
    context.config_mut().app.security.csp = Some(tauri::utils::config::Csp::Policy(
        "default-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'none'; img-src 'self' data:"
            .into(),
    ));
    let data_directory = profile.0.clone();
    let app = tauri::Builder::default()
        .setup(move |app| {
            tauri::WebviewWindowBuilder::from_config(app, &window_config)?
                .data_directory(data_directory.clone())
                .incognito(true)
                .on_navigation(preview_navigation_allowed)
                .on_new_window(|_, _| tauri::webview::NewWindowResponse::Deny)
                .build()?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, WindowEvent::CloseRequested { .. }) {
                window.app_handle().exit(0);
            }
        })
        .build(context)
        .expect("failed to build isolated UI preview");
    app.run(|_, _| {});
    drop(profile);
}

fn preview_navigation_allowed(url: &tauri::Url) -> bool {
    url.as_str() == "about:blank"
        || (matches!(url.scheme(), "http" | "https" | "tauri")
            && matches!(
                url.host_str(),
                Some("localhost" | "127.0.0.1" | "tauri.localhost")
            )
            && matches!(url.path(), "/" | "/index.html")
            && url
                .query_pairs()
                .any(|(key, value)| key == "synthetic-preview" && value == "1"))
}

struct PreviewProfile(std::path::PathBuf);

impl PreviewProfile {
    fn create() -> std::io::Result<Self> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(std::io::Error::other)?
            .as_nanos();
        for attempt in 0..32 {
            let directory = std::env::temp_dir().join(format!(
                "codexbar-cockpit-ui-preview-{}-{timestamp}-{attempt}",
                std::process::id()
            ));
            match std::fs::create_dir(&directory) {
                Ok(()) => return Ok(Self(directory)),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(std::io::Error::other(
            "could not allocate a fresh UI preview profile",
        ))
    }
}

impl Drop for PreviewProfile {
    fn drop(&mut self) {
        // WebView2 may briefly retain a file handle after exit. Leaving a uniquely created temporary
        // profile in that case is safer than touching any existing app profile.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub fn run_smoke_test() {
    // This separate builder has no plugins, invoke handlers, state loaders, collectors or HTTP clients.
    // Frontend calls therefore cannot read provider credentials or start cloud synchronization.
    let floating = std::env::args().any(|arg| arg == "--smoke-floating");
    let app = tauri::Builder::default().setup(move |app| {
        if floating {
            let preferences = crate::models::WidgetPreferences {
                display_mode: "floating".into(), font_scale: 1.0, ..Default::default()
            };
            initialize(app, &preferences, None).map_err(std::io::Error::other)?;
        }
        setup(app)?;
        if floating { show_floating_panel(app.handle().clone()).map_err(std::io::Error::other)?; }
        else { show_panel(app.handle(), None).map_err(std::io::Error::other)?; }
        let handle = app.handle().clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            let healthy = handle.tray_by_id("main").is_some()
                && handle.get_webview_window("widget").is_some_and(|window| window.is_visible().unwrap_or(false));
            let presentation = snapshot(&handle).ok();
            let healthy = healthy && presentation.as_ref().is_some_and(|value| value.surface ==
                if floating { PanelSurface::Compact } else { PanelSurface::Panel });
            if healthy {
                if let Some(path) = std::env::var_os("COCKPIT_SMOKE_OUTPUT") {
                    let value = serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,"tray":true,"panel":true,"isolated":true,"floating":floating,"presentation":presentation});
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
    fn compact_geometry_scales_with_text_and_dpi_without_leaving_work_area() {
        assert_eq!(
            floating_placement(None, (0, 0, 1920, 1040), 1.0, 1.0),
            Placement {
                x: 1572,
                y: 8,
                width: 340,
                height: 170
            }
        );
        for scale in [1.0, 1.5, 2.0] {
            for font in [1.0, 1.5, 2.0] {
                let p = floating_placement(
                    Some(FloatingPosition { x: -1900, y: 900 }),
                    (-1920, 30, 1920, 1010),
                    scale,
                    font,
                );
                assert!(p.x >= -1920 && p.y >= 30);
                assert!(i64::from(p.x) + i64::from(p.width) <= 0);
                assert!(i64::from(p.y) + i64::from(p.height) <= 1040);
            }
        }
    }
    #[test]
    fn stale_monitor_positions_and_small_screens_are_clamped() {
        for position in [
            FloatingPosition {
                x: i32::MIN,
                y: i32::MAX,
            },
            FloatingPosition { x: 4000, y: -500 },
        ] {
            let p = floating_placement(Some(position), (0, 0, 280, 150), 2.0, 2.0);
            assert!(p.x >= 0 && p.y >= 0);
            assert!(i64::from(p.x) + i64::from(p.width) <= 280);
            assert!(i64::from(p.y) + i64::from(p.height) <= 150);
        }
    }
    #[test]
    fn floating_surface_keeps_focus_independence_and_old_blur_callbacks_cannot_collapse_new_panels()
    {
        assert_eq!(
            blur_action(DisplayMode::Floating, PanelSurface::Compact),
            BlurAction::Keep
        );
        assert_eq!(
            blur_action(DisplayMode::Floating, PanelSurface::Panel),
            BlurAction::Compact
        );
        assert_eq!(
            blur_action(DisplayMode::Tray, PanelSurface::Panel),
            BlurAction::Hide
        );
        assert!(blur_is_current(4, 4, PanelSurface::Panel));
        assert!(!blur_is_current(4, 5, PanelSurface::Panel));
        assert!(!blur_is_current(4, 4, PanelSurface::Compact));
    }
    #[test]
    fn font_and_pin_changes_do_not_dismiss_full_settings() {
        assert_eq!(
            surface_after_preferences(
                DisplayMode::Floating,
                DisplayMode::Floating,
                PanelSurface::Panel
            ),
            (PanelSurface::Panel, WindowVisibility::Preserve)
        );
        assert_eq!(
            surface_after_preferences(
                DisplayMode::Floating,
                DisplayMode::Floating,
                PanelSurface::Compact
            ),
            (PanelSurface::Compact, WindowVisibility::Preserve)
        );
        assert_eq!(
            surface_after_preferences(
                DisplayMode::Tray,
                DisplayMode::Floating,
                PanelSurface::Panel
            ),
            (PanelSurface::Compact, WindowVisibility::Reveal)
        );
        assert_eq!(
            surface_after_preferences(
                DisplayMode::Floating,
                DisplayMode::Tray,
                PanelSurface::Compact
            ),
            (PanelSurface::Panel, WindowVisibility::Reveal)
        );
    }
    #[test]
    fn same_mode_preference_save_cannot_reveal_a_hidden_floating_surface() {
        use std::cell::Cell;
        let visibility_after_save = |previous, next, visible| {
            let visible = Cell::new(visible);
            let (_, request) = surface_after_preferences(previous, next, PanelSurface::Compact);
            apply_visibility(request, || {
                visible.set(true);
                Ok(())
            })
            .unwrap();
            visible.get()
        };
        for visible in [false, true] {
            assert_eq!(
                visibility_after_save(DisplayMode::Floating, DisplayMode::Floating, visible),
                visible
            );
        }
        assert!(visibility_after_save(
            DisplayMode::Tray,
            DisplayMode::Floating,
            false
        ));
        assert!(visibility_after_save(
            DisplayMode::Floating,
            DisplayMode::Tray,
            false
        ));
        let explicitly_shown = Cell::new(false);
        apply_visibility(WindowVisibility::Reveal, || {
            explicitly_shown.set(true);
            Ok(())
        })
        .unwrap();
        assert!(explicitly_shown.get());
    }
    #[test]
    fn floating_position_documents_roundtrip_and_unknown_formats_remain_untouched() {
        let profile = PreviewProfile::create().unwrap();
        let path = profile.0.join("floating-window.json");
        let position = FloatingPosition { x: -920, y: 70 };
        assert_eq!(load_position(&path), None);
        persist_position(&path, position).unwrap();
        assert_eq!(load_position(&path), Some(position));
        let next = FloatingPosition { x: 20, y: 90 };
        persist_position(&path, next).unwrap();
        assert_eq!(load_position(&path), Some(next));
        for contents in [r#"{"version":2,"x":1,"y":1}"#, "broken"] {
            fs::write(&path, contents).unwrap();
            assert_eq!(load_position(&path), None);
            assert!(persist_position(&path, position).is_err());
            assert_eq!(fs::read_to_string(&path).unwrap(), contents);
        }
    }
    #[test]
    fn synthetic_preview_navigation_stays_on_its_explicit_local_page() {
        for value in [
            "http://tauri.localhost/index.html?synthetic-preview=1",
            "tauri://localhost/index.html?synthetic-preview=1",
            "http://localhost:1420/?synthetic-preview=1",
        ] {
            assert!(preview_navigation_allowed(&value.parse().unwrap()));
        }
        for value in [
            "https://example.com/index.html?synthetic-preview=1",
            "file:///index.html?synthetic-preview=1",
            "http://tauri.localhost/index.html",
            "http://tauri.localhost/index.html?synthetic-preview=0",
        ] {
            assert!(!preview_navigation_allowed(&value.parse().unwrap()));
        }
    }
    #[test]
    fn every_ui_preview_gets_a_fresh_temporary_profile() {
        let first = PreviewProfile::create().unwrap();
        let second = PreviewProfile::create().unwrap();
        assert_ne!(first.0, second.0);
        assert!(first.0.is_dir() && second.0.is_dir());
        assert_eq!(first.0.parent(), Some(std::env::temp_dir().as_path()));
        let first_path = first.0.clone();
        drop(first);
        assert!(!first_path.exists());
    }
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
