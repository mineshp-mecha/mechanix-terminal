use crate::terminal::{FlutterTerminal, TerminalFrame};
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};

pub use crate::terminal::TerminalCell;

use std::sync::OnceLock;

use std::thread;
use std::time::Duration;

static NEXT_ID: AtomicU32 = AtomicU32::new(1);

fn terminals() -> &'static RwLock<HashMap<u32, FlutterTerminal>> {
    static INSTANCE: OnceLock<RwLock<HashMap<u32, FlutterTerminal>>> = OnceLock::new();
    INSTANCE.get_or_init(|| RwLock::new(HashMap::new()))
}

fn active_id() -> &'static RwLock<u32> {
    static INSTANCE: OnceLock<RwLock<u32>> = OnceLock::new();
    INSTANCE.get_or_init(|| RwLock::new(0))
}

// Terminal Preferences
// FRB will generate a Dart mirror automatically for all fields below.

#[derive(Debug, Clone)]
pub struct TermPreferences {
    // Font (used Flutter-side by CustomPainter / TextPainter) 
    pub font_family: String,
    pub font_size: f64,
    pub line_height: f64,

    pub color_foreground: u32,
    pub color_background: u32,
    pub color_cursor: u32,
    pub color_selection: u32,
    pub palette: Vec<u32>,
}

impl Default for TermPreferences {
    fn default() -> Self {
        Self {
            font_family: "monospace".into(),
            font_size: 14.0,
            line_height: 1.2,
            color_foreground: 0xCDD6F4,
            color_background: 0x1E1E2E,
            color_cursor: 0xF5C2E7,
            color_selection: 0x45475A,
            palette: catppuccin_mocha_palette(),
        }
    }
}

/// Catppuccin Mocha 16-colour palette (indices 0-15).
fn catppuccin_mocha_palette() -> Vec<u32> {
    vec![
        0x45475A, // 0  Black
        0xF38BA8, // 1  Red
        0xA6E3A1, // 2  Green
        0xF9E2AF, // 3  Yellow
        0x89B4FA, // 4  Blue
        0xF5C2E7, // 5  Magenta
        0x94E2D5, // 6  Cyan
        0xBAC2DE, // 7  White
        0x585B70, // 8  Bright Black
        0xF38BA8, // 9  Bright Red
        0xA6E3A1, // 10 Bright Green
        0xF9E2AF, // 11 Bright Yellow
        0x89B4FA, // 12 Bright Blue
        0xF5C2E7, // 13 Bright Magenta
        0x94E2D5, // 14 Bright Cyan
        0xA6ADC8, // 15 Bright White
    ]
}

// Terminal management API

#[flutter_rust_bridge::frb(sync)]
pub fn add_terminal(rows: u16, cols: u16) -> u32 {
    add_terminal_with_prefs(rows, cols, TermPreferences::default())
}

#[flutter_rust_bridge::frb(sync)]
pub fn add_terminal_with_prefs(rows: u16, cols: u16, prefs: TermPreferences) -> u32 {
    let id = NEXT_ID.fetch_add(1, Ordering::SeqCst);
    let terminal = FlutterTerminal::new(rows, cols, prefs);
    let mut lock = terminals().write();
    lock.insert(id, terminal);

    let mut active_lock = active_id().write();
    if *active_lock == 0 {
        *active_lock = id;
    }

    id
}

#[flutter_rust_bridge::frb(sync)]
pub fn remove_terminal(id: u32) {
    let mut lock = terminals().write();
    lock.remove(&id);

    let mut active_lock = active_id().write();
    if *active_lock == id {
        if let Some(&new_id) = lock.keys().next() {
            *active_lock = new_id;
        } else {
            *active_lock = 0;
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_active_terminal(id: u32) {
    let mut active_lock = active_id().write();
    *active_lock = id;
}

/// Hot-reload preferences on a live terminal.
/// Colours take effect immediately; font changes only affect the Flutter renderer
#[flutter_rust_bridge::frb(sync)]
pub fn update_terminal_prefs(id: u32, prefs: TermPreferences) {
    let lock = terminals().read();
    if let Some(t) = lock.get(&id) {
        t.update_prefs(prefs);
    }
}

/// Convenience: return the current preferences for a terminal.
#[flutter_rust_bridge::frb(sync)]
pub fn get_terminal_prefs(id: u32) -> Option<TermPreferences> {
    let lock = terminals().read();
    lock.get(&id).map(|t| t.get_prefs())
}

use crate::frb_generated::StreamSink;

pub fn create_terminal_stream(sink: StreamSink<u32>) {
    thread::spawn(move || loop {
        {
            let lock = terminals().read();
            for (&id, terminal) in lock.iter() {
                if terminal.dirty.load(Ordering::SeqCst) {
                    let _ = sink.add(id);
                }
            }
        }
        thread::sleep(Duration::from_millis(16));
    });
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_terminal_frame(id: u32) -> Option<TerminalFrame> {
    let lock = terminals().read();
    lock.get(&id).and_then(|t| t.get_frame())
}

#[flutter_rust_bridge::frb(sync)]
pub fn send_input(id: u32, input: String) {
    let lock = terminals().read();
    if let Some(t) = lock.get(&id) {
        t.write(input);
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb(sync)]
pub fn scroll_terminal(id: u32, lines: i32) {
    let lock = terminals().read();
    if let Some(t) = lock.get(&id) {
        t.scroll(lines);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn load_config_prefs() -> TermPreferences {
    crate::config::load_prefs_from_alacritty_config().unwrap_or_default()
}

#[flutter_rust_bridge::frb(sync)]
pub fn save_config_prefs(prefs: TermPreferences) {
    let _ = crate::config::save_prefs_to_alacritty_config(&prefs);
}
