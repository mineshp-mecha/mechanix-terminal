use alacritty_terminal::event::VoidListener;
use alacritty_terminal::grid::{Dimensions, GridCell};
use alacritty_terminal::index::{Column, Line};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::grid::Scroll;
use alacritty_terminal::term::{Config as AlacrittyConfig, Term};
use alacritty_terminal::vte::ansi::{CursorShape as AlacCursorShape, CursorStyle};
use parking_lot::RwLock;
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::{Read, Write};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use vte::ansi;

use std::sync::atomic::{AtomicBool, Ordering};

use crate::api::simple::TermPreferences;

pub struct TerminalFrame {
    pub rows: u16,
    pub cols: u16,
    pub content: String,
    pub attributes: Vec<u32>, // Packed: 24 bits for FG/BG, 8 bits for flags
    pub cursor_x: u16,
    pub cursor_y: u16,
}

pub struct TerminalCell {
    pub content: String,
    pub fg: u32,
    pub bg: u32,
    pub bold: bool,
}


pub struct FlutterTerminal {
    term:   Arc<RwLock<Term<VoidListener>>>,
    writer: Arc<RwLock<SyncWriter>>,
    prefs:  Arc<RwLock<TermPreferences>>,
    pub dirty: Arc<AtomicBool>,
}

struct SyncWriter(Box<dyn Write + Send>);
unsafe impl Sync for SyncWriter {}

struct SimpleDimensions {
    cols: usize,
    rows: usize,
}

impl Dimensions for SimpleDimensions {
    fn columns(&self) -> usize { self.cols }
    fn screen_lines(&self) -> usize { self.rows }
    fn total_lines(&self) -> usize { 10000 }
}

#[derive(Default)]
struct NoopTimeout { _dummy: bool }

impl ansi::Timeout for NoopTimeout {
    fn set_timeout(&mut self, _: Duration) {}
    fn clear_timeout(&mut self) {}
    fn pending_timeout(&self) -> bool { false }
}

// Map TermPreferences → alacritty_terminal::Config

fn build_alacritty_config() -> AlacrittyConfig {
    AlacrittyConfig {
        scrolling_history: 10_000,
        default_cursor_style: CursorStyle {
            shape: AlacCursorShape::Block,
            blinking: false,
        },
        vi_mode_cursor_style: None,
        semantic_escape_chars: alacritty_terminal::term::SEMANTIC_ESCAPE_CHARS.to_owned(),
        kitty_keyboard: false,
        osc52: Default::default(),
    }
}

// ── FlutterTerminal ───────────────────────────────────────────────────────────

