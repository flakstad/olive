package tests

import "core:os"
import "core:strings"
import "core:testing"
import reload "../src/olive_reload"

@(test)
resource_watch_ignore_skips_exact_directory_names :: proc(t: ^testing.T) {
  root, dir_err := os.make_directory_temp("", "olive-resource-ignore-*", context.allocator)
  testing.expect_value(t, dir_err == nil, true)
  if dir_err != nil {
    return
  }
  defer {
    _ = os.remove_all(root)
    delete(root)
  }

  ignored_path, join_err := os.join_path({root, ".worktrees", "branch", "asset.txt"}, context.allocator)
  testing.expect_value(t, join_err == nil, true)
  if join_err != nil {
    return
  }
  defer delete(ignored_path)
  ignored_dir, _ := os.split_path(ignored_path)
  testing.expect_value(t, os.make_directory_all(ignored_dir) == nil, true)
  testing.expect_value(t, os.write_entire_file_from_string(ignored_path, "ignored") == nil, true)

  _, path, found := reload.newest_resource_write_time([]string{root}, []string{".worktrees"})
  if found {
    delete(path)
  }
  testing.expect_value(t, found, false)

  _, path_without_ignores, found_without_ignores := reload.newest_resource_write_time([]string{root})
  testing.expect_value(t, found_without_ignores, true)
  if found_without_ignores {
    testing.expect_value(t, strings.has_suffix(path_without_ignores, "asset.txt"), true)
    delete(path_without_ignores)
  }

  kept_path, kept_join_err := os.join_path({root, ".worktrees-old", "asset.txt"}, context.allocator)
  testing.expect_value(t, kept_join_err == nil, true)
  if kept_join_err != nil {
    return
  }
  defer delete(kept_path)
  kept_dir, _ := os.split_path(kept_path)
  testing.expect_value(t, os.make_directory_all(kept_dir) == nil, true)
  testing.expect_value(t, os.write_entire_file_from_string(kept_path, "kept") == nil, true)

  _, exact_path, found_exact_only := reload.newest_resource_write_time([]string{root}, []string{".worktrees"})
  testing.expect_value(t, found_exact_only, true)
  if found_exact_only {
    testing.expect_value(t, strings.contains(exact_path, ".worktrees-old"), true)
    delete(exact_path)
  }
}
