// Copyright (c) Andreas Flakstad and Olive contributors
// SPDX-License-Identifier: MIT

package tests

import "core:fmt"
import "core:os"
import "core:sync"
import "core:strings"
import "core:testing"
import "core:time"
import olive "../src/olive_core"

build_olive_binary_mutex: sync.Mutex
exec_mutex: sync.Mutex

Exec_Result :: struct {
  exit_code: int,
  stdout:    string,
  stderr:    string,
}

exec :: proc(command: []string, working_dir := "") -> Exec_Result {
  sync.mutex_lock(&exec_mutex)
  defer sync.mutex_unlock(&exec_mutex)

  state, stdout, stderr, err := os.process_exec(
    os.Process_Desc{command = command, working_dir = working_dir},
    context.allocator,
  )
  exit_code := 1
  if err == nil && state.exited {
    exit_code = state.exit_code
  }
  return Exec_Result{exit_code = exit_code, stdout = string(stdout), stderr = string(stderr)}
}

delete_exec_result :: proc(result: Exec_Result) {
  delete(transmute([]byte)result.stdout)
  delete(transmute([]byte)result.stderr)
}

file_contains :: proc(path, needle: string) -> bool {
  data, read_err := os.read_entire_file_from_path(path, context.allocator)
  if read_err != nil {
    return false
  }
  defer delete(data)
  return strings.contains(string(data), needle)
}

wait_for_file_contains :: proc(path, needle: string, attempts: int, delay: time.Duration) -> bool {
  for _ in 0..<attempts {
    if file_contains(path, needle) {
      return true
    }
    time.sleep(delay)
  }
  return false
}

wait_for_file_exists :: proc(path: string, attempts: int, delay: time.Duration) -> bool {
  for _ in 0..<attempts {
    if os.exists(path) {
      return true
    }
    time.sleep(delay)
  }
  return false
}

