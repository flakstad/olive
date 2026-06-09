package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Reload_Target :: struct {
    root:          string,
    package_path:  string,
    runtime_path:  string,
    state_type:    string,
    run_name:      string,
    init_name:     string,
    on_load_name:  string,
    on_unload_name: string,
    force_reload_name: string,
    force_restart_name: string,
    host_init_name: string,
    host_shutdown_name: string,
    generated_dir: string,
    build_dir:     string,
    module_name:   string,
    watch_paths:   string,
    watch_debounce_ms: string,
    odin_args: string,
}

reload_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  olive init <dir>")
    fmt.println("  olive generate [reload-dir]")
    fmt.println("  olive check [reload-dir]")
    fmt.println("  olive run [reload-dir] [--json]")
    fmt.println("  olive build [reload-dir]")
    fmt.println("  olive watch [reload-dir]")
    fmt.println("  olive paths [reload-dir] [--json]")
    fmt.println("  olive clean [reload-dir]")
}

default_reload_dir :: proc() -> string {
    return strings.clone("reload")
}

reload_dir_arg_or_default :: proc(index: int) -> string {
    if len(os.args) > index {
        return strings.clone(os.args[index])
    }
    return default_reload_dir()
}

trim :: proc(value: string) -> string {
    return strings.trim_space(value)
}

reload_source_path_in_dir :: proc(dir: string) -> string {
    return join_or_exit([]string{dir, "reload.odin"})
}

has_conventional_proc :: proc(source, name: string) -> bool {
    rest := source
    for len(rest) > 0 {
        line := rest
        next_start := len(rest)
        if newline := strings.index(rest, "\n"); newline >= 0 {
            line = rest[:newline]
            next_start = newline + 1
        }
        trimmed := strings.trim_space(line)
        if strings.has_prefix(trimmed, name) {
            after := strings.trim_left(trimmed[len(name):], " \t")
            if strings.has_prefix(after, "::") && strings.contains(after, "proc") {
                return true
            }
        }
        rest = rest[next_start:]
    }
    return false
}

has_reload_state_alias :: proc(source: string) -> bool {
    rest := source
    for len(rest) > 0 {
        line := rest
        next_start := len(rest)
        if newline := strings.index(rest, "\n"); newline >= 0 {
            line = rest[:newline]
            next_start = newline + 1
        }
        trimmed := strings.trim_space(line)
        if strings.has_prefix(trimmed, "Reload_State") {
            after := strings.trim_left(trimmed[len("Reload_State"):], " \t")
            if strings.has_prefix(after, "::") {
                return true
            }
        }
        rest = rest[next_start:]
    }
    return false
}

named_import_path :: proc(source, alias: string) -> (path: string, ok: bool) {
    rest := source
    prefix := fmt.tprintf("import %s ", alias)
    for len(rest) > 0 {
        line := rest
        next_start := len(rest)
        if newline := strings.index(rest, "\n"); newline >= 0 {
            line = rest[:newline]
            next_start = newline + 1
        }
        trimmed := strings.trim_space(line)
        if strings.has_prefix(trimmed, prefix) {
            value := strings.trim_space(trimmed[len(prefix):])
            if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
                return strings.clone(value[1:len(value)-1]), true
            }
        }
        rest = rest[next_start:]
    }
    return "", false
}

conventional_string_value :: proc(source, name: string) -> (value: string, ok: bool) {
    rest := source
    for len(rest) > 0 {
        line := rest
        next_start := len(rest)
        if newline := strings.index(rest, "\n"); newline >= 0 {
            line = rest[:newline]
            next_start = newline + 1
        }
        trimmed := strings.trim_space(line)
        if strings.has_prefix(trimmed, name) {
            after := strings.trim_left(trimmed[len(name):], " \t")
            if strings.has_prefix(after, "::") {
                expr := strings.trim_space(after[len("::"):])
                if len(expr) >= 2 && expr[0] == '"' && expr[len(expr)-1] == '"' {
                    return strings.clone(expr[1:len(expr)-1]), true
                }
            }
        }
        rest = rest[next_start:]
    }
    return "", false
}

