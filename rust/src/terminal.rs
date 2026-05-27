use alacritty_terminal::event::VoidListener;
use alacritty_terminal::grid::{Dimensions, GridCell};
use alacritty_terminal::index::{Column, Line};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::{Config, Term};
use vte::ansi;
use parking_lot::RwLock;
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use std::io::{Read, Write};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub struct TerminalFrame {
    pub rows: u16,
    pub cols: u16,
    pub cells: Vec<TerminalCell>,
    pub cursor_x: u16,
    pub cursor_y: u16,
}

pub struct TerminalCell {
    pub content: String,
    pub fg: u32,
    pub bg: u32,
    pub bold: bool,
}

struct SyncMasterPty(Box<dyn MasterPty + Send>);
unsafe impl Sync for SyncMasterPty {}

pub struct FlutterTerminal {
    term: Arc<RwLock<Term<VoidListener>>>,
    master_pty: Arc<RwLock<SyncMasterPty>>,
    writer: Arc<RwLock<SyncWriter>>,
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
    fn total_lines(&self) -> usize { self.rows }
}

#[derive(Default)]
struct NoopTimeout {
    _dummy: bool,
}

impl ansi::Timeout for NoopTimeout {
    fn set_timeout(&mut self, _: Duration) {}
    fn clear_timeout(&mut self) {}
    fn pending_timeout(&self) -> bool { false }
}

impl FlutterTerminal {
    pub fn new(rows: u16, cols: u16) -> Self {
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .unwrap();

        let dims = SimpleDimensions { cols: cols as usize, rows: rows as usize };
        let term = Term::new(Config::default(), &dims, VoidListener);
        let term = Arc::new(RwLock::new(term));

        let mut _child = pair
            .slave
            .spawn_command(CommandBuilder::new("bash"))
            .unwrap();

        let reader = pair.master.try_clone_reader().unwrap();
        let writer = pair.master.take_writer().unwrap();
        let term_clone = Arc::clone(&term);

        thread::spawn(move || {
            let mut processor: ansi::Processor<NoopTimeout> = ansi::Processor::new();
            let mut reader = reader;
            let mut buf = [0u8; 1024];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        let mut term_lock = term_clone.write();
                        processor.advance(&mut *term_lock, &buf[..n]);
                    }
                    Err(_) => break,
                }
            }
        });

        Self {
            term,
            master_pty: Arc::new(RwLock::new(SyncMasterPty(pair.master))),
            writer: Arc::new(RwLock::new(SyncWriter(writer))),
        }
    }

    pub fn write(&self, input: String) {
        let mut writer = self.writer.write();
        writer.0.write_all(input.as_bytes()).unwrap();
        writer.0.flush().unwrap();
    }

    pub fn get_frame(&self) -> TerminalFrame {
        let term = self.term.read();
        let grid = term.grid();
        
        let mut cells = Vec::new();
        let rows = term.screen_lines();
        let cols = term.columns();

        for line in 0..rows {
            for col in 0..cols {
                let cell = &grid[Line(line as i32)][Column(col)];
                cells.push(TerminalCell {
                    content: cell.c.to_string(),
                    fg: 0xFFFFFFFF,
                    bg: 0xFF000000,
                    bold: cell.flags().contains(Flags::BOLD),
                });
            }
        }

        TerminalFrame {
            rows: rows as u16,
            cols: cols as u16,
            cells,
            cursor_x: term.grid().cursor.point.column.0 as u16,
            cursor_y: term.grid().cursor.point.line.0 as u16,
        }
    }
}