write_sample_package :: proc(t: ^testing.T, root: string) -> (pkg: string, ok: bool) {
  package_path, join_err := os.join_path({root, "sample"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return "", false
  }
  if os.make_directory_all(package_path) != nil {
    delete(package_path)
    testing.expect_value(t, false, true)
    return "", false
  }
  source_path, source_join_err := os.join_path({package_path, "sample.odin"}, context.allocator)
  testing.expect_value(t, source_join_err == nil, true)
  if source_join_err != nil {
    delete(package_path)
    return "", false
  }
  defer delete(source_path)
  source := `package sample

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return a + b
}

answer :: proc() -> int {
    return 42
}

say :: proc() {
    fmt.println("said")
}
`
  testing.expect_value(t, os.write_entire_file_from_string(source_path, source) == nil, true)
  return package_path, true
}

write_main_package :: proc(t: ^testing.T, root: string) -> (pkg: string, ok: bool) {
  package_path, join_err := os.join_path({root, "app"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return "", false
  }
  if os.make_directory_all(package_path) != nil {
    delete(package_path)
    testing.expect_value(t, false, true)
    return "", false
  }
  source_path, source_join_err := os.join_path({package_path, "app.odin"}, context.allocator)
  testing.expect_value(t, source_join_err == nil, true)
  if source_join_err != nil {
    delete(package_path)
    return "", false
  }
  defer delete(source_path)
  source := `package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return a + b
}

main :: proc() {
    fmt.println(add(1, 2))
}
`
  testing.expect_value(t, os.write_entire_file_from_string(source_path, source) == nil, true)
  return package_path, true
}

write_scratch_main_package :: proc(t: ^testing.T, root: string) -> (pkg: string, ok: bool) {
  package_path, join_err := os.join_path({root, "scratch_app"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return "", false
  }
  if os.make_directory_all(package_path) != nil {
    delete(package_path)
    testing.expect_value(t, false, true)
    return "", false
  }
  source_path, source_join_err := os.join_path({package_path, "app.odin"}, context.allocator)
  testing.expect_value(t, source_join_err == nil, true)
  if source_join_err != nil {
    delete(package_path)
    return "", false
  }
  defer delete(source_path)
  source := `package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return a + b
}

/* add(5, 2) */
add(5, 3)

main :: proc() {
    fmt.println(add(1, 2))
}
`
  testing.expect_value(t, os.write_entire_file_from_string(source_path, source) == nil, true)
  return package_path, true
}

write_test_package :: proc(t: ^testing.T, root: string) -> (pkg: string, ok: bool) {
  package_path, join_err := os.join_path({root, "testpkg"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return "", false
  }
  if os.make_directory_all(package_path) != nil {
    delete(package_path)
    testing.expect_value(t, false, true)
    return "", false
  }
  source_path, source_join_err := os.join_path({package_path, "testpkg.odin"}, context.allocator)
  testing.expect_value(t, source_join_err == nil, true)
  if source_join_err != nil {
    delete(package_path)
    return "", false
  }
  defer delete(source_path)
  source := `package testpkg

import "core:testing"

@(test)
sample_test :: proc(t: ^testing.T) {
    testing.expect_value(t, 2 + 2, 4)
}
`
  testing.expect_value(t, os.write_entire_file_from_string(source_path, source) == nil, true)
  return package_path, true
}

build_olive_binary :: proc(t: ^testing.T, root: string) -> (binary: string, ok: bool) {
  sync.mutex_lock(&build_olive_binary_mutex)
  defer sync.mutex_unlock(&build_olive_binary_mutex)

  executable_name := "olive"
  when ODIN_OS == .Windows {
    executable_name = "olive.exe"
  }
  binary_path, join_err := os.join_path({root, executable_name}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return "", false
  }
  out_arg := strings.clone(fmt.tprintf("-out:%s", binary_path))
  defer delete(out_arg)
  result := exec([]string{"odin", "build", "cmd/olive", out_arg})
  defer delete_exec_result(result)
  if result.exit_code != 0 {
    fmt.eprintln(result.stderr)
  }
  testing.expect_value(t, result.exit_code, 0)
  if result.exit_code != 0 {
    delete(binary_path)
    return "", false
  }
  return binary_path, true
}

@(test)
render_printing_runner :: proc(t: ^testing.T) {
  output := olive.render_runner(olive.Config{
    package_path = "/tmp/pkg",
    code = "target.answer()",
    print_result = true,
    import_path = "../pkg",
  })
  defer delete(output)
  testing.expect_value(t, strings.contains(output, "import \"core:fmt\""), true)
  testing.expect_value(t, strings.contains(output, "import target \"../pkg\""), true)
  testing.expect_value(t, strings.contains(output, "result := target.answer()"), true)
  testing.expect_value(t, strings.contains(output, "fmt.println(result)"), true)
}

@(test)
render_internal_multiline_olive :: proc(t: ^testing.T) {
  output := olive.render_internal_runner(olive.Config{
    package_path = "/tmp/pkg",
    code = "x := 1\nadd(x, 3)",
    print_result = true,
    package_name = "main",
  })
  defer delete(output)
  testing.expect_value(t, strings.contains(output, "package main"), true)
  testing.expect_value(t, strings.contains(output, "    x := 1"), true)
  testing.expect_value(t, strings.contains(output, "    result := add(x, 3)"), true)
  testing.expect_value(t, strings.contains(output, "result := x := 1"), false)
}

@(test)
comment_top_level_scratch_lines :: proc(t: ^testing.T) {
  source := `package main

add :: proc(a: int, b: int) -> int {
    return a + b
}

add(5,3)
`
  output := olive.comment_top_level_scratch_lines(source)
  defer delete(output)
  testing.expect_value(t, strings.contains(output, "add :: proc"), true)
  testing.expect_value(t, strings.contains(output, "/* olive scratch: add(5,3) */"), true)
}

@(test)
render_no_print_runner :: proc(t: ^testing.T) {
  output := olive.render_runner(olive.Config{
    package_path = "/tmp/pkg",
    code = "target.run()",
    print_result = false,
    import_path = "../pkg",
  })
  defer delete(output)
  testing.expect_value(t, strings.contains(output, "    target.run()"), true)
  testing.expect_value(t, strings.contains(output, "fmt.println(result)"), false)
}

@(test)
remap_external_runner_diagnostic_to_olive_expr_line :: proc(t: ^testing.T) {
  stderr := "/tmp/olive-1/main.odin(7:15) Error: Unknown identifier: nope\n"
  output := olive.remap_runner_output_locations(stderr, "/tmp/olive-1/main.odin", "nope()", true, false, 0)
  defer delete(output)
  testing.expect_value(t, output, "<olive>:1:15 Error: Unknown identifier: nope\n")
}

@(test)
remap_internal_runner_diagnostic_to_olive_multiline_source_line :: proc(t: ^testing.T) {
  stderr := "/tmp/olive-1/olive_runner.odin(7:18) Error: Unknown identifier: nope\n"
  code := "x := 1\n\nnope(x)"
  output := olive.remap_runner_output_locations(stderr, "/tmp/olive-1/olive_runner.odin", code, true, true, 0)
  defer delete(output)
  testing.expect_value(t, output, "<olive>:3:18 Error: Unknown identifier: nope\n")
}

@(test)
remap_leaves_non_snippet_diagnostics_alone :: proc(t: ^testing.T) {
  stderr := "/tmp/olive-1/app.odin(3:1) Error: package error\n"
  output := olive.remap_runner_output_locations(stderr, "/tmp/olive-1/olive_runner.odin", "nope()", true, true, 0)
  defer delete(output)
  testing.expect_value(t, output, stderr)
}

@(test)
comment_top_level_scratch_lines_preserves_block_comment :: proc(t: ^testing.T) {
  source := `package main

add :: proc(a: int, b: int) -> int {
    return a + b
}

/*
add(5,3)
*/

another :: proc(a: int) -> int {
    return a * 2
}
`
  output := olive.comment_top_level_scratch_lines(source)
  defer delete(output)
  testing.expect_value(t, strings.contains(output, "/*\nadd(5,3)\n*/"), true)
  testing.expect_value(t, strings.contains(output, "olive scratch: add(5,3)"), false)
}

@(test)
store_values_round_trip :: proc(t: ^testing.T) {
  package_dir, dir_err := os.make_directory_temp("", "olive-store-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(package_dir)
    delete(package_dir)
  }
  testing.expect_value(t, olive.save_value(package_dir, "answer", "42\n"), true)
  value, ok := olive.load_value(package_dir, "answer")
  testing.expect_value(t, ok, true)
  if ok {
    defer delete(transmute([]byte)value)
    testing.expect_value(t, value, "42\n")
  }
  names := olive.list_values(package_dir)
  defer olive.delete_string_slice(names)
  testing.expect_value(t, len(names), 1)
  if len(names) == 1 {
    testing.expect_value(t, names[0], "answer")
  }
  testing.expect_value(t, olive.remove_value(package_dir, "answer"), true)
}

@(test)
compiled_cli_external_and_internal_olive :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-basic-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  sample_pkg, sample_ok := write_sample_package(t, root)
  if !sample_ok {
    return
  }
  defer delete(sample_pkg)
  external_result := exec([]string{binary, "eval", sample_pkg, "target.add(5, 7)"})
  defer delete_exec_result(external_result)
  testing.expect_value(t, external_result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(external_result.stdout), "12")
  check_result := exec([]string{binary, "eval", sample_pkg, "target.answer()", "--check"})
  defer delete_exec_result(check_result)
  testing.expect_value(t, check_result.exit_code, 0)
  no_print_result := exec([]string{binary, "eval", sample_pkg, "target.say()", "--no-print"})
  defer delete_exec_result(no_print_result)
  testing.expect_value(t, no_print_result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(no_print_result.stdout), "said")
  cwd_result := exec([]string{
    binary,
    "eval",
    sample_pkg,
    `_ = os.write_entire_file_from_string("olive-cwd.txt", "ok")`,
    "--no-print",
    "--import",
    `import "core:os"`,
  })
  defer delete_exec_result(cwd_result)
  testing.expect_value(t, cwd_result.exit_code, 0)
  cwd_file, cwd_join_err := os.join_path({sample_pkg, "olive-cwd.txt"}, context.allocator)
  testing.expect_value(t, cwd_join_err == nil, true)
  if cwd_join_err == nil {
    defer delete(cwd_file)
    cwd_data, cwd_read_err := os.read_entire_file_from_path(cwd_file, context.allocator)
    testing.expect_value(t, cwd_read_err == nil, true)
    if cwd_read_err == nil {
      defer delete(cwd_data)
      testing.expect_value(t, string(cwd_data), "ok")
    }
  }
  main_pkg, main_ok := write_main_package(t, root)
  if !main_ok {
    return
  }
  defer delete(main_pkg)
  internal_result := exec([]string{binary, "eval", main_pkg, "add(5, 2)", "--internal"})
  defer delete_exec_result(internal_result)
  testing.expect_value(t, internal_result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(internal_result.stdout), "7")
}

@(test)
compiled_cli_internal_olive_comments_top_level_scratch :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-scratch-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  pkg, pkg_ok := write_scratch_main_package(t, root)
  if !pkg_ok {
    return
  }
  defer delete(pkg)
  keep_dir, keep_join_err := os.join_path({root, "kept-internal"}, context.allocator)
  testing.expect_value(t, keep_join_err == nil, true)
  if keep_join_err != nil {
    return
  }
  defer delete(keep_dir)
  result := exec([]string{binary, "eval", pkg, "add(5, 2)", "--internal", "--keep-dir", keep_dir})
  defer delete_exec_result(result)
  testing.expect_value(t, result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(result.stdout), "7")
  copied_source_path, copied_join_err := os.join_path({keep_dir, "app.odin"}, context.allocator)
  testing.expect_value(t, copied_join_err == nil, true)
  if copied_join_err != nil {
    return
  }
  defer delete(copied_source_path)
  copied_source, read_err := os.read_entire_file_from_path(copied_source_path, context.allocator)
  testing.expect_value(t, read_err == nil, true)
  if read_err == nil {
    defer delete(copied_source)
    testing.expect_value(t, strings.contains(string(copied_source), "/* olive scratch: add(5, 3) */"), true)
    testing.expect_value(t, strings.contains(string(copied_source), "olive_original_main :: proc()"), true)
  }
}

@(test)
compiled_cli_runs_and_writes_generated_source :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  pkg, pkg_ok := write_sample_package(t, root)
  if !pkg_ok {
    return
  }
  defer delete(pkg)
  generated_path, generated_join_err := os.join_path({root, "generated.odin"}, context.allocator)
  testing.expect_value(t, generated_join_err == nil, true)
  if generated_join_err != nil {
    return
  }
  defer delete(generated_path)
  result := exec([]string{binary, "eval", pkg, "target.answer()", "--generated", generated_path})
  defer delete_exec_result(result)
  testing.expect_value(t, result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(result.stdout), "42")
  generated, read_err := os.read_entire_file_from_path(generated_path, context.allocator)
  testing.expect_value(t, read_err == nil, true)
  if read_err == nil {
    defer delete(generated)
    testing.expect_value(t, strings.contains(string(generated), "import target"), true)
    testing.expect_value(t, strings.contains(string(generated), "result := target.answer()"), true)
  }
  show_result := exec([]string{binary, "eval", pkg, "target.answer()", "--show"})
  defer delete_exec_result(show_result)
  if show_result.exit_code != 0 {
    fmt.eprintln(show_result.stderr)
    fmt.eprintln(show_result.stdout)
  }
  testing.expect_value(t, show_result.exit_code, 0)
  testing.expect_value(t, strings.contains(show_result.stdout, "import target"), true)
  testing.expect_value(t, strings.has_suffix(strings.trim_space(show_result.stdout), "42"), true)
}

@(test)
compiled_cli_relative_keep_dir_runs_from_package_cwd :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-keep-dir-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  pkg, pkg_ok := write_sample_package(t, root)
  if !pkg_ok {
    return
  }
  defer delete(pkg)
  keep_dir := "relative-olive-runner"
  result := exec([]string{binary, "eval", pkg, "target.answer()", "--keep-dir", keep_dir}, root)
  defer delete_exec_result(result)
  testing.expect_value(t, result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(result.stdout), "42")
  kept_runner, join_err := os.join_path({root, keep_dir, "main.odin"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err == nil {
    defer delete(kept_runner)
    testing.expect_value(t, os.exists(kept_runner), true)
  }
}

@(test)
compiled_cli_reload_init_check_and_build :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-reload-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  app_dir, app_join_err := os.join_path({root, "reload-app"}, context.allocator)
  testing.expect_value(t, app_join_err == nil, true)
  if app_join_err != nil {
    return
  }
  defer delete(app_dir)
  testing.expect_value(t, os.make_directory_all(app_dir) == nil, true)
  legacy_state_path, legacy_state_join_err := os.join_path({app_dir, "state.odin"}, context.allocator)
  testing.expect_value(t, legacy_state_join_err == nil, true)
  if legacy_state_join_err == nil {
    defer delete(legacy_state_path)
    legacy_state_source := `package main

Program_State :: struct {
    ticks: int,
}
`
    testing.expect_value(t, os.write_entire_file_from_string(legacy_state_path, legacy_state_source) == nil, true)
  }
  legacy_game_path, legacy_game_join_err := os.join_path({app_dir, "game.odin"}, context.allocator)
  testing.expect_value(t, legacy_game_join_err == nil, true)
  if legacy_game_join_err == nil {
    defer delete(legacy_game_path)
    legacy_game_source := `package main

init :: proc(state: ^Program_State) {
    state.ticks = 0
}

tick :: proc(state: ^Program_State) {
    state.ticks += 1
}
`
    testing.expect_value(t, os.write_entire_file_from_string(legacy_game_path, legacy_game_source) == nil, true)
  }

  init_result := exec([]string{binary, "init", app_dir})
  defer delete_exec_result(init_result)
  testing.expect_value(t, init_result.exit_code, 0)

  reload_dir, reload_dir_join_err := os.join_path({app_dir, "reload"}, context.allocator)
  testing.expect_value(t, reload_dir_join_err == nil, true)
  if reload_dir_join_err != nil {
    return
  }
  defer delete(reload_dir)
  reload_path, reload_join_err := os.join_path({reload_dir, "reload.odin"}, context.allocator)
  testing.expect_value(t, reload_join_err == nil, true)
  if reload_join_err != nil {
    return
  }
  defer delete(reload_path)
  if reload_join_err == nil {
    testing.expect_value(t, os.exists(reload_path), true)
  }
  resources_dir, resources_join_err := os.join_path({app_dir, "resources"}, context.allocator)
  testing.expect_value(t, resources_join_err == nil, true)
  if resources_join_err == nil {
    defer delete(resources_dir)
    testing.expect_value(t, os.make_directory_all(resources_dir) == nil, true)
    resource_file, resource_file_join_err := os.join_path({resources_dir, "message.txt"}, context.allocator)
    testing.expect_value(t, resource_file_join_err == nil, true)
    if resource_file_join_err == nil {
      defer delete(resource_file)
      testing.expect_value(t, os.write_entire_file_from_string(resource_file, "hello") == nil, true)
    }
  }
  if reload_join_err == nil {
    reload_source, reload_read_err := os.read_entire_file_from_path(reload_path, context.allocator)
    testing.expect_value(t, reload_read_err == nil, true)
    if reload_read_err == nil {
      defer delete(reload_source)
      builder := strings.builder_make()
      defer strings.builder_destroy(&builder)
      strings.write_string(&builder, string(reload_source))
      strings.write_string(&builder, `
Olive_Watch_Resources :: "../resources"

on_resource_change :: proc(state: ^Reload_State, path: string) {
    _ = path
    state.ticks += 0
}
`)
      testing.expect_value(t, os.write_entire_file_from_string(reload_path, strings.to_string(builder)) == nil, true)
    }
  }
  main_path, main_join_err := os.join_path({app_dir, "main.odin"}, context.allocator)
  testing.expect_value(t, main_join_err == nil, true)
  if main_join_err == nil {
    defer delete(main_path)
    testing.expect_value(t, os.exists(main_path), true)
  }
  state_path, state_join_err := os.join_path({app_dir, "state.odin"}, context.allocator)
  testing.expect_value(t, state_join_err == nil, true)
  if state_join_err == nil {
    defer delete(state_path)
    testing.expect_value(t, os.exists(state_path), false)
  }
  game_path, game_join_err := os.join_path({app_dir, "game.odin"}, context.allocator)
  testing.expect_value(t, game_join_err == nil, true)
  if game_join_err == nil {
    defer delete(game_path)
    testing.expect_value(t, os.exists(game_path), false)
  }

  check_result := exec([]string{binary, "check"}, app_dir)
  defer delete_exec_result(check_result)
  testing.expect_value(t, check_result.exit_code, 0)
  testing.expect_value(t, strings.contains(check_result.stdout, "reload ok"), true)

  paths_result := exec([]string{binary, "paths"}, app_dir)
  defer delete_exec_result(paths_result)
  testing.expect_value(t, paths_result.exit_code, 0)
  testing.expect_value(t, strings.contains(paths_result.stdout, "module_binary:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "package:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "watch:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "resource_watch:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "watch_ignore:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "watch_debounce_ms:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "watch_command:"), true)
  testing.expect_value(t, strings.contains(paths_result.stdout, "build_command:"), true)

  json_paths_result := exec([]string{binary, "paths", "--json"}, app_dir)
  defer delete_exec_result(json_paths_result)
  testing.expect_value(t, json_paths_result.exit_code, 0)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"module_binary"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"package"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"watch"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"resource_watch"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"watch_ignore"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"watch_debounce_ms"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"watch_command"`), true)
  testing.expect_value(t, strings.contains(json_paths_result.stdout, `"build_command"`), true)

  build_result := exec([]string{binary, "build", reload_dir})
  defer delete_exec_result(build_result)
  testing.expect_value(t, build_result.exit_code, 0)

  default_build_result := exec([]string{binary, "build"}, app_dir)
  defer delete_exec_result(default_build_result)
  testing.expect_value(t, default_build_result.exit_code, 0)

  clean_result := exec([]string{binary, "clean"}, app_dir)
  defer delete_exec_result(clean_result)
  testing.expect_value(t, clean_result.exit_code, 0)

  generated_dir, generated_join_err := os.join_path({app_dir, ".olive", "reload", "generated"}, context.allocator)
  testing.expect_value(t, generated_join_err == nil, true)
  if generated_join_err == nil {
    defer delete(generated_dir)
    testing.expect_value(t, os.exists(generated_dir), false)
  }
}

@(test)
compiled_cli_run_notifies_resource_change :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-resource-run-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }

  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)

  app_dir, app_join_err := os.join_path({root, "resource-app"}, context.allocator)
  testing.expect_value(t, app_join_err == nil, true)
  if app_join_err != nil {
    return
  }
  defer delete(app_dir)
  testing.expect_value(t, os.make_directory_all(app_dir) == nil, true)

  resources_dir, resources_join_err := os.join_path({app_dir, "resources"}, context.allocator)
  testing.expect_value(t, resources_join_err == nil, true)
  if resources_join_err != nil {
    return
  }
  defer delete(resources_dir)
  testing.expect_value(t, os.make_directory_all(resources_dir) == nil, true)

  resource_file, resource_join_err := os.join_path({resources_dir, "message.txt"}, context.allocator)
  testing.expect_value(t, resource_join_err == nil, true)
  if resource_join_err != nil {
    return
  }
  defer delete(resource_file)
  testing.expect_value(t, os.write_entire_file_from_string(resource_file, "initial\n") == nil, true)

  started_marker, started_marker_join_err := os.join_path({app_dir, "started.marker"}, context.allocator)
  testing.expect_value(t, started_marker_join_err == nil, true)
  if started_marker_join_err != nil {
    return
  }
  defer delete(started_marker)

  hook_marker, hook_marker_join_err := os.join_path({app_dir, "hook.marker"}, context.allocator)
  testing.expect_value(t, hook_marker_join_err == nil, true)
  if hook_marker_join_err != nil {
    return
  }
  defer delete(hook_marker)

  main_path, main_join_err := os.join_path({app_dir, "main.odin"}, context.allocator)
  testing.expect_value(t, main_join_err == nil, true)
  if main_join_err != nil {
    return
  }
  defer delete(main_path)
  main_source := `package main

import "core:time"

Program_State :: struct {
    ticks: int,
    resource_seen: bool,
}

tick :: proc(state: ^Program_State) {
    state.ticks += 1
    time.sleep(50 * time.Millisecond)
}
`
  testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)

  reload_dir, reload_dir_join_err := os.join_path({app_dir, "reload"}, context.allocator)
  testing.expect_value(t, reload_dir_join_err == nil, true)
  if reload_dir_join_err != nil {
    return
  }
  defer delete(reload_dir)
  testing.expect_value(t, os.make_directory_all(reload_dir) == nil, true)

  reload_path, reload_join_err := os.join_path({app_dir, "reload", "reload.odin"}, context.allocator)
  testing.expect_value(t, reload_join_err == nil, true)
  if reload_join_err != nil {
    return
  }
  defer delete(reload_path)
  reload_builder := strings.builder_make()
  defer strings.builder_destroy(&reload_builder)
  strings.write_string(&reload_builder, `package reload

import "core:fmt"
import "core:os"
import program ".."
import olive_reload "../.olive/reload/runtime/olive_reload"

Reload_State :: program.Program_State

Olive_Watch_Resources :: "../resources"

init :: proc(state: ^Reload_State) {
    _ = state
    _ = os.write_entire_file_from_string(`)
  fmt.sbprintf(&reload_builder, "%q", started_marker)
  strings.write_string(&reload_builder, `, "started\n")
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
    program.tick(state)
    if state.resource_seen {
        olive_reload.request_exit(host)
    }
}

on_resource_change :: proc(state: ^Reload_State, path: string) {
    _ = os.write_entire_file_from_string(`)
  fmt.sbprintf(&reload_builder, "%q", hook_marker)
  strings.write_string(&reload_builder, `, path)
    fmt.println("RESOURCE_HOOK", path)
    state.resource_seen = true
}
`)
  reload_source := strings.clone(strings.to_string(reload_builder))
  defer delete(reload_source)
  testing.expect_value(t, os.write_entire_file_from_string(reload_path, reload_source) == nil, true)

  check_result := exec([]string{binary, "check"}, app_dir)
  defer delete_exec_result(check_result)
  if check_result.exit_code != 0 {
    fmt.eprintln(check_result.stdout)
    fmt.eprintln(check_result.stderr)
  }
  testing.expect_value(t, check_result.exit_code, 0)
  if check_result.exit_code != 0 {
    return
  }

  output_path, output_join_err := os.join_path({root, "resource-run.out"}, context.allocator)
  testing.expect_value(t, output_join_err == nil, true)
  if output_join_err != nil {
    return
  }
  defer delete(output_path)

  output_file, open_err := os.open(output_path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY)
  testing.expect_value(t, open_err == nil, true)
  if open_err != nil {
    return
  }

  process, start_err := os.process_start(os.Process_Desc{
    command = []string{binary, "run"},
    working_dir = app_dir,
    stdout = output_file,
    stderr = output_file,
  })
  testing.expect_value(t, start_err == nil, true)
  if start_err != nil {
    os.close(output_file)
    return
  }

  started := wait_for_file_exists(started_marker, 40, 250 * time.Millisecond)
  testing.expect_value(t, started, true)
  testing.expect_value(t, os.write_entire_file_from_string(resource_file, "changed\n") == nil, true)

  hook_called := wait_for_file_exists(hook_marker, 80, 250 * time.Millisecond)
  if !hook_called {
    _ = os.process_kill(process)
  }
  state, wait_err := os.process_wait(process)
  os.close(output_file)

  event_reported := file_contains(output_path, "[olive] resource changed:")

  testing.expect_value(t, wait_err == nil, true)
  testing.expect_value(t, state.exited, true)
  if state.exited {
    testing.expect_value(t, state.exit_code, 0)
  }
  testing.expect_value(t, hook_called, true)
  when ODIN_OS != .Windows {
    testing.expect_value(t, event_reported, true)
  }
}

@(test)
compiled_cli_store_commands_round_trip :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-cli-store-test-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }
  binary, binary_ok := build_olive_binary(t, root)
  if !binary_ok {
    return
  }
  defer delete(binary)
  pkg, pkg_ok := write_sample_package(t, root)
  if !pkg_ok {
    return
  }
  defer delete(pkg)
  run_result := exec([]string{binary, "eval", pkg, "target.add(20, 22)", "--save", "answer"})
  defer delete_exec_result(run_result)
  testing.expect_value(t, run_result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(run_result.stdout), "42")
  load_result := exec([]string{binary, "store", "load", pkg, "answer"})
  defer delete_exec_result(load_result)
  testing.expect_value(t, load_result.exit_code, 0)
  testing.expect_value(t, load_result.stdout, "42\n")
  list_result := exec([]string{binary, "store", "list", pkg})
  defer delete_exec_result(list_result)
  testing.expect_value(t, list_result.exit_code, 0)
  testing.expect_value(t, strings.trim_space(list_result.stdout), "answer")
  rm_result := exec([]string{binary, "store", "rm", pkg, "answer"})
  defer delete_exec_result(rm_result)
  testing.expect_value(t, rm_result.exit_code, 0)
}