read_reload_target :: proc(reload_dir: string) -> (Reload_Target, string, bool) {
    reload_source_path := reload_source_path_in_dir(reload_dir)
    defer delete(reload_source_path)
    data, read_err := os.read_entire_file_from_path(reload_source_path, context.allocator)
    if read_err != nil {
        return {}, strings.clone(fmt.tprintf("could not read reload adapter: %s", reload_source_path)), false
    }
    defer delete(data)
    source := string(data)
    if !has_reload_state_alias(source) {
        return {}, strings.clone("reload adapter requires `Reload_State :: <your state type>` in reload/reload.odin"), false
    }
    if !has_conventional_proc(source, "run") {
        return {}, strings.clone("reload adapter requires `run :: proc(...)` in reload/reload.odin"), false
    }

    runtime_path, runtime_found := named_import_path(source, "olive_reload")
    if !runtime_found {
        runtime_path = olive_reload_runtime_path_or_exit(reload_dir)
    }
    cfg := Reload_Target{
        root = strings.clone(reload_dir),
        package_path = strings.clone("."),
        runtime_path = runtime_path,
        state_type = strings.clone("Reload_State"),
        run_name = strings.clone("run"),
        generated_dir = strings.clone("../.olive/reload/generated"),
        build_dir = strings.clone("../.olive/reload/build"),
        module_name = strings.clone("reload"),
        watch_paths = strings.clone(".."),
        watch_debounce_ms = strings.clone("150"),
    }
    if has_conventional_proc(source, "init") {
        cfg.init_name = strings.clone("init")
    }
    if has_conventional_proc(source, "on_load") {
        cfg.on_load_name = strings.clone("on_load")
    }
    if has_conventional_proc(source, "on_unload") {
        cfg.on_unload_name = strings.clone("on_unload")
    }
    if has_conventional_proc(source, "force_reload") {
        cfg.force_reload_name = strings.clone("force_reload")
    }
    if has_conventional_proc(source, "force_restart") {
        cfg.force_restart_name = strings.clone("force_restart")
    }
    if has_conventional_proc(source, "host_init") {
        cfg.host_init_name = strings.clone("host_init")
    }
    if has_conventional_proc(source, "host_shutdown") {
        cfg.host_shutdown_name = strings.clone("host_shutdown")
    }
    if value, found := conventional_string_value(source, "Olive_Module_Name"); found {
        delete(cfg.module_name)
        cfg.module_name = value
    }
    if value, found := conventional_string_value(source, "Olive_Watch"); found {
        delete(cfg.watch_paths)
        cfg.watch_paths = value
    }
    if value, found := conventional_string_value(source, "Olive_Watch_Debounce_MS"); found {
        delete(cfg.watch_debounce_ms)
        cfg.watch_debounce_ms = value
    }
    if value, found := conventional_string_value(source, "Olive_Odin_Args"); found {
        cfg.odin_args = value
    }
    return cfg, "", true
}

join_or_exit :: proc(parts: []string) -> string {
    path, err := os.join_path(parts, context.allocator)
    if err != nil {
        fmt.eprintln("failed to join path")
        os.exit(1)
    }
    return path
}

path_relative_to_reload_root :: proc(cfg: Reload_Target, path: string) -> string {
    if os.is_absolute_path(path) {
        return strings.clone(path)
    }
    return join_or_exit([]string{cfg.root, path})
}

ensure_directory_or_exit :: proc(path: string) {
    if os.is_directory(path) {
        return
    }
    if os.exists(path) {
        fmt.eprintln("path exists but is not a directory: ", path)
        os.exit(1)
    }
    if os.make_directory_all(path) != nil && !os.is_directory(path) {
        fmt.eprintln("failed to create directory: ", path)
        os.exit(1)
    }
}

write_file_or_exit :: proc(path, content: string) {
    dir, _ := os.split_path(path)
    if dir != "" {
        ensure_directory_or_exit(dir)
    }
    if os.write_entire_file_from_string(path, content) != nil {
        fmt.eprintln("failed to write: ", path)
        os.exit(1)
    }
}

remove_file_if_exact_content :: proc(path, expected_content: string) {
    if !os.exists(path) {
        return
    }
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return
    }
    defer delete(data)
    if string(data) == expected_content {
        _ = os.remove(path)
    }
}

relative_import_or_exit :: proc(from_dir, target_path: string) -> string {
    from_abs, from_err := os.get_absolute_path(from_dir, context.allocator)
    if from_err != nil {
        fmt.eprintln("failed to resolve generated directory")
        os.exit(1)
    }
    defer delete(from_abs)
    target_abs, target_err := os.get_absolute_path(target_path, context.allocator)
    if target_err != nil {
        fmt.eprintln("failed to resolve import path: ", target_path)
        os.exit(1)
    }
    defer delete(target_abs)
    rel, rel_err := os.get_relative_path(from_abs, target_abs, context.allocator)
    if rel_err != nil {
        fmt.eprintln("failed to compute relative import")
        os.exit(1)
    }
    return rel
}

