package probe

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Config :: struct {
  package_path:  string,
  code:          string,
  print_result:  bool,
  extra_imports: []string,
  import_path:   string,
  package_name:  string,
}

Run_Result :: struct {
  exit_code: int,
  stdout:    string,
  stderr:    string,
}

Generated_Location :: struct {
  line:        int,
  column:      int,
  close_index: int,
}

STORE_ENV :: "PROBE_STORE_DIR"

valid_store_name :: proc(name: string) -> bool {
  if name == "" || name == "." || name == ".." {
    return false
  }
  for ch in transmute([]byte)name {
    if (ch >= 'A' && ch <= 'Z') ||
      (ch >= 'a' && ch <= 'z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '.' ||
      ch == '-' {
        continue
      }
    return false
  }
  return true
}

store_dir :: proc(package_path: string) -> (path: string, ok: bool) {
  if override, found := os.lookup_env(STORE_ENV, context.allocator); found {
    return override, true
  }
  package_abs, abs_err := os.get_absolute_path(package_path, context.allocator)
  if abs_err != nil {
    return "", false
  }
  defer delete(package_abs)
  joined, join_err := os.join_path({package_abs, ".probe", "values"}, context.allocator)
  if join_err != nil {
    return "", false
  }
  return joined, true
}

store_path :: proc(package_path, name: string) -> (path: string, ok: bool) {
  if !valid_store_name(name) {
    return "", false
  }
  directory, dir_ok := store_dir(package_path)
  if !dir_ok {
    return "", false
  }
  defer delete(directory)
  joined, join_err := os.join_path({directory, name}, context.allocator)
  if join_err != nil {
    return "", false
  }
  return joined, true
}

save_value :: proc(package_path, name, value: string) -> bool {
  path, path_ok := store_path(package_path, name)
  if !path_ok {
    return false
  }
  defer delete(path)
  directory, dir_ok := store_dir(package_path)
  if !dir_ok {
    return false
  }
  defer delete(directory)
  if !os.exists(directory) && os.make_directory_all(directory) != nil {
    return false
  }
  if os.exists(path) {
    _ = os.remove(path)
  }
  return os.write_entire_file_from_string(path, value) == nil
}

load_value :: proc(package_path, name: string) -> (value: string, ok: bool) {
  path, path_ok := store_path(package_path, name)
  if !path_ok {
    return "", false
  }
  defer delete(path)
  data, read_err := os.read_entire_file_from_path(path, context.allocator)
  if read_err != nil {
    return "", false
  }
  return string(data), true
}

string_less :: proc(a, b: string) -> bool {
  n := len(a)
  if len(b) < n {
    n = len(b)
  }
  for i in 0..<n {
    if a[i] < b[i] {
      return true
    }
    if a[i] > b[i] {
      return false
    }
  }
  return len(a) < len(b)
}

list_values :: proc(package_path: string) -> []string {
  result := make([dynamic]string)

  directory, dir_ok := store_dir(package_path)
  if !dir_ok {
    return result[:]
  }
  defer delete(directory)

  entries, read_err := os.read_directory_by_path(directory, -1, context.allocator)
  if read_err != nil {
    return result[:]
  }
  defer os.file_info_slice_delete(entries, context.allocator)

  for entry in entries {
    if entry.type == .Regular {
      append(&result, strings.clone(entry.name))
    }
  }
  slice.sort_by(result[:], string_less)
  return result[:]
}

delete_string_slice :: proc(values: []string) {
  for value in values {
    delete(value)
  }
  delete(values)
}

remove_value :: proc(package_path, name: string) -> bool {
  path, path_ok := store_path(package_path, name)
  if !path_ok {
    return false
  }
  defer delete(path)
  return os.remove(path) == nil
}

odin_string :: proc(value: string) -> string {
  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  strings.write_byte(&builder, '"')
  for ch in transmute([]byte)value {
    if ch == '\\' || ch == '"' {
      strings.write_byte(&builder, '\\')
    }
    strings.write_byte(&builder, ch)
  }
  strings.write_byte(&builder, '"')
  return strings.clone(strings.to_string(builder))
}

write_body :: proc(builder: ^strings.Builder, code: string, print_result: bool) {
  if print_result {
    lines := code_lines(code)
    defer delete_code_lines(lines)
    if len(lines) > 1 {
      for line in lines[:len(lines)-1] {
        fmt.sbprintf(builder, "    %s\n", line)
      }
      fmt.sbprintf(builder, "    result := %s\n", lines[len(lines)-1])
    } else if len(lines) == 1 {
      fmt.sbprintf(builder, "    result := %s\n", lines[0])
    } else {
      strings.write_string(builder, "    result := nil\n")
    }
    strings.write_string(builder, "    fmt.println(result)\n")
    return
  }
  rest := code
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
    }
    if strings.trim_space(line) == "" {
      strings.write_byte(builder, '\n')
    } else {
      fmt.sbprintf(builder, "    %s\n", line)
    }
    rest = rest[next_start:]
  }
}