impl FlutterTerminal {
    pub fn new(rows: u16, cols: u16, prefs: TermPreferences) -> Self {
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .expect("openpty failed");

        let dims = SimpleDimensions { cols: cols as usize, rows: rows as usize };
        let config = build_alacritty_config();
        let term  = Term::new(config, &dims, VoidListener);
        let term  = Arc::new(RwLock::new(term));
        let dirty = Arc::new(AtomicBool::new(true));

        let _child = pair.slave.spawn_command(CommandBuilder::new("bash")).expect("spawn failed");

        let reader       = pair.master.try_clone_reader().expect("clone_reader failed");
        let writer       = pair.master.take_writer().expect("take_writer failed");
        let term_clone   = Arc::clone(&term);
        let dirty_clone  = Arc::clone(&dirty);

        thread::spawn(move || {
            let mut processor: ansi::Processor<NoopTimeout> = ansi::Processor::new();
            let mut reader = reader;
            let mut buf    = [0u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        let mut term_lock = term_clone.write();
                        processor.advance(&mut *term_lock, &buf[..n]);
                        dirty_clone.store(true, Ordering::SeqCst);
                    }
                }
            }
        });

        Self {
            term,
            writer: Arc::new(RwLock::new(SyncWriter(writer))),
            prefs:  Arc::new(RwLock::new(prefs)),
            dirty,
        }
    }

    // Write input

    pub fn write(&self, input: String) {
        let mut w = self.writer.write();
        let _ = w.0.write_all(input.as_bytes());
        let _ = w.0.flush();
    }

    // Hot-reload preferences 

    pub fn update_prefs(&self, new_prefs: TermPreferences) {
        // Store so get_frame() can forward rendering hints (font, colours) to Flutter
        *self.prefs.write() = new_prefs;
        self.dirty.store(true, Ordering::SeqCst);
    }

    pub fn get_prefs(&self) -> TermPreferences {
        self.prefs.read().clone()
    }

    // ── Snapshot the grid ─────────────────────────────────────────────────────

    pub fn get_frame(&self) -> Option<TerminalFrame> {
        if !self.dirty.swap(false, Ordering::SeqCst) {
            return None;
        }

        let prefs = self.prefs.read();
        let term  = self.term.read();
        let grid  = term.grid();
        let display_offset = grid.display_offset();

        let rows = term.screen_lines();
        let cols = term.columns();

        let mut content    = String::with_capacity(rows * cols);
        let mut attributes = Vec::with_capacity(rows * cols);

        let palette = &prefs.palette;

        for y in 0..rows {
            let line_idx = Line(y as i32 - display_offset as i32);
            for col in 0..cols {
                let cell = &grid[line_idx][Column(col)];
                content.push(cell.c);

                // Pack flags into attribute word
                let mut attr = 0u32;
                let flags = cell.flags();
                if flags.contains(Flags::BOLD)      { attr |= 1 << 0; }
                if flags.contains(Flags::ITALIC)    { attr |= 1 << 1; }
                if flags.contains(Flags::UNDERLINE) { attr |= 1 << 2; }
                if flags.contains(Flags::DIM)       { attr |= 1 << 3; }

                // Encode foreground colour (0xRRGGBB in bits 8-31)
                let fg_packed = resolve_color(&cell.fg, palette, prefs.color_foreground);
                attr |= fg_packed << 8;

                attributes.push(attr);
            }
        }

        // Cursor: adjust for scrollback display offset
        let raw_cursor_y      = term.grid().cursor.point.line.0 as i32;
        let adjusted_cursor_y = raw_cursor_y + display_offset as i32;

        Some(TerminalFrame {
            rows: rows as u16,
            cols: cols as u16,
            content,
            attributes,
            cursor_x: term.grid().cursor.point.column.0 as u16,
            cursor_y: if (0..rows as i32).contains(&adjusted_cursor_y) {
                adjusted_cursor_y as u16
            } else {
                65535
            },
        })
    }
    pub fn scroll(&self, lines: i32) {
        let mut term = self.term.write();
        term.scroll_display(Scroll::Delta(lines));
        self.dirty.store(true, Ordering::SeqCst);
    }
}

/// Convert an alacritty `Color` to a packed 0xRRGGBB u32.
fn resolve_color(
    color: &alacritty_terminal::vte::ansi::Color,
    palette: &[u32],
    default_fg: u32,
) -> u32 {
    use alacritty_terminal::vte::ansi::Color;

    match color {
        Color::Named(named) => {
            let idx = *named as usize;
            if idx < palette.len() { palette[idx] } else { default_fg }
        }
        Color::Indexed(i) => {
            let i = *i as usize;
            if i < palette.len() {
                palette[i]
            } else {
                // 216-colour cube (indices 16-231)
                if i < 232 {
                    let i = i - 16;
                    let b = (i % 6) * 51;
                    let g = ((i / 6) % 6) * 51;
                    let r = (i / 36) * 51;
                    ((r as u32) << 16) | ((g as u32) << 8) | (b as u32)
                } else {
                    // Greyscale (indices 232-255)
                    let v = ((i - 232) * 10 + 8) as u32;
                    (v << 16) | (v << 8) | v
                }
            }
        }
        Color::Spec(rgb) => {
            ((rgb.r as u32) << 16) | ((rgb.g as u32) << 8) | (rgb.b as u32)
        }
    }
}
