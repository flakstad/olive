package main

import "core:os"
import "core:strings"
import "core:testing"

join_test_path :: proc(t: ^testing.T, parts: []string) -> (string, bool) {
  path, err := os.join_path(parts, context.allocator)
  testing.expect_value(t, err == nil, true)
  if err != nil {
    return "", false
  }
  return path, true
}

write_test_file :: proc(t: ^testing.T, path, content: string) -> bool {
  dir, _ := os.split_path(path)
  if dir != "" {
    testing.expect_value(t, os.make_directory_all(dir) == nil, true)
  }
  ok := os.write_entire_file_from_string(path, content) == nil
  testing.expect_value(t, ok, true)
  return ok
}

delete_test_string :: proc(value: string) {
  if value != "" {
    delete(value)
  }
}

delete_test_reload_target :: proc(cfg: ^Reload_Target) {
  delete_test_string(cfg.root)
  delete_test_string(cfg.package_path)
  delete_test_string(cfg.runtime_path)
  delete_test_string(cfg.state_type)
  delete_test_string(cfg.run_name)
  delete_test_string(cfg.init_name)
  delete_test_string(cfg.on_load_name)
  delete_test_string(cfg.on_unload_name)
  delete_test_string(cfg.resource_change_name)
  delete_test_string(cfg.force_reload_name)
  delete_test_string(cfg.force_restart_name)
  delete_test_string(cfg.host_init_name)
  delete_test_string(cfg.host_shutdown_name)
  delete_test_string(cfg.module_name)
  delete_test_string(cfg.watch_paths)
  delete_test_string(cfg.resource_watch_paths)
  delete_test_string(cfg.watch_ignore_names)
  delete_test_string(cfg.watch_debounce_ms)
  delete_test_string(cfg.odin_args)
  cfg^ = {}
}

@(test)
watch_ignore_skips_exact_directory_names :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-watch-ignore-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }

  ignored_source, ignored_ok := join_test_path(t, []string{root, ".worktrees", "branch", "ignored.odin"})
  if !ignored_ok {
    return
  }
  defer delete(ignored_source)
  if !write_test_file(t, ignored_source, "package ignored\n") {
    return
  }

  ignore_names := comma_names_for(DEFAULT_WATCH_IGNORE)
  defer delete_string_list(ignore_names)
  _, found_ignored := newest_odin_write_time(root, ignore_names[:])
  testing.expect_value(t, found_ignored, false)

  _, found_without_ignores := newest_odin_write_time(root)
  testing.expect_value(t, found_without_ignores, true)

  kept_source, kept_ok := join_test_path(t, []string{root, ".worktrees-old", "kept.odin"})
  if !kept_ok {
    return
  }
  defer delete(kept_source)
  if !write_test_file(t, kept_source, "package kept\n") {
    return
  }

  _, found_exact_only := newest_odin_write_time(root, ignore_names[:])
  testing.expect_value(t, found_exact_only, true)
}

@(test)
watch_ignore_constant_can_be_empty :: proc(t: ^testing.T) {
  names := comma_names_for("")
  defer delete_string_list(names)
  testing.expect_value(t, len(names), 0)

  custom := comma_names_for(" .git , .olive ")
  defer delete_string_list(custom)
  testing.expect_value(t, len(custom), 2)
  if len(custom) == 2 {
    testing.expect_value(t, custom[0], ".git")
    testing.expect_value(t, custom[1], ".olive")
    testing.expect_value(t, strings.contains(custom[0], " "), false)
  }
}

@(test)
reload_source_parser_finds_conventional_declarations :: proc(t: ^testing.T) {
  source := `package reload

import olive_reload "../src/olive_reload"

Reload_State :: app.Program_State

runaway :: proc() {}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
    _ = state
    _ = host
}

Olive_Watch :: "../src, ../cmd"
`
  testing.expect_value(t, has_reload_state_alias(source), true)
  testing.expect_value(t, has_conventional_proc(source, "run"), true)
  testing.expect_value(t, has_conventional_proc(source, "missing"), false)

  import_path, import_ok := named_import_path(source, "olive_reload")
  testing.expect_value(t, import_ok, true)
  if import_ok {
    defer delete(import_path)
    testing.expect_value(t, import_path, "../src/olive_reload")
  }

  watch_value, watch_ok := conventional_string_value(source, "Olive_Watch")
  testing.expect_value(t, watch_ok, true)
  if watch_ok {
    defer delete(watch_value)
    testing.expect_value(t, watch_value, "../src, ../cmd")
  }
}

@(test)
reload_target_defaults_to_managed_runtime :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-runtime-default-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }

  reload_source, source_ok := join_test_path(t, []string{root, "reload.odin"})
  if !source_ok {
    return
  }
  defer delete(reload_source)
  if os.write_entire_file_from_string(reload_source, `package reload

Reload_State :: Program_State

Program_State :: struct {}

run :: proc(state: ^Reload_State, host: rawptr) {
    _ = state
    _ = host
}
`) != nil {
    testing.expect_value(t, false, true)
    return
  }

  cfg, message, ok := read_reload_target(root)
  if message != "" {
    defer delete(message)
  }
  testing.expect_value(t, ok, true)
  if ok {
    defer delete_test_reload_target(&cfg)
    testing.expect_value(t, cfg.runtime_path, DEFAULT_MANAGED_RUNTIME_PATH)
  }
}