render_runner :: proc(config: Config) -> string {
  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  package_abs, abs_err := os.get_absolute_path(config.package_path, context.allocator)
  import_path := config.import_path
  if import_path == "" && abs_err == nil {
    import_path = package_abs
  } else if import_path == "" {
    import_path = config.package_path
  }
  defer if abs_err == nil { delete(package_abs) }
  quoted_import := odin_string(import_path)
  defer delete(quoted_import)
  strings.write_string(&builder, "package main\n\n")
  strings.write_string(&builder, "import \"core:fmt\"\n")
  fmt.sbprintf(&builder, "import target %s\n", quoted_import)
  for import_line in config.extra_imports {
    strings.write_string(&builder, import_line)
    strings.write_byte(&builder, '\n')
  }
  strings.write_string(&builder, "\nmain :: proc() {\n")
  write_body(&builder, config.code, config.print_result)
  strings.write_string(&builder, "}\n")
  return strings.clone(strings.to_string(builder))
}

render_internal_runner :: proc(config: Config) -> string {
  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  package_name := config.package_name
  if package_name == "" {
    package_name = "main"
  }
  fmt.sbprintf(&builder, "package %s\n\n", package_name)
  strings.write_string(&builder, "import \"core:fmt\"\n")
  for import_line in config.extra_imports {
    strings.write_string(&builder, import_line)
    strings.write_byte(&builder, '\n')
  }
  strings.write_string(&builder, "\nmain :: proc() {\n")
  write_body(&builder, config.code, config.print_result)
  strings.write_string(&builder, "}\n")
  return strings.clone(strings.to_string(builder))
}

code_lines :: proc(code: string) -> []string {
  result := make([dynamic]string)
  rest := code
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
    }
    trimmed := strings.trim_space(line)
    if trimmed != "" {
      append(&result, strings.clone(trimmed))
    }
    rest = rest[next_start:]
  }
  return result[:]
}

delete_code_lines :: proc(lines: []string) {
  for line in lines {
    delete(line)
  }
  delete(lines)
}

count_non_empty_code_lines :: proc(code: string) -> int {
  count := 0
  rest := code
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
    }
    if strings.trim_space(line) != "" {
      count += 1
    }
    rest = rest[next_start:]
  }
  return count
}

count_physical_code_lines :: proc(code: string) -> int {
  if code == "" {
    return 0
  }
  count := 0
  rest := code
  for len(rest) > 0 {
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      next_start = newline + 1
    }
    count += 1
    rest = rest[next_start:]
  }
  return count
}

generated_user_start_line :: proc(extra_import_count: int, internal: bool) -> int {
  if internal {
    return 6 + extra_import_count
  }
  return 7 + extra_import_count
}

generated_user_line_count :: proc(code: string, print_result: bool) -> int {
  if print_result {
    count := count_non_empty_code_lines(code)
    if count == 0 {
      return 1
    }
    return count
  }
  return count_physical_code_lines(code)
}

