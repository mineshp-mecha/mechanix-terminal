# flutter_alacritty

A high-performance Flutter-based terminal emulator powered by Alacritty's terminal core.

## 🚀 Features

- **Alacritty Core**: High-performance terminal emulation using `alacritty_terminal`.
- **PTY Support**: Real shell interaction via `portable-pty`.
- **Multi-Tab Support**: Multiple independent terminal sessions (bash) in a tabbed interface.
- **Efficient FFI**: Seamless, high-speed communication between Flutter and Rust using `flutter_rust_bridge` (v2).
- **Custom Rendering**: Optimized `CustomPainter` rendering with 60fps refresh.

## 🏗 Technical Architecture

The project is split into two main layers: the **Rust Backend** (Logic & PTY) and the **Flutter Frontend** (UI & Input).

### 1. Communication Layer (FFI)

We use `flutter_rust_bridge` to bridge the gap between Dart and Rust.

- **Code Generation**: All communication interfaces are defined in Rust and automatically generated for Dart.
- **Synchronous Execution**: Critical operations like `get_terminal_frame` and `send_input` are marked with `#[frb(sync)]` for minimal latency.
- **Memory Safety**: `flutter_rust_bridge` handles complex data passing (like nested lists of terminal cells) without manual memory management.

### 2. Rust Backend (The Engine)

The Rust layer (`rust/src/`) is responsible for the heavy lifting:

- **PTY Management**: Uses `portable-pty` to spawn `bash` processes and manage I/O streams.
- **Terminal Emulation**: Leverages `alacritty_terminal` for its grid model and ANSI parser.
- **ANSI Processor**: A background thread continuously reads raw bytes from the PTY, feeds them into Alacritty's `Processor`, which updates the internal `Term` (grid) state.
- **Multi-Tab Registry**: A global `HashMap` managed with `parking_lot::RwLock` stores multiple `FlutterTerminal` instances.

### 3. Flutter Frontend (The UI)

The Dart layer (`lib/`) handles user interaction:

- **Rendering Pipeline**: The `TerminalView` widget triggers a `Timer.periodic` every 16ms (60fps) to fetch the latest `TerminalFrame` from Rust.
- **CustomPainter**: `TerminalPainter` iterates over the grid cells and renders them using `TextPainter` on a `Canvas`.
- **Input Handling**: Captures `RawKeyEvent` and maps logical keys (Enter, Backspace, Tab, etc.) to ANSI escape sequences, which are sent back to the Rust PTY writer.

## 🛠 Technical Details & Challenges

### PTY Threading

To prevent blocking the UI, each terminal instance has its own background reader thread.

```rust
thread::spawn(move || {
    let mut processor = ansi::Processor::new();
    loop {
        // Read raw bytes from PTY -> Update Alacritty Grid
    }
});
```

### Thread Safety (Sync/Send)

Since Alacritty's `Term` and the PTY writer are accessed from multiple threads (background reader and FFI calls), they are wrapped in `Arc<RwLock<...>>`. Custom `SyncWriter` and `SyncMasterPty` wrappers were implemented to satisfy Rust's thread-safety requirements for FFI exports.

### FontConfig & Rendering

In embedded environments (like flutter-elinux), system fonts might be restricted. The `disable_system_fonts` flag logic (found in related work) ensures that only bundle-provided fonts are used, maintaining visual consistency.

## 🛠 Development

### Prerequisites

- Flutter SDK
- Rust (Cargo)
- `flutter_rust_bridge_codegen` (`cargo install flutter_rust_bridge_codegen`)

### Build and Run

1. **Generate FFI Bindings**:

   ```bash
   flutter_rust_bridge_codegen generate
   ```

2. **Build Rust Library**:

   ```bash
   cd rust && cargo build
   ```

3. **Install Dependencies**:

   ```bash
   flutter pub get
   ```

4. **Run Application**:
   ```bash
   flutter run
   ```

### Project Structure

- `lib/src/rust/`: Generated Dart bindings.
- `rust/src/api/`: Rust FFI entry points.
- `rust/src/terminal.rs`: Core terminal and PTY logic.
- `linux/CMakeLists.txt`: Configured to automatically bundle the Rust `.so` library.

## RUN ON ARM64

```bash
LD_LIBRARY_PATH=./lib ./flutter_alacritty -b . -s 1 -w 540 -h 620
```

## cross compile the

you need to manually cross-compile the Rust library for ARM64 and ensure it is placed in the lib/ directory of your deployment bundle.
cd flutter_alacritty/rust

## Use CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER to point to your cross-compiler

```bash
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
cargo build --release --target aarch64-unknown-linux-gnu
```
