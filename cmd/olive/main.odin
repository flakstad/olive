package main

import "core:fmt"
import "core:os"
import olive "../../src/olive_core"

usage :: proc() {
  fmt.println("usage:")
  fmt.println("  olive init <dir>")
  fmt.println("  olive generate [reload-dir]")
  fmt.println("  olive check [reload-dir]")
  fmt.println("  olive run [reload-dir] [--json]")
  fmt.println("  olive build [reload-dir]")
  fmt.println("  olive watch [reload-dir]")
  fmt.println("  olive paths [reload-dir] [--json]")
  fmt.println("  olive clean [reload-dir]")
  fmt.println("  olive eval <package> <code> [--check] [--no-print] [--show] [--generated file] [--internal] [--keep-dir dir] [--import line] [--save name]")
  fmt.println("  olive store path <package>")
  fmt.println("  olive store save <package> <name> <value>")
  fmt.println("  olive store load <package> <name>")
  fmt.println("  olive store list <package>")
  fmt.println("  olive store rm <package> <name>")
}

print_result :: proc(result: olive.Run_Result) {
  if len(result.stdout) > 0 {
    fmt.print(result.stdout)
  }
  if len(result.stderr) > 0 {
    fmt.eprint(result.stderr)
  }
}

Eval_Options :: struct {
  target_package: string,
  code:           string,
  action:         string,
  no_print:       bool,
  show:           bool,
  internal:       bool,
  keep_dir:       string,
  generated_path: string,
  save_name:      string,
  imports:        [dynamic]string,
}

Runner_Dir :: struct {
  path:      string,
  temp_dir:  string,
  owns_path: bool,
}

delete_eval_options :: proc(options: ^Eval_Options) {
  delete(options.imports)
  options.imports = nil
}

delete_runner_dir :: proc(runner_dir: Runner_Dir) {
  if runner_dir.temp_dir != "" {
    _ = os.remove_all(runner_dir.temp_dir)
    delete(runner_dir.temp_dir)
  } else if runner_dir.owns_path && runner_dir.path != "" {
    delete(runner_dir.path)
  }
}

parse_eval_options :: proc() -> (Eval_Options, int, bool) {
  if len(os.args) < 4 {
    usage()
    return {}, 2, false
  }

  options := Eval_Options{
    target_package = os.args[2],
    code = os.args[3],
    action = "run",
    imports = make([dynamic]string),
  }

  i := 4
  for i < len(os.args) {
    switch os.args[i] {
    case "--check":
      options.action = "check"
      i += 1
    case "--no-print":
      options.no_print = true
      i += 1
    case "--show":
      options.show = true
      i += 1
    case "--internal":
      options.internal = true
      i += 1
    case "--keep-dir":
      if i+1 >= len(os.args) {
        usage()
        delete_eval_options(&options)
        return {}, 2, false
      }
      options.keep_dir = os.args[i+1]
      i += 2
    case "--generated":
      if i+1 >= len(os.args) {
        usage()
        delete_eval_options(&options)
        return {}, 2, false
      }
      options.generated_path = os.args[i+1]
      i += 2
    case "--save":
      if i+1 >= len(os.args) {
        usage()
        delete_eval_options(&options)
        return {}, 2, false
      }
      options.save_name = os.args[i+1]
      i += 2
    case "--import":
      if i+1 >= len(os.args) {
        usage()
        delete_eval_options(&options)
        return {}, 2, false
      }
      append(&options.imports, os.args[i+1])
      i += 2
      case:
      usage()
      delete_eval_options(&options)
      return {}, 2, false
    }
  }

  return options, 0, true
}

resolve_eval_runner_dir :: proc(keep_dir: string) -> (Runner_Dir, int, bool) {
  if keep_dir != "" {
    if os.is_absolute_path(keep_dir) {
      return Runner_Dir{path = keep_dir}, 0, true
    }

    cwd, cwd_err := os.get_working_directory(context.allocator)
    if cwd_err != nil {
      fmt.eprintln("failed to resolve current directory")
      return {}, 2, false
    }
    defer delete(cwd)

    abs_runner_dir, join_err := os.join_path({cwd, keep_dir}, context.allocator)
    if join_err != nil {
      fmt.eprintln("failed to resolve keep directory: ", keep_dir)
      return {}, 2, false
    }
    return Runner_Dir{path = abs_runner_dir, owns_path = true}, 0, true
  }

  dir, dir_err := os.make_directory_temp("", "olive-*", context.allocator)
  if dir_err != nil {
    fmt.eprintln("failed to create temporary directory")
    return {}, 1, false
  }
  return Runner_Dir{path = dir, temp_dir = dir}, 0, true
}

write_eval_runner :: proc(config: olive.Config, runner_dir: string, internal: bool) -> (path: string, ok: bool) {
  if internal {
    return olive.write_internal_runner(config, runner_dir)
  }
  return olive.write_runner(config, runner_dir)
}