source_line_for_generated_user_line :: proc(code: string, print_result: bool, generated_offset: int) -> int {
  if !print_result {
    return generated_offset + 1
  }

  rest := code
  source_line := 1
  non_empty_seen := 0
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
    }
    if strings.trim_space(line) != "" {
      if non_empty_seen == generated_offset {
        return source_line
      }
      non_empty_seen += 1
    }
    source_line += 1
    rest = rest[next_start:]
  }
  return 1
}

parse_generated_location :: proc(line, generated_path: string) -> (Generated_Location, bool) {
  open_index := strings.index(line, "(")
  if open_index < 0 {
    return {}, false
  }

  file_text := line[:open_index]
  _, generated_file := os.split_path(generated_path)
  _, diagnostic_file := os.split_path(file_text)
  if file_text != generated_path && diagnostic_file != generated_file {
    return {}, false
  }

  location := line[open_index+1:]
  colon_index := strings.index(location, ":")
  close_offset := strings.index(location, ")")
  if colon_index < 0 || close_offset < 0 || colon_index > close_offset {
    return {}, false
  }

  parsed_line, ok_line := strconv.parse_int(location[:colon_index])
  if !ok_line {
    return {}, false
  }

  parsed_column := 0
  if colon_index+1 < close_offset {
    column_text := location[colon_index+1:close_offset]
    if second_colon := strings.index(column_text, ":"); second_colon >= 0 {
      column_text = column_text[:second_colon]
    }
    parsed, ok_column := strconv.parse_int(column_text)
    if ok_column {
      parsed_column = parsed
    }
  }

  return Generated_Location{
    line = parsed_line,
    column = parsed_column,
    close_index = open_index + 1 + close_offset,
  }, true
}

remap_runner_output_locations :: proc(output, runner_path, code: string, print_result, internal: bool, extra_import_count: int) -> string {
  if output == "" || runner_path == "" {
    return strings.clone(output)
  }

  user_start := generated_user_start_line(extra_import_count, internal)
  user_count := generated_user_line_count(code, print_result)
  if user_count == 0 {
    return strings.clone(output)
  }

  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)

  rest := output
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline+1]
      next_start = newline + 1
    }

    location, ok_location := parse_generated_location(line, runner_path)
    if ok_location && location.line >= user_start && location.line < user_start + user_count {
      source_line := source_line_for_generated_user_line(code, print_result, location.line - user_start)
      fmt.sbprintf(&builder, "<probe>:%d:%d", source_line, location.column)
      strings.write_string(&builder, line[location.close_index+1:])
    } else {
      strings.write_string(&builder, line)
    }

    rest = rest[next_start:]
  }

  return strings.clone(strings.to_string(builder))
}

write_runner :: proc(config: Config, directory: string) -> (path: string, ok: bool) {
  _ = os.make_directory_all(directory)
  package_abs, abs_err := os.get_absolute_path(config.package_path, context.allocator)
  if abs_err != nil {
    return "", false
  }
  defer delete(package_abs)
  directory_abs, dir_abs_err := os.get_absolute_path(directory, context.allocator)
  if dir_abs_err != nil {
    return "", false
  }
  defer delete(directory_abs)
  relative_import, rel_err := os.get_relative_path(directory_abs, package_abs, context.allocator)
  if rel_err != nil {
    return "", false
  }
  defer delete(relative_import)
  local_config := config
  local_config.import_path = relative_import
  output := render_runner(local_config)
  defer delete(output)
  joined, join_err := os.join_path({directory, "main.odin"}, context.allocator)
  if join_err != nil {
    return "", false
  }
  if os.write_entire_file_from_string(joined, output) != nil {
    delete(joined)
    return "", false
  }
  return joined, true
}