reload_module_source :: proc(cfg: Reload_Target, module_dir, package_path, runtime_path: string) -> string {
    app_import := relative_import_or_exit(module_dir, package_path)
    defer delete(app_import)
    runtime_import := relative_import_or_exit(module_dir, runtime_path)
    defer delete(runtime_import)

    b := strings.builder_make()
    defer strings.builder_destroy(&b)
    strings.write_string(&b, "package olive_reload_module\n\n")
    strings.write_string(&b, "import \"base:runtime\"\n")
    fmt.sbprintf(&b, "import app %q\n", app_import)
    fmt.sbprintf(&b, "import olive_reload %q\n\n", runtime_import)
    strings.write_string(&b, "@(export)\nolive_reload_api_version: u32 = olive_reload.MANIFEST_API_VERSION\n\n")
    fmt.sbprintf(&b, "@(export)\nolive_reload_state_size :: proc \"c\" () -> int {{\n    return size_of(app.%s)\n}}\n\n", cfg.state_type)
    fmt.sbprintf(&b, "@(export)\nolive_reload_state_align :: proc \"c\" () -> int {{\n    return align_of(app.%s)\n}}\n\n", cfg.state_type)
    fmt.sbprintf(&b, "@(export)\nolive_reload_on_load :: proc \"c\" (state: rawptr, is_reload: bool) {{\n    context = runtime.default_context()\n    app_state := (^app.%s)(state)\n", cfg.state_type)
    if cfg.init_name != "" {
        fmt.sbprintf(&b, "    if !is_reload {{\n        app.%s(app_state)\n    }}\n", cfg.init_name)
    }
    if cfg.on_load_name != "" {
        fmt.sbprintf(&b, "    if is_reload {{\n        app.%s(app_state)\n    }}\n", cfg.on_load_name)
    }
    strings.write_string(&b, "}\n\n")
    fmt.sbprintf(&b, "@(export)\nolive_reload_on_unload :: proc \"c\" (state: rawptr) {{\n    context = runtime.default_context()\n    app_state := (^app.%s)(state)\n", cfg.state_type)
    if cfg.on_unload_name != "" {
        fmt.sbprintf(&b, "    app.%s(app_state)\n", cfg.on_unload_name)
    }
    strings.write_string(&b, "}\n\n")
    fmt.sbprintf(&b, "@(export)\nolive_reload_app_run :: proc \"c\" (state: rawptr, host: rawptr) {{\n    context = runtime.default_context()\n    app_state := (^app.%s)(state)\n    app_host := (^olive_reload.Run_Host)(host)\n    app.%s(app_state, app_host)\n}}\n", cfg.state_type, cfg.run_name)
    if cfg.force_reload_name != "" {
        fmt.sbprintf(&b, "\n@(export)\nolive_reload_force_reload :: proc \"c\" (state: rawptr) -> bool {{\n    context = runtime.default_context()\n    app_state := (^app.%s)(state)\n    return app.%s(app_state)\n}}\n", cfg.state_type, cfg.force_reload_name)
    }
    if cfg.force_restart_name != "" {
        fmt.sbprintf(&b, "\n@(export)\nolive_reload_force_restart :: proc \"c\" (state: rawptr) -> bool {{\n    context = runtime.default_context()\n    app_state := (^app.%s)(state)\n    return app.%s(app_state)\n}}\n", cfg.state_type, cfg.force_restart_name)
    }
    return strings.clone(strings.to_string(b))
}

reload_host_source :: proc(cfg: Reload_Target, host_dir, package_path, runtime_path, module_binary_path: string) -> string {
    app_import := relative_import_or_exit(host_dir, package_path)
    defer delete(app_import)
    runtime_import := relative_import_or_exit(host_dir, runtime_path)
    defer delete(runtime_import)

    b := strings.builder_make()
    defer strings.builder_destroy(&b)
    strings.write_string(&b, "package olive_reload_host\n\n")
    strings.write_string(&b, "import \"core:dynlib\"\n")
    strings.write_string(&b, "import \"core:os\"\n")
    fmt.sbprintf(&b, "import app %q\n", app_import)
    fmt.sbprintf(&b, "import olive_reload %q\n\n", runtime_import)
    strings.write_string(&b, "App_Symbols :: struct {\n    run: proc \"c\" (state: rawptr, host: rawptr) `dynlib:\"olive_reload_app_run\"`,\n    force_reload: proc \"c\" (state: rawptr) -> bool `dynlib:\"olive_reload_force_reload\"`,\n    force_restart: proc \"c\" (state: rawptr) -> bool `dynlib:\"olive_reload_force_restart\"`,\n    __handle: dynlib.Library,\n}\n\n")
    fmt.sbprintf(&b, "run :: proc(symbols: ^App_Symbols, state: ^app.%s, host: ^olive_reload.Run_Host) {{\n    symbols.run(rawptr(state), rawptr(host))\n}}\n\n", cfg.state_type)
    fmt.sbprintf(&b, "force_reload :: proc(symbols: ^App_Symbols, state: ^app.%s) -> bool {{\n    return symbols.force_reload != nil && symbols.force_reload(rawptr(state))\n}}\n\n", cfg.state_type)
    fmt.sbprintf(&b, "force_restart :: proc(symbols: ^App_Symbols, state: ^app.%s) -> bool {{\n    return symbols.force_restart != nil && symbols.force_restart(rawptr(state))\n}}\n\n", cfg.state_type)
    fmt.sbprintf(&b, "reset_state :: proc(state: ^app.%s) {{\n    state^ = app.%s{{}}\n}}\n\n", cfg.state_type, cfg.state_type)
    strings.write_string(&b, "event_handler :: proc() -> proc(olive_reload.Reload_Event) {\n")
    strings.write_string(&b, "    for arg in os.args[1:] {\n")
    strings.write_string(&b, "        if arg == \"--json\" {\n")
    strings.write_string(&b, "            return olive_reload.json_event_handler\n")
    strings.write_string(&b, "        }\n")
    strings.write_string(&b, "    }\n")
    strings.write_string(&b, "    return olive_reload.default_event_handler\n")
    strings.write_string(&b, "}\n\n")
    strings.write_string(&b, "main :: proc() {\n")
    fmt.sbprintf(&b, "    module_path := %q\n", module_binary_path)
    if cfg.host_init_name != "" {
        fmt.sbprintf(&b, "    app.%s()\n", cfg.host_init_name)
    }
    fmt.sbprintf(&b, "    state := app.%s{{}}\n", cfg.state_type)
    strings.write_string(&b, "    symbols := App_Symbols{}\n")
    strings.write_string(&b, "    status := olive_reload.run_host(module_path, &symbols, &state, run, event_handler(), force_reload, force_restart, reset_state)\n")
    if cfg.host_shutdown_name != "" {
        fmt.sbprintf(&b, "    app.%s()\n", cfg.host_shutdown_name)
    }
    strings.write_string(&b, "    os.exit(status)\n")
    strings.write_string(&b, "}\n")
    return strings.clone(strings.to_string(b))
}

