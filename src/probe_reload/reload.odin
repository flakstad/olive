package probe_reload

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:time"

MANIFEST_API_VERSION :: u32(1)

Core_Symbols :: struct {
    api_version: ^u32 `dynlib:"probe_reload_api_version"`,
    state_size:  proc "c" () -> int `dynlib:"probe_reload_state_size"`,
    state_align: proc "c" () -> int `dynlib:"probe_reload_state_align"`,
    on_load:     proc "c" (state: rawptr, is_reload: bool) `dynlib:"probe_reload_on_load"`,
    on_unload:   proc "c" (state: rawptr) `dynlib:"probe_reload_on_unload"`,
    __handle:    dynlib.Library,
}

Reload_Event_Kind :: enum {
    Started,
    Reloaded,
    Restarted,
    Reload_Failed,
    Checkpoint_Error,
}

Reload_Event :: struct {
    kind:       Reload_Event_Kind,
    generation: int,
    message:    string,
}

Run_Host :: struct {
    module_path: string,
    last_write:  time.Time,
    reload_requested: bool,
    exit_requested: bool,
    error_message: string,
}

Session :: struct {
    module_path: string,
    state:       rawptr,
    state_size:  int,
    state_align: int,
    core:        Core_Symbols,
    generation:  int,
    last_write:  time.Time,
    retained:    [dynamic]dynlib.Library,
}

State_Size :: proc($T: typeid) -> int {
    return size_of(T)
}

State_Align :: proc($T: typeid) -> int {
    return align_of(T)
}

library_write_time :: proc(path: string) -> (time.Time, bool) {
    info, err := os.stat(path, context.temp_allocator)
    if err != nil {
        return {}, false
    }
    return info.modification_time, true
}

shadow_library_path :: proc(path: string, generation: int) -> string {
    dir, file := os.split_path(path)
    shadow_name := strings.clone(fmt.tprintf(".probe-reload-%d-%s", generation, file))
    defer delete(shadow_name)
    joined, err := os.join_path({dir, shadow_name}, context.allocator)
    if err != nil {
        return strings.clone(fmt.tprintf("%s.probe-reload-%d-%s", dir, generation, file))
    }
    return joined
}

copy_file :: proc(from, to: string) -> bool {
    data, read_err := os.read_entire_file_from_path(from, context.allocator)
    if read_err != nil {
        return false
    }
    defer delete(data)
    if os.exists(to) {
        _ = os.remove(to)
    }
    return os.write_entire_file(to, data) == nil
}

unload_core :: proc(core: ^Core_Symbols, state: rawptr) {
    if core.__handle != nil {
        if core.on_unload != nil && state != nil {
            core.on_unload(state)
        }
        _ = dynlib.unload_library(core.__handle)
        core^ = {}
    }
}

close_library :: proc(library: dynlib.Library) {
    if library != nil {
        _ = dynlib.unload_library(library)
    }
}

retain_app_symbol_library :: proc(session: ^Session, app_symbols: ^$T) {
    for field in reflect.struct_fields_zipped(T) {
        if field.name == "__handle" {
            field_ptr := rawptr(uintptr(app_symbols) + field.offset)
            handle := (^dynlib.Library)(field_ptr)^
            if handle != nil {
                append(&session.retained, handle)
                (^dynlib.Library)(field_ptr)^ = nil
            }
            return
        }
    }
}

release_retained_libraries :: proc(session: ^Session) {
    for library in session.retained {
        close_library(library)
    }
    delete(session.retained)
    session.retained = nil
}

cleanup_shadow_libraries :: proc(module_path: string) {
    dir, _ := os.split_path(module_path)
    entries, read_err := os.read_directory_by_path(dir, -1, context.temp_allocator)
    if read_err != nil {
        return
    }
    for entry in entries {
        if strings.contains(entry.name, ".probe-reload-") {
            path, join_err := os.join_path({dir, entry.name}, context.temp_allocator)
            if join_err == nil {
                _ = os.remove(path)
            }
        }
    }
}

unload_app_symbol_library :: proc(app_symbols: ^$T) {
    for field in reflect.struct_fields_zipped(T) {
        if field.name == "__handle" {
            field_ptr := rawptr(uintptr(app_symbols) + field.offset)
            handle := (^dynlib.Library)(field_ptr)^
            if handle != nil {
                close_library(handle)
                (^dynlib.Library)(field_ptr)^ = nil
            }
            return
        }
    }
}