write_generated_eval_output :: proc(runner, generated_path: string, show: bool) -> int {
  if !show && generated_path == "" {
    return 0
  }

  data, read_err := os.read_entire_file_from_path(runner, context.allocator)
  if read_err != nil {
    fmt.eprintln("failed to read generated Odin: ", runner)
    return 1
  }
  defer delete(data)

  if generated_path != "" {
    if os.write_entire_file(generated_path, data) != nil {
      fmt.eprintln("failed to write generated Odin: ", generated_path)
      return 1
    }
  }
  if show {
    fmt.print(string(data))
  }
  return 0
}

parse_eval_command :: proc() -> int {
  options, status, options_ok := parse_eval_options()
  if !options_ok {
    return status
  }
  defer delete_eval_options(&options)

  if !os.exists(options.target_package) {
    fmt.eprintln("package path does not exist: ", options.target_package)
    return 2
  }

  runner_dir, runner_status, runner_dir_ok := resolve_eval_runner_dir(options.keep_dir)
  if !runner_dir_ok {
    return runner_status
  }
  defer delete_runner_dir(runner_dir)

  config := olive.Config{
    package_path = options.target_package,
    code         = options.code,
    print_result = !options.no_print,
    extra_imports = options.imports[:],
  }

  runner, ok := write_eval_runner(config, runner_dir.path, options.internal)
  if !ok {
    fmt.eprintln("failed to generate olive runner")
    return 2
  }
  defer delete(runner)

  if generated_status := write_generated_eval_output(runner, options.generated_path, options.show); generated_status != 0 {
    return generated_status
  }

  result := olive.run_odin(options.action, runner_dir.path, options.target_package)
  defer delete(transmute([]byte)result.stdout)
  defer delete(transmute([]byte)result.stderr)
  if options.save_name != "" && result.exit_code == 0 {
    if !olive.valid_store_name(options.save_name) {
      fmt.eprintln("store name must contain only letters, digits, '_', '.', or '-'")
      return 2
    }
    if !olive.save_value(options.target_package, options.save_name, result.stdout) {
      fmt.eprintln("failed to save stored value")
      return 1
    }
  }
  mapped_stderr := olive.remap_runner_output_locations(result.stderr, runner, options.code, !options.no_print, options.internal, len(options.imports))
  defer delete(mapped_stderr)
  print_result(olive.Run_Result{
    exit_code = result.exit_code,
    stdout    = result.stdout,
    stderr    = mapped_stderr,
  })
  return result.exit_code
}

parse_store_command :: proc() -> int {
  if len(os.args) < 4 {
    usage()
    return 2
  }

  action := os.args[2]
  target_package := os.args[3]
  if !os.exists(target_package) {
    fmt.eprintln("package path does not exist: ", target_package)
    return 2
  }

  switch action {
  case "path":
    if len(os.args) != 4 {
      usage()
      return 2
    }
    directory, ok := olive.store_dir(target_package)
    if !ok {
      fmt.eprintln("failed to resolve store path")
      return 1
    }
    defer delete(directory)
    fmt.println(directory)
    return 0
  case "save":
    if len(os.args) != 6 {
      usage()
      return 2
    }
    name := os.args[4]
    value := os.args[5]
    if !olive.valid_store_name(name) {
      fmt.eprintln("store name must contain only letters, digits, '_', '.', or '-'")
      return 2
    }
    if !olive.save_value(target_package, name, value) {
      fmt.eprintln("failed to save stored value")
      return 1
    }
    return 0
  case "load":
    if len(os.args) != 5 {
      usage()
      return 2
    }
    name := os.args[4]
    if !olive.valid_store_name(name) {
      fmt.eprintln("store name must contain only letters, digits, '_', '.', or '-'")
      return 2
    }
    value, ok := olive.load_value(target_package, name)
    if !ok {
      fmt.eprintln("stored value not found: ", name)
      return 1
    }
    defer delete(transmute([]byte)value)
    fmt.print(value)
    return 0
  case "list":
    if len(os.args) != 4 {
      usage()
      return 2
    }
    names := olive.list_values(target_package)
    defer olive.delete_string_slice(names)
    for name in names {
      fmt.println(name)
    }
    return 0
  case "rm":
    if len(os.args) != 5 {
      usage()
      return 2
    }
    name := os.args[4]
    if !olive.valid_store_name(name) {
      fmt.eprintln("store name must contain only letters, digits, '_', '.', or '-'")
      return 2
    }
    if !olive.remove_value(target_package, name) {
      fmt.eprintln("stored value not found: ", name)
      return 1
    }
    return 0
    case:
    usage()
    return 2
  }
}

main :: proc() {
  if len(os.args) < 2 {
    usage()
    os.exit(2)
  }

  switch os.args[1] {
  case "init", "generate", "check", "run", "build", "watch", "paths", "clean":
    os.exit(parse_reload_command())
  case "eval":
    os.exit(parse_eval_command())
  case "store":
    os.exit(parse_store_command())
  case "-h", "--help", "help":
    usage()
    case:
    usage()
    os.exit(2)
  }
}