Reload_Paths :: struct {
    generated_root: string,
    module_dir:     string,
    host_dir:       string,
    module_file:    string,
    host_file:      string,
    build_dir:      string,
    module_binary:  string,
    host_binary:    string,
}

reload_paths_for :: proc(cfg: Reload_Target) -> Reload_Paths {
    generated_root := path_relative_to_reload_root(cfg, cfg.generated_dir)
    module_dir := join_or_exit([]string{generated_root, "module"})
    host_dir := join_or_exit([]string{generated_root, "host"})
    build_dir := path_relative_to_reload_root(cfg, cfg.build_dir)
    module_binary := join_or_exit([]string{build_dir, fmt.tprintf("%s.%s", cfg.module_name, dynlib.LIBRARY_FILE_EXTENSION)})
    host_binary := join_or_exit([]string{build_dir, fmt.tprintf("%s_host", cfg.module_name)})
    return Reload_Paths{
        generated_root = generated_root,
        module_dir = module_dir,
        host_dir = host_dir,
        module_file = join_or_exit([]string{module_dir, "module.odin"}),
        host_file = join_or_exit([]string{host_dir, "host.odin"}),
        build_dir = build_dir,
        module_binary = module_binary,
        host_binary = host_binary,
    }
}

read_reload_dir_or_exit :: proc(reload_dir: string) -> (Reload_Target, Reload_Paths) {
    cfg, err, ok := read_reload_target(reload_dir)
    if !ok {
        fmt.eprintln(err)
        os.exit(1)
    }
    return cfg, reload_paths_for(cfg)
}

json_string :: proc(value: string) -> string {
    b := strings.builder_make()
    defer strings.builder_destroy(&b)
    strings.write_byte(&b, '"')
    for ch in transmute([]byte)value {
        switch ch {
        case '\\', '"':
            strings.write_byte(&b, '\\')
            strings.write_byte(&b, ch)
        case '\n':
            strings.write_string(&b, "\\n")
        case '\r':
            strings.write_string(&b, "\\r")
        case '\t':
            strings.write_string(&b, "\\t")
        case:
            strings.write_byte(&b, ch)
        }
    }
    strings.write_byte(&b, '"')
    return strings.clone(strings.to_string(b))
}

print_json_field :: proc(name, value: string, trailing_comma := true) {
    quoted := json_string(value)
    defer delete(quoted)
    comma := trailing_comma ? "," : ""
    fmt.printf("  %q: %s%s\n", name, quoted, comma)
}

print_reload_paths :: proc(reload_dir: string, json := false) {
    cfg, paths := read_reload_dir_or_exit(reload_dir)
    if json {
        fmt.println("{")
        print_json_field("reload_dir", reload_dir)
        print_json_field("generated_root", paths.generated_root)
        print_json_field("module_dir", paths.module_dir)
        print_json_field("host_dir", paths.host_dir)
        print_json_field("module_file", paths.module_file)
        print_json_field("host_file", paths.host_file)
        print_json_field("build_dir", paths.build_dir)
        print_json_field("module_binary", paths.module_binary)
        print_json_field("host_binary", paths.host_binary)
        print_json_field("package", cfg.package_path)
        print_json_field("watch", cfg.watch_paths)
        print_json_field("watch_debounce_ms", cfg.watch_debounce_ms)
        print_json_field("odin_args", cfg.odin_args)
        print_json_field("run_command", fmt.tprintf("olive run %s", reload_dir))
        print_json_field("watch_command", fmt.tprintf("olive watch %s", reload_dir))
        print_json_field("build_command", fmt.tprintf("olive build %s", reload_dir), false)
        fmt.println("}")
        return
    }
    fmt.printf("reload_dir: %s\n", reload_dir)
    fmt.printf("generated_root: %s\n", paths.generated_root)
    fmt.printf("module_dir: %s\n", paths.module_dir)
    fmt.printf("host_dir: %s\n", paths.host_dir)
    fmt.printf("module_file: %s\n", paths.module_file)
    fmt.printf("host_file: %s\n", paths.host_file)
    fmt.printf("build_dir: %s\n", paths.build_dir)
    fmt.printf("module_binary: %s\n", paths.module_binary)
    fmt.printf("host_binary: %s\n", paths.host_binary)
    fmt.printf("package: %s\n", cfg.package_path)
    fmt.printf("watch: %s\n", cfg.watch_paths)
    fmt.printf("watch_debounce_ms: %s\n", cfg.watch_debounce_ms)
    fmt.printf("odin_args: %s\n", cfg.odin_args)
    fmt.printf("run_command: olive run %s\n", reload_dir)
    fmt.printf("watch_command: olive watch %s\n", reload_dir)
    fmt.printf("build_command: olive build %s\n", reload_dir)
}