load_core :: proc(path: string, state: rawptr, state_size, state_align: int, generation: int, is_reload: bool) -> (Core_Symbols, time.Time, string, bool) {
    shadow := shadow_library_path(path, generation)
    defer delete(shadow)
    if !copy_file(path, shadow) {
        return {}, {}, strings.clone("failed to copy reload library"), false
    }

    core := Core_Symbols{}
    _, ok := dynlib.initialize_symbols(&core, shadow)
    if !ok {
        return {}, {}, strings.clone("failed to load reload manifest"), false
    }

    if core.api_version == nil || core.state_size == nil || core.state_align == nil || core.on_load == nil || core.on_unload == nil {
        unload_core(&core, nil)
        return {}, {}, strings.clone("reload manifest is incomplete"), false
    }
    if core.api_version^ != MANIFEST_API_VERSION {
        unload_core(&core, nil)
        return {}, {}, strings.clone("reload API version mismatch"), false
    }
    layout_changed := core.state_size() != state_size || core.state_align() != state_align
    if layout_changed {
        unload_core(&core, nil)
        return {}, {}, strings.clone("reload state layout changed; rebuild and restart the host"), false
    }

    write_time, time_ok := library_write_time(path)
    if !time_ok {
        unload_core(&core, nil)
        return {}, {}, strings.clone("failed to stat reload library"), false
    }
    core.on_load(state, is_reload)
    return core, write_time, "", true
}

start_session :: proc(module_path: string, app_symbols: ^$T, state: ^$S) -> (Session, string, bool) {
    state_size := size_of(S)
    state_align := align_of(S)
    core, write_time, message, ok := load_core(module_path, rawptr(state), state_size, state_align, 1, false)
    if !ok {
        return {}, message, false
    }
    _, symbols_ok := dynlib.initialize_symbols(app_symbols, shadow_library_path(module_path, 1))
    if !symbols_ok {
        unload_core(&core, rawptr(state))
        return {}, strings.clone("failed to load app symbols"), false
    }
    return Session{
        module_path = module_path,
        state = rawptr(state),
        state_size = state_size,
        state_align = state_align,
        core = core,
        generation = 1,
        last_write = write_time,
        retained = make([dynamic]dynlib.Library),
    }, "", true
}

finish_session :: proc(session: ^Session) {
    unload_core(&session.core, session.state)
    release_retained_libraries(session)
    cleanup_shadow_libraries(session.module_path)
}

poll_session :: proc(session: ^Session, app_symbols: ^$T, state: ^$S, init_state: proc(^S) = nil) -> (Reload_Event, bool) {
    write_time, time_ok := library_write_time(session.module_path)
    if !time_ok {
        return Reload_Event{kind = .Reload_Failed, generation = session.generation, message = "failed to stat reload library"}, true
    }
    if time.time_to_unix_nano(write_time) == time.time_to_unix_nano(session.last_write) {
        return {}, false
    }

    next_generation := session.generation + 1
    core, new_write_time, message, ok := load_core(session.module_path, session.state, session.state_size, session.state_align, next_generation, true)
    if !ok {
        return Reload_Event{kind = .Reload_Failed, generation = session.generation, message = message}, true
    }

    shadow := shadow_library_path(session.module_path, next_generation)
    defer delete(shadow)
    retain_app_symbol_library(session, app_symbols)
    _, symbols_ok := dynlib.initialize_symbols(app_symbols, shadow)
    if !symbols_ok {
        unload_core(&core, session.state)
        return Reload_Event{kind = .Reload_Failed, generation = session.generation, message = "failed to reload app symbols"}, true
    }

    if session.core.on_unload != nil {
        session.core.on_unload(session.state)
    }
    append(&session.retained, session.core.__handle)
    session.core = core
    session.generation = next_generation
    session.last_write = new_write_time
    return Reload_Event{kind = .Reloaded, generation = session.generation}, true
}

