use std::fs;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use toml::Value;

use crate::api::simple::TermPreferences;

fn config_path() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("alacritty").join("alacritty.toml")
}

fn rgb_to_hex(v: u32) -> String {
    format!("#{:06x}", v & 0xFFFFFF)
}

fn hex_to_rgb(s: &str) -> Option<u32> {
    let s = s.trim().trim_start_matches('#').trim_start_matches("0x");
    u32::from_str_radix(s, 16).ok()
}

const NORMAL_NAMES: [&str; 8]  = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
const BRIGHT_NAMES: [&str; 8]  = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];

pub fn load_prefs_from_alacritty_config() -> Option<TermPreferences> {
    let path = config_path();
    let text = fs::read_to_string(&path).ok()?;
    let doc: Value = toml::from_str(&text).ok()?;

    let font_family = doc
        .get("font").and_then(|f| f.get("normal")).and_then(|n| n.get("family"))
        .and_then(Value::as_str)
        .unwrap_or("monospace")
        .to_string();

    let font_size = doc
        .get("font").and_then(|f| f.get("size"))
        .and_then(Value::as_float)
        .unwrap_or(14.0);

    let line_height = doc
        .get("font").and_then(|f| f.get("line_height"))
        .and_then(Value::as_float)
        .unwrap_or(1.2);

    let colors = doc.get("colors");

    let color_foreground = colors
        .and_then(|c| c.get("primary")).and_then(|p| p.get("foreground"))
        .and_then(Value::as_str).and_then(hex_to_rgb)
        .unwrap_or(0xCDD6F4);

    let color_background = colors
        .and_then(|c| c.get("primary")).and_then(|p| p.get("background"))
        .and_then(Value::as_str).and_then(hex_to_rgb)
        .unwrap_or(0x1E1E2E);

    let color_cursor = colors
        .and_then(|c| c.get("cursor")).and_then(|p| p.get("cursor"))
        .and_then(Value::as_str).and_then(hex_to_rgb)
        .unwrap_or(0xF5C2E7);

    let color_selection = colors
        .and_then(|c| c.get("selection")).and_then(|p| p.get("background"))
        .and_then(Value::as_str).and_then(hex_to_rgb)
        .unwrap_or(0x45475A);

    let mut palette = vec![0u32; 16];

    if let Some(normal) = colors.and_then(|c| c.get("normal")) {
        for (i, name) in NORMAL_NAMES.iter().enumerate() {
            if let Some(v) = normal.get(*name).and_then(Value::as_str).and_then(hex_to_rgb) {
                palette[i] = v;
            }
        }
    }
    
    if let Some(bright) = colors.and_then(|c| c.get("bright")) {
        for (i, name) in BRIGHT_NAMES.iter().enumerate() {
            if let Some(v) = bright.get(*name).and_then(Value::as_str).and_then(hex_to_rgb) {
                palette[8 + i] = v;
            }
        }
    }

    if palette.iter().all(|&v| v == 0) {
        palette = catppuccin_mocha_palette();
    }

    Some(TermPreferences {
        font_family,
        font_size,
        line_height,
        color_foreground,
        color_background,
        color_cursor,
        color_selection,
        palette,
    })
}

pub fn save_prefs_to_alacritty_config(prefs: &TermPreferences) -> Result<(), String> {
    let path = config_path();

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let mut doc: Value = path
        .exists()
        .then(|| fs::read_to_string(&path).ok())
        .flatten()
        .and_then(|s| toml::from_str(&s).ok())
        .unwrap_or(Value::Table(toml::map::Map::new()));

    let root = match &mut doc {
        Value::Table(t) => t,
        _ => return Err("Unexpected TOML root type".into()),
    };

    {
        let font = root
            .entry("font")
            .or_insert(Value::Table(toml::map::Map::new()));
        let font_table = font.as_table_mut().ok_or("font is not a table")?;

        font_table.insert("size".into(), Value::Float(prefs.font_size));
        font_table.insert("line_height".into(), Value::Float(prefs.line_height));

        let normal = font_table
            .entry("normal")
            .or_insert(Value::Table(toml::map::Map::new()));
        if let Some(t) = normal.as_table_mut() {
            t.insert("family".into(), Value::String(prefs.font_family.clone()));
        }
    }

    {
        let colors = root
            .entry("colors")
            .or_insert(Value::Table(toml::map::Map::new()));
        let colors_table = colors.as_table_mut().ok_or("colors is not a table")?;

        {
            let primary = colors_table
                .entry("primary")
                .or_insert(Value::Table(toml::map::Map::new()));
            if let Some(t) = primary.as_table_mut() {
                t.insert("foreground".into(), Value::String(rgb_to_hex(prefs.color_foreground)));
                t.insert("background".into(), Value::String(rgb_to_hex(prefs.color_background)));
            }
        }

        {
            let cursor = colors_table
                .entry("cursor")
                .or_insert(Value::Table(toml::map::Map::new()));
            if let Some(t) = cursor.as_table_mut() {
                t.insert("cursor".into(), Value::String(rgb_to_hex(prefs.color_cursor)));
            }
        }

        {
            let selection = colors_table
                .entry("selection")
                .or_insert(Value::Table(toml::map::Map::new()));
            if let Some(t) = selection.as_table_mut() {
                t.insert("background".into(), Value::String(rgb_to_hex(prefs.color_selection)));
            }
        }

        {
            let normal = colors_table
                .entry("normal")
                .or_insert(Value::Table(toml::map::Map::new()));
            if let Some(t) = normal.as_table_mut() {
                for (i, name) in NORMAL_NAMES.iter().enumerate() {
                    if i < prefs.palette.len() {
                        t.insert((*name).into(), Value::String(rgb_to_hex(prefs.palette[i])));
                    }
                }
            }
        }

        {
            let bright = colors_table
                .entry("bright")
                .or_insert(Value::Table(toml::map::Map::new()));
            if let Some(t) = bright.as_table_mut() {
                for (i, name) in BRIGHT_NAMES.iter().enumerate() {
                    let idx = 8 + i;
                    if idx < prefs.palette.len() {
                        t.insert((*name).into(), Value::String(rgb_to_hex(prefs.palette[idx])));
                    }
                }
            }
        }
    }

    let serialized = toml::to_string_pretty(&doc).map_err(|e| e.to_string())?;
    fs::write(&path, serialized).map_err(|e| e.to_string())?;
    Ok(())
}

fn catppuccin_mocha_palette() -> Vec<u32> {
    vec![
        0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF,
        0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
        0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF,
        0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xA6ADC8,
    ]
}