remove_path_if_exists :: proc(path: string) -> bool {
    if path == "" || !os.exists(path) {
        return true
    }
    return os.remove_all(path) == nil
}

clean_reload_paths :: proc(reload_dir: string) -> int {
    _, paths := read_reload_dir_or_exit(reload_dir)
    ok := true
    ok = remove_path_if_exists(paths.generated_root) && ok
    ok = remove_path_if_exists(paths.build_dir) && ok

    if !ok {
        fmt.eprintln("failed to clean some reload paths")
        return 1
    }
    fmt.printf("removed: %s\n", paths.generated_root)
    fmt.printf("removed: %s\n", paths.build_dir)
    return 0
}

newest_odin_write_time :: proc(path: string) -> (time.Time, bool) {
    info, stat_err := os.stat(path, context.temp_allocator)
    if stat_err != nil {
        return {}, false
    }
    if info.type == .Regular {
        if strings.has_suffix(info.name, ".odin") {
            return info.modification_time, true
        }
        return {}, false
    }
    if info.type != .Directory {
        return {}, false
    }

    newest := time.Time{}
    found := false
    entries, read_err := os.read_directory_by_path(path, -1, context.temp_allocator)
    if read_err != nil {
        return {}, false
    }
    for entry in entries {
        if entry.name == "." || entry.name == ".." || entry.name == ".olive" {
            continue
        }
        child := entry.fullpath
        if child == "" {
            child = join_or_exit([]string{path, entry.name})
            defer delete(child)
        }
        child_time, child_found := newest_odin_write_time(child)
        if child_found {
            if !found || time.time_to_unix_nano(child_time) > time.time_to_unix_nano(newest) {
                newest = child_time
            }
            found = true
        }
    }
    return newest, found
}

watch_paths_for :: proc(cfg: Reload_Target) -> [dynamic]string {
    paths := make([dynamic]string)
    rest := cfg.watch_paths
    for {
        part := rest
        next := ""
        if comma := strings.index(rest, ","); comma >= 0 {
            part = rest[:comma]
            next = rest[comma+1:]
        }
        trimmed := trim(part)
        if trimmed != "" {
            append(&paths, path_relative_to_reload_root(cfg, trimmed))
        }
        if next == "" {
            break
        }
        rest = next
    }
    if len(paths) == 0 {
        append(&paths, path_relative_to_reload_root(cfg, cfg.package_path))
    }
    return paths
}

delete_watch_paths :: proc(paths: [dynamic]string) {
    for path in paths {
        delete(path)
    }
    delete(paths)
}

newest_watch_write_time :: proc(paths: []string) -> (time.Time, bool) {
    newest := time.Time{}
    found := false
    for path in paths {
        path_time, path_found := newest_odin_write_time(path)
        if path_found {
            if !found || time.time_to_unix_nano(path_time) > time.time_to_unix_nano(newest) {
                newest = path_time
            }
            found = true
        }
    }
    return newest, found
}

watch_debounce_duration :: proc(cfg: Reload_Target) -> time.Duration {
    ms, ok := strconv.parse_int(cfg.watch_debounce_ms, 10)
    if !ok || ms < 0 {
        return 150 * time.Millisecond
    }
    return time.Duration(ms) * time.Millisecond
}

append_odin_args :: proc(args: ^[dynamic]string, cfg: Reload_Target) {
    rest := cfg.odin_args
    for {
        part := rest
        next := ""
        if space := strings.index_any(rest, " \t"); space >= 0 {
            part = rest[:space]
            next = rest[space+1:]
        }
        trimmed := trim(part)
        if trimmed != "" {
            append(args, trimmed)
        }
        if next == "" {
            break
        }
        rest = next
    }
}