package_name_from_source :: proc(source: string) -> (name: string, ok: bool) {
  rest := source
  for line in strings.split_lines_iterator(&rest) {
    trimmed := strings.trim_space(line)
    if strings.has_prefix(trimmed, "package ") {
      rest := strings.trim_space(trimmed[len("package "):])
      end := len(rest)
      for ch, i in rest {
        if !(ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_') {
          end = i
          break
        }
      }
      if end > 0 {
        return strings.clone(rest[:end]), true
      }
    }
  }
  return "", false
}

rename_entry_main :: proc(source: string) -> string {
  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  rest := source
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    newline_found := false
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
      newline_found = true
    }
    trimmed := strings.trim_left(line, " \t")
    indent := line[:len(line)-len(trimmed)]
    if strings.has_prefix(trimmed, "main") {
      after := strings.trim_left(trimmed[len("main"):], " \t")
      if strings.has_prefix(after, "::") {
        strings.write_string(&builder, indent)
        strings.write_string(&builder, "probe_original_main")
        strings.write_string(&builder, trimmed[len("main"):])
      } else {
        strings.write_string(&builder, line)
      }
    } else {
      strings.write_string(&builder, line)
    }
    if newline_found {
      strings.write_byte(&builder, '\n')
    }
    rest = rest[next_start:]
  }
  return strings.clone(strings.to_string(builder))
}

is_declaration_line :: proc(line: string) -> bool {
  trimmed := strings.trim_space(line)
  if trimmed == "" {
    return true
  }
  if strings.has_prefix(trimmed, "package ") ||
    strings.has_prefix(trimmed, "import ") ||
    strings.has_prefix(trimmed, "foreign ") ||
    strings.has_prefix(trimmed, "when ") ||
    strings.has_prefix(trimmed, "@(") ||
    strings.has_prefix(trimmed, "#") {
      return true
    }
  return strings.contains(trimmed, "::") ||
    strings.contains(trimmed, ": ") ||
    strings.contains(trimmed, ":= proc")
}

comment_top_level_scratch_lines :: proc(source: string) -> string {
  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  depth := 0
  in_comment := false
  rest := source
  for len(rest) > 0 {
    line := rest
    next_start := len(rest)
    newline_found := false
    if newline := strings.index(rest, "\n"); newline >= 0 {
      line = rest[:newline]
      next_start = newline + 1
      newline_found = true
    }
    stripped := strings.trim_space(line)
    if in_comment {
      strings.write_string(&builder, line)
      if strings.contains(stripped, "*/") {
        in_comment = false
      }
      if newline_found {
        strings.write_byte(&builder, '\n')
      }
      rest = rest[next_start:]
      continue
    }
    is_comment_start := strings.has_prefix(stripped, "/*")
    is_comment_line := strings.has_prefix(stripped, "//") ||
      is_comment_start ||
      strings.has_prefix(stripped, "*")
    if is_comment_start && !strings.contains(stripped, "*/") {
      in_comment = true
    }
    should_comment := depth == 0 &&
      stripped != "" &&
      !is_comment_line &&
      stripped != "}" &&
      stripped != "}," &&
      !is_declaration_line(line)
    if should_comment {
      indent := line[:len(line)-len(strings.trim_left(line, " \t"))]
      fmt.sbprintf(&builder, "%s/* probe scratch: %s */", indent, stripped)
    } else {
      strings.write_string(&builder, line)
    }
    for ch in transmute([]byte)line {
      if ch == '{' {
        depth += 1
      } else if ch == '}' {
        depth -= 1
        if depth < 0 {
          depth = 0
        }
      }
    }
    if newline_found {
      strings.write_byte(&builder, '\n')
    }
    rest = rest[next_start:]
  }
  return strings.clone(strings.to_string(builder))
}