default_event_handler :: proc(event: Reload_Event) {
    switch event.kind {
    case .Started:
        fmt.printf("[probe reload] started generation=%d\n", event.generation)
    case .Reloaded:
        fmt.printf("[probe reload] reloaded generation=%d\n", event.generation)
    case .Restarted:
        fmt.printf("[probe reload] restarted generation=%d: %s\n", event.generation, event.message)
    case .Reload_Failed:
        fmt.eprintf("[probe reload] reload failed: %s\n", event.message)
    case .Checkpoint_Error:
        fmt.eprintf("[probe reload] checkpoint error: %s\n", event.message)
    }
}

event_kind_name :: proc(kind: Reload_Event_Kind) -> string {
    switch kind {
    case .Started:
        return "started"
    case .Reloaded:
        return "reloaded"
    case .Restarted:
        return "restarted"
    case .Reload_Failed:
        return "reload_failed"
    case .Checkpoint_Error:
        return "checkpoint_error"
    }
    return "unknown"
}

write_json_string :: proc(builder: ^strings.Builder, value: string) {
    strings.write_byte(builder, '"')
    for ch in transmute([]byte)value {
        switch ch {
        case '\\', '"':
            strings.write_byte(builder, '\\')
            strings.write_byte(builder, ch)
        case '\n':
            strings.write_string(builder, "\\n")
        case '\r':
            strings.write_string(builder, "\\r")
        case '\t':
            strings.write_string(builder, "\\t")
        case:
            strings.write_byte(builder, ch)
        }
    }
    strings.write_byte(builder, '"')
}

json_event_handler :: proc(event: Reload_Event) {
    b := strings.builder_make()
    defer strings.builder_destroy(&b)
    strings.write_string(&b, `PROBE_RELOAD_EVENT	{`)
    strings.write_string(&b, `"kind":`)
    write_json_string(&b, event_kind_name(event.kind))
    fmt.sbprintf(&b, `,"generation":%d`, event.generation)
    strings.write_string(&b, `,"message":`)
    write_json_string(&b, event.message)
    strings.write_string(&b, "}\n")
    fmt.print(strings.to_string(b))
}

run_host_init :: proc(host: ^Run_Host, module_path: string) {
    host.module_path = module_path
    host.reload_requested = false
    host.exit_requested = false
    host.error_message = ""
    host.last_write, _ = library_write_time(module_path)
}

request_exit :: proc(host: ^Run_Host) {
    host.exit_requested = true
}

checkpoint :: proc(host: ^Run_Host) -> bool {
    write_time, ok := library_write_time(host.module_path)
    if !ok {
        host.error_message = "failed to stat reload library"
        return false
    }
    if time.time_to_unix_nano(write_time) != time.time_to_unix_nano(host.last_write) {
        host.reload_requested = true
        return true
    }
    return false
}

run_cooperative_host :: proc(
    module_path: string,
    app_symbols: ^$T,
    state: ^$S,
    run: proc(^T, ^S, ^Run_Host),
    on_event := default_event_handler,
    force_reload: proc(^T, ^S) -> bool = nil,
    force_restart: proc(^T, ^S) -> bool = nil,
    init_state: proc(^S) = nil,
) -> int {
    session, message, ok := start_session(module_path, app_symbols, state)
    if !ok {
        on_event(Reload_Event{kind = .Reload_Failed, message = message})
        return 1
    }
    defer finish_session(&session)
    defer unload_app_symbol_library(app_symbols)
    on_event(Reload_Event{kind = .Started, generation = session.generation})

    host := Run_Host{}
    run_host_init(&host, module_path)
    for {
        host.reload_requested = false
        host.exit_requested = false
        host.error_message = ""
        run(app_symbols, state, &host)
        if host.exit_requested {
            return 0
        }
        if host.error_message != "" {
            on_event(Reload_Event{kind = .Checkpoint_Error, generation = session.generation, message = host.error_message})
        }
        if force_restart != nil && force_restart(app_symbols, state) && init_state != nil {
            if session.core.on_unload != nil {
                session.core.on_unload(session.state)
            }
            init_state(state)
            session.core.on_load(session.state, false)
            on_event(Reload_Event{kind = .Restarted, generation = session.generation, message = "app requested restart"})
        }
        force := force_reload != nil && force_reload(app_symbols, state)
        if force {
            session.last_write = {}
        }
        event, changed := poll_session(&session, app_symbols, state, init_state)
        if changed {
            on_event(event)
        }
        host.last_write = session.last_write
    }
    return 0
}