reload_check :: proc(reload_dir: string) -> int {
    cfg, paths := read_reload_dir_or_exit(reload_dir)
    ok := true
    reload_package_path := path_relative_to_reload_root(cfg, cfg.package_path)
    defer delete(reload_package_path)
    runtime_path := path_relative_to_reload_root(cfg, cfg.runtime_path)
    defer delete(runtime_path)

    if !os.is_directory(reload_package_path) {
        fmt.eprintln("package path is not a directory: ", reload_package_path)
        ok = false
    } else {
        _, found_sources := newest_odin_write_time(reload_package_path)
        if !found_sources {
            fmt.eprintln("package path contains no .odin files: ", reload_package_path)
            ok = false
        }
    }
    if !os.is_directory(runtime_path) {
        fmt.eprintln("runtime path is not a directory: ", runtime_path)
        ok = false
    }
    if cfg.run_name == "" {
        fmt.eprintln("run must not be empty")
        ok = false
    }
    if cfg.module_name == "" {
        fmt.eprintln("module_name must not be empty")
        ok = false
    }
    if cfg.generated_dir == "" {
        fmt.eprintln("generated_dir must not be empty")
        ok = false
    }
    if cfg.build_dir == "" {
        fmt.eprintln("build_dir must not be empty")
        ok = false
    }
    if _, debounce_ok := strconv.parse_int(cfg.watch_debounce_ms, 10); !debounce_ok {
        fmt.eprintln("watch_debounce_ms must be an integer")
        ok = false
    }
    watch_paths := watch_paths_for(cfg)
    defer delete_watch_paths(watch_paths)
    watch_found := false
    for path in watch_paths {
        if !os.exists(path) {
            fmt.eprintln("watch path does not exist: ", path)
            ok = false
            continue
        }
        if _, found_sources := newest_odin_write_time(path); found_sources {
            watch_found = true
        } else {
            fmt.eprintln("watch path contains no .odin files: ", path)
            ok = false
        }
    }
    if !watch_found {
        fmt.eprintln("watch paths contain no .odin files")
        ok = false
    }
    if !ok {
        return 1
    }

    _, paths = reload_generate_or_exit(reload_dir, true)

    fmt.printf("[olive] checking generated reload module: %s\n", paths.module_dir)
    module_check_args := make([dynamic]string)
    defer delete(module_check_args)
    append(&module_check_args, "odin", "check", paths.module_dir, "-no-entry-point")
    append_odin_args(&module_check_args, cfg)
    module_status := exec_or_exit(module_check_args[:])
    if module_status != 0 {
        fmt.eprintln("[olive] reload module check failed")
        return module_status
    }

    fmt.printf("[olive] checking generated host: %s\n", paths.host_dir)
    host_check_args := make([dynamic]string)
    defer delete(host_check_args)
    append(&host_check_args, "odin", "check", paths.host_dir)
    append_odin_args(&host_check_args, cfg)
    host_status := exec_or_exit(host_check_args[:])
    if host_status != 0 {
        fmt.eprintln("[olive] host check failed")
        return host_status
    }

    fmt.printf("[olive] reload ok: %s\n", reload_dir)
    fmt.printf("[olive] package: %s\n", reload_package_path)
    fmt.printf("[olive] runtime: %s\n", runtime_path)
    fmt.printf("[olive] run: %s\n", cfg.run_name)
    fmt.printf("[olive] watch: %s\n", cfg.watch_paths)
    fmt.printf("[olive] module: %s\n", paths.module_binary)
    return 0
}

reload_generate_or_exit :: proc(reload_dir: string, quiet := false) -> (Reload_Target, Reload_Paths) {
    cfg, paths := read_reload_dir_or_exit(reload_dir)
    ensure_directory_or_exit(paths.module_dir)
    ensure_directory_or_exit(paths.host_dir)
    reload_package_path := path_relative_to_reload_root(cfg, cfg.package_path)
    defer delete(reload_package_path)
    runtime_path := path_relative_to_reload_root(cfg, cfg.runtime_path)
    defer delete(runtime_path)
    module_source := reload_module_source(cfg, paths.module_dir, reload_package_path, runtime_path)
    defer delete(module_source)
    host_source := reload_host_source(cfg, paths.host_dir, reload_package_path, runtime_path, paths.module_binary)
    defer delete(host_source)
    write_file_or_exit(paths.module_file, module_source)
    write_file_or_exit(paths.host_file, host_source)
    if !quiet {
        fmt.println(paths.module_file)
        fmt.println(paths.host_file)
    }
    return cfg, paths
}

exec_or_exit :: proc(args: []string, working_dir := "") -> int {
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = args, working_dir = working_dir},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if len(stdout) > 0 {
        fmt.print(string(stdout))
    }
    if len(stderr) > 0 {
        fmt.eprint(string(stderr))
    }
    if err != nil {
        return 1
    }
    if state.exited {
        return state.exit_code
    }
    return 1
}

exec_foreground_or_exit :: proc(args: []string, working_dir := "") -> int {
    process, start_err := os.process_start(os.Process_Desc{
        command = args,
        working_dir = working_dir,
        stdin = os.stdin,
        stdout = os.stdout,
        stderr = os.stderr,
    })
    if start_err != nil {
        fmt.eprintln("failed to start: ", args[0])
        return 1
    }

    state, wait_err := os.process_wait(process)
    if wait_err != nil {
        fmt.eprintln("failed to wait for: ", args[0])
        return 1
    }
    if state.exited {
        return state.exit_code
    }
    return 1
}