copy_package_for_internal_probe :: proc(package_path, directory: string) -> (package_name: string, ok: bool) {
  _ = os.make_directory_all(directory)
  entries, read_err := os.read_directory_by_path(package_path, -1, context.allocator)
  if read_err != nil {
    return "", false
  }
  defer os.file_info_slice_delete(entries, context.allocator)
  copied := false
  discovered_name := ""
  for entry in entries {
    if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
      continue
    }
    source_path, join_source_err := os.join_path({package_path, entry.name}, context.allocator)
    if join_source_err != nil {
      continue
    }
    defer delete(source_path)
    data, read_source_err := os.read_entire_file_from_path(source_path, context.allocator)
    if read_source_err != nil {
      return "", false
    }
    source := string(data)
    if discovered_name == "" {
      name, name_ok := package_name_from_source(source)
      if name_ok {
        discovered_name = name
      }
    }
    renamed := rename_entry_main(source)
    commented := comment_top_level_scratch_lines(renamed)
    delete(renamed)
    delete(data)
    defer delete(commented)
    destination_path, join_dest_err := os.join_path({directory, entry.name}, context.allocator)
    if join_dest_err != nil {
      return "", false
    }
    defer delete(destination_path)
    if os.write_entire_file_from_string(destination_path, commented) != nil {
      return "", false
    }
    copied = true
  }
  if !copied || discovered_name == "" {
    if discovered_name != "" {
      delete(discovered_name)
    }
    return "", false
  }
  return discovered_name, true
}

write_internal_runner :: proc(config: Config, directory: string) -> (path: string, ok: bool) {
  package_name, package_ok := copy_package_for_internal_probe(config.package_path, directory)
  if !package_ok {
    return "", false
  }
  defer delete(package_name)
  local_config := config
  local_config.package_name = package_name
  output := render_internal_runner(local_config)
  defer delete(output)
  joined, join_err := os.join_path({directory, "probe_runner.odin"}, context.allocator)
  if join_err != nil {
    return "", false
  }
  if os.write_entire_file_from_string(joined, output) != nil {
    delete(joined)
    return "", false
  }
  return joined, true
}

run_odin :: proc(action, runner_dir, working_dir: string) -> Run_Result {
  args := make([dynamic]string, 0, 5)
  defer delete(args)
  append(&args, "odin", action, runner_dir)
  out_dir := ""
  out_path := ""
  out_arg := ""
  if action == "run" || action == "build" {
    dir, dir_err := os.make_directory_temp(runner_dir, "probe-bin-*", context.allocator)
    if dir_err == nil {
      out_dir = dir
      joined, join_err := os.join_path({out_dir, "probe.bin"}, context.allocator)
      if join_err == nil {
        out_path = joined
      }
    }
    if out_path != "" {
      out_arg = strings.clone(fmt.tprintf("-out:%s", out_path))
      append(&args, out_arg)
    }
  }
  defer if out_dir != "" {
    _ = os.remove_all(out_dir)
    delete(out_dir)
  }
  defer if out_path != "" { delete(out_path) }
  defer if out_arg != "" {
    delete(out_arg)
  }
  state, stdout, stderr, err := os.process_exec(
    os.Process_Desc{command = args[:], working_dir = working_dir},
    context.allocator,
  )
  exit_code := 1
  if err == nil && state.exited {
    exit_code = state.exit_code
  }
  return Run_Result{exit_code = exit_code, stdout = string(stdout), stderr = string(stderr)}
}

run_odin_package :: proc(action, package_path: string, extra_args: []string) -> Run_Result {
  args := make([dynamic]string, 0, 3+len(extra_args))
  defer delete(args)
  append(&args, "odin", action, package_path)
  for arg in extra_args {
    append(&args, arg)
  }

  process, start_err := os.process_start(os.Process_Desc{
    command = args[:],
    stdin   = os.stdin,
    stdout  = os.stdout,
    stderr  = os.stderr,
  })
  exit_code := 1
  if start_err != nil {
    return Run_Result{exit_code = exit_code}
  }
  state, wait_err := os.process_wait(process)
  if wait_err == nil && state.exited {
    exit_code = state.exit_code
  }
  return Run_Result{exit_code = exit_code}
}