reload_build_status_or_exit :: proc(reload_dir: string, host: bool, quiet := false) -> (Reload_Target, Reload_Paths, int) {
    cfg, paths := reload_generate_or_exit(reload_dir, quiet)
    ensure_directory_or_exit(paths.build_dir)
    module_tmp := strings.clone(fmt.tprintf("%s.tmp", paths.module_binary))
    defer delete(module_tmp)
    module_out := strings.clone(fmt.tprintf("-out:%s", module_tmp))
    defer delete(module_out)
    module_args := make([dynamic]string)
    defer delete(module_args)
    append(&module_args, "odin", "build", paths.module_dir, "-build-mode:dll", module_out)
    append_odin_args(&module_args, cfg)
    module_status := exec_or_exit(module_args[:])
    if module_status != 0 {
        if os.exists(module_tmp) {
            _ = os.remove(module_tmp)
        }
        return cfg, paths, module_status
    }
    if os.exists(paths.module_binary) {
        _ = os.remove(paths.module_binary)
    }
    if os.rename(module_tmp, paths.module_binary) != nil {
        fmt.eprintln("failed to publish reload module: ", paths.module_binary)
        return cfg, paths, 1
    }
    if host {
        host_out := strings.clone(fmt.tprintf("-out:%s", paths.host_binary))
        defer delete(host_out)
        host_args := make([dynamic]string)
        defer delete(host_args)
        append(&host_args, "odin", "build", paths.host_dir, host_out)
        append_odin_args(&host_args, cfg)
        host_status := exec_or_exit(host_args[:])
        if host_status != 0 {
            return cfg, paths, host_status
        }
    }
    return cfg, paths, 0
}

reload_build_or_exit :: proc(reload_dir: string, host: bool) -> (Reload_Target, Reload_Paths) {
    cfg, paths, status := reload_build_status_or_exit(reload_dir, host)
    if status != 0 {
        os.exit(status)
    }
    return cfg, paths
}

reload_watch :: proc(reload_dir: string) -> int {
    cfg, _, status := reload_build_status_or_exit(reload_dir, false, true)
    watch_paths := watch_paths_for(cfg)
    defer delete_watch_paths(watch_paths)
    last_write, found := newest_watch_write_time(watch_paths[:])
    if !found {
        fmt.eprintln("watch found no Odin files under configured watch paths")
        return 1
    }
    if status == 0 {
        fmt.printf("[olive] watching: %s\n", cfg.watch_paths)
    } else {
        fmt.printf("[olive] initial build failed; watching for changes: %s\n", cfg.watch_paths)
    }

    debounce := watch_debounce_duration(cfg)
    for {
        time.sleep(250 * time.Millisecond)
        current_write, current_found := newest_watch_write_time(watch_paths[:])
        if !current_found {
            continue
        }
        if time.time_to_unix_nano(current_write) == time.time_to_unix_nano(last_write) {
            continue
        }
        last_write = current_write
        time.sleep(debounce)
        settled_write, settled_found := newest_watch_write_time(watch_paths[:])
        if settled_found {
            last_write = settled_write
        }
        fmt.println("[olive] change detected; rebuilding module")
        _, _, rebuild_status := reload_build_status_or_exit(reload_dir, false, true)
        if rebuild_status == 0 {
            fmt.println("[olive] build ok")
        } else {
            fmt.printf("[olive] build failed exit=%d; still watching\n", rebuild_status)
        }
    }
    return 0
}

olive_reload_runtime_path_or_exit :: proc(from_dir: string) -> string {
    if override, found := os.lookup_env("OLIVE_RELOAD_RUNTIME", context.allocator); found {
        return override
    }

    executable_dir, exe_err := os.get_executable_directory(context.allocator)
    if exe_err == nil {
        candidate := join_or_exit([]string{executable_dir, "src", "olive_reload"})
        delete(executable_dir)
        if os.is_directory(candidate) {
            return candidate
        }
        delete(candidate)
    }

    cwd, cwd_err := os.get_working_directory(context.allocator)
    if cwd_err == nil {
        candidate := join_or_exit([]string{cwd, "src", "olive_reload"})
        delete(cwd)
        if os.is_directory(candidate) {
            return candidate
        }
        delete(candidate)
    }

    fmt.eprintln("could not find Olive reload runtime; set OLIVE_RELOAD_RUNTIME=/path/to/olive/src/olive_reload")
    os.exit(1)
}

reload_init_program :: proc(dir: string) {
    ensure_directory_or_exit(dir)
    reload_dir := join_or_exit([]string{dir, "reload"})
    defer delete(reload_dir)
    ensure_directory_or_exit(reload_dir)
    main_file := join_or_exit([]string{dir, "main.odin"})
    defer delete(main_file)
    reload_file := join_or_exit([]string{reload_dir, "reload.odin"})
    defer delete(reload_file)
    runtime_path := olive_reload_runtime_path_or_exit(dir)
    defer delete(runtime_path)
    runtime_import_path := relative_import_or_exit(reload_dir, runtime_path)
    defer delete(runtime_import_path)
    root_import := relative_import_or_exit(reload_dir, dir)
    defer delete(root_import)

    legacy_state_file := join_or_exit([]string{dir, "state.odin"})
    defer delete(legacy_state_file)
    legacy_game_file := join_or_exit([]string{dir, "game.odin"})
    defer delete(legacy_game_file)
    legacy_state_source := `package main

Program_State :: struct {
    ticks: int,
}
`
    legacy_game_source := `package main

init :: proc(state: ^Program_State) {
    state.ticks = 0
}

tick :: proc(state: ^Program_State) {
    state.ticks += 1
}
`
    remove_file_if_exact_content(legacy_state_file, legacy_state_source)
    remove_file_if_exact_content(legacy_game_file, legacy_game_source)

    main_source := `package main

import "core:fmt"
import "core:time"

Program_State :: struct {
    ticks: int,
}

init :: proc(state: ^Program_State) {
    state.ticks = 0
}

tick :: proc(state: ^Program_State) {
    state.ticks += 1
    fmt.printf("tick %d: edit main.odin and change this text\n", state.ticks)
    time.sleep(time.Second)
}

main :: proc() {
    state := Program_State{}
    init(&state)

    for {
        tick(&state)
    }
}
`
    reload_builder := strings.builder_make()
    defer strings.builder_destroy(&reload_builder)
    strings.write_string(&reload_builder, "package reload\n\n")
    strings.write_string(&reload_builder, "import \"core:fmt\"\n")
    fmt.sbprintf(&reload_builder, "import program %q\n", root_import)
    fmt.sbprintf(&reload_builder, "import olive_reload %q\n\n", runtime_import_path)
    strings.write_string(&reload_builder, `Reload_State :: program.Program_State

init :: proc(state: ^Reload_State) {
    program.init(state)
}

on_load :: proc(state: ^Reload_State) {
    _ = state
    fmt.println("reloaded")
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
    _ = host
    program.tick(state)
}
`)
    reload_source := strings.to_string(reload_builder)
    write_file_or_exit(main_file, main_source)
    write_file_or_exit(reload_file, reload_source)
    fmt.println(reload_file)
}

parse_reload_command :: proc() -> int {
    if len(os.args) < 2 {
        reload_usage()
        return 2
    }
    switch os.args[1] {
    case "init":
        if len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_init_program(os.args[2])
        return 0
    case "generate":
        if len(os.args) != 2 && len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_dir := reload_dir_arg_or_default(2)
        defer delete(reload_dir)
        _, _ = reload_generate_or_exit(reload_dir)
        return 0
    case "check":
        if len(os.args) != 2 && len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_dir := reload_dir_arg_or_default(2)
        defer delete(reload_dir)
        return reload_check(reload_dir)
    case "build":
        if len(os.args) != 2 && len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_dir := reload_dir_arg_or_default(2)
        defer delete(reload_dir)
        _, _ = reload_build_or_exit(reload_dir, false)
        return 0
    case "watch":
        if len(os.args) != 2 && len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_dir := reload_dir_arg_or_default(2)
        defer delete(reload_dir)
        return reload_watch(reload_dir)
    case "paths":
        if len(os.args) < 2 || len(os.args) > 4 {
            reload_usage()
            return 2
        }
        json := false
        reload_dir := ""
        if len(os.args) == 2 {
            reload_dir = default_reload_dir()
        } else if len(os.args) == 3 {
            if os.args[2] == "--json" {
                reload_dir = default_reload_dir()
                json = true
            } else {
                reload_dir = strings.clone(os.args[2])
            }
        } else {
            reload_dir = strings.clone(os.args[2])
            if os.args[3] != "--json" {
                delete(reload_dir)
                reload_usage()
                return 2
            }
            json = true
        }
        defer delete(reload_dir)
        print_reload_paths(reload_dir, json)
        return 0
    case "clean":
        if len(os.args) != 2 && len(os.args) != 3 {
            reload_usage()
            return 2
        }
        reload_dir := reload_dir_arg_or_default(2)
        defer delete(reload_dir)
        return clean_reload_paths(reload_dir)
    case "run":
        if len(os.args) < 2 || len(os.args) > 4 {
            reload_usage()
            return 2
        }
        json := false
        reload_dir := ""
        if len(os.args) == 2 {
            reload_dir = default_reload_dir()
        } else if len(os.args) == 3 {
            if os.args[2] == "--json" {
                reload_dir = default_reload_dir()
                json = true
            } else {
                reload_dir = strings.clone(os.args[2])
            }
        } else {
            reload_dir = strings.clone(os.args[2])
            if os.args[3] != "--json" {
                delete(reload_dir)
                reload_usage()
                return 2
            }
            json = true
        }
        defer delete(reload_dir)
        host_args := make([dynamic]string)
        defer delete(host_args)
        _, paths := reload_build_or_exit(reload_dir, true)
        append(&host_args, paths.host_binary)
        if json {
            append(&host_args, "--json")
        }
        return exec_foreground_or_exit(host_args[:])
    case "-h", "--help", "help":
        reload_usage()
        return 0
    case:
        reload_usage()
        return 2
    }
}
