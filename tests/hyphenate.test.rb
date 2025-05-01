#!/usr/bin/env ruby

# ----------------------------------------------------------------------

# hyphenate.test.rb
#
# Tests hyphenate.rb
#
# Usage: env [TMPDIR="/tmp"] ruby hyphenate.test.rb [script_path [ruby]]
#
# Copyright © 2025 konsolebox
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files
# (the “Software”), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# ----------------------------------------------------------------------

require 'fileutils'
require 'shellwords'
require 'test/unit'
require 'tmpdir'

$script_path = ARGV[0] || File.expand_path("../../hyphenate.rb", __FILE__)
$ruby = ARGV[1] || "ruby"
ENV['TMPDIR'] ||= "/tmp"

class TestHyphenateRb < Test::Unit::TestCase
  module Helpers
    def self.included(base)
      # At least make sure public methods of the includer class's superclass aren't overridden
      conflict = instance_methods.find{ |m| base.superclass.instance_methods.include?(m) }
      raise NameError, "Method already defined in #{base}: #{conflict}" if conflict
    end

    # Assert that a file exists at the specified path
    def assert_file_exist(path, message)
      assert_true(File.exist?(path), message)
    end

    # Assert that a file does not exist at the specified path
    def assert_file_not_exist(path, message)
      assert_false(File.exist?(path), message)
    end

    # Recursively create files and directories
    def create_file_structure(structure, base_dir = ".")
      structure.each do |path, content|
        full_path = File.join(base_dir, path)

        if content.is_a?(Hash)
          Dir.mkdir(full_path)
          create_file_structure(content, full_path)
        else
          File.write(full_path, content || "test content")
        end
      end
    end

    # Create common nested structure used for testing recursive features
    def create_common_nested_structure(base_dir = ".")
      create_file_structure({
        "ParentDir" => {
          "already-hyphenated.txt" => "test content",
          "NeedsRenaming.txt" => "test content",
          "SomeFile.ts" => "test content",
          "SubDir" => {
            "NestedFile.ts" => "test content"
          }
        }
      }, base_dir)

      # Create a symbolic link after the structure is created
      File.symlink("already-hyphenated.txt", File.join(base_dir, "ParentDir", "SymLink"))
    end

    # Creates a regex out of a string with no special meaning
    def str_to_regex(str)
      Regexp.compile(Regexp.escape(str))
    end

    # Alias for File.expand_path
    def expand_path(*args)
      File.expand_path(*args)
    end

    # Create alias for common methods; avoid lengthiness in many instances of the code
    alias_method :_p, :expand_path
    alias_method :_r, :str_to_regex
  end

  include Helpers

  class ScriptRunner
    class Result < Struct.new(:output, :status)
    end

    attr_reader :script_path, :script_path_escaped, :ruby, :ruby_escaped

    def initialize(script_path, ruby)
      raise "Script doesn't exist: #{script_path}" unless File.exist?(script_path)

      @script_path = File.expand_path(script_path)
      @script_path_escaped = Shellwords.escape(@script_path)
      @ruby = ruby
      @ruby_escaped =  Shellwords.escape(ruby)

      unless system("test -f #{@script_path_escaped}")
        raise "Script not found through its escaped path: #{@script_path_escaped}"
      end

      unless system("#{@ruby_escaped} -e true >/dev/null 2>&1")
        raise "Ruby command in escaped form fails to execute: #{@ruby_escaped}"
      end
    end

    # Run the hyphenate.rb script with arguments and optional output redirection
    # @param args [Array<String>] Script arguments
    # @param stdout [String, Integer] Redirect stdout (e.g., "/dev/null") or duplicate a file descriptor
    # @param stderr [String, Integer] Redirect stderr (e.g., "/dev/null") or duplicate a file descriptor; usually 1
    # @return [Result] Struct with output and status
    def run(*args, **opts)
      command = [@ruby_escaped, @script_path_escaped] + args.map{ |a| Shellwords.escape(a) }
      stdout, stderr = opts.values_at(:stdout, :stderr)
      command << ">#{stdout.is_a?(Integer) ? "&#{stdout}" : Shellwords.escape(stdout)}" if stdout
      command << "2>#{stderr.is_a?(Integer) ? "&#{stderr}" : Shellwords.escape(stderr)}" if stderr
      Result.new(`#{command.join(' ')}`, $?)
    end

    def run_quietly(*args, **opts)
      run(*args, stdout: "/dev/null", stderr: "/dev/null", **opts)
    end
  end

  def initialize(*args, **opts)
    super
    @runner = ScriptRunner.new($script_path, $ruby)
  end

  def setup
    # Store original directory
    @original_dir = Dir.pwd

    # Create a temporary directory for testing and change to it
    @temp_dir = Dir.mktmpdir("test_hyphenate_#{self.class}_#{__method__}", ENV['TMPDIR'])
    Dir.chdir(@temp_dir)
  end

  def teardown
    # Clean up temporary directory and return to original directory
    Dir.chdir(@original_dir)
    FileUtils.remove_entry(@temp_dir) if File.exist?(@temp_dir)
  end

  # Test files are kept untouched when already hyphenated
  def test_already_hyphenated_files
    # Setup test structure
    create_file_structure({
      "TestDir" => {
        "already-hyphenated.txt" => "test content",
        "NeedsRenaming.txt" => "test content"
      }
    })

    # Run the script
    output = @runner.run("-r", "-v", "TestDir", stderr: 1).output

    # Verify that files aren't touched
    assert_match(_r("File is already in its proper form: #{_p('TestDir/already-hyphenated.txt')}"),
                 output, "Verbose should indicate unchanged file")
    assert_match(_r("[FILE] #{_p('TestDir/NeedsRenaming.txt')} -> needs-renaming.txt"),
                 output, "Verbose should show renaming action")
    assert_file_exist("TestDir/already-hyphenated.txt", "Already hyphenated file should remain")
    assert_file_exist("TestDir/needs-renaming.txt", "File should be renamed")
  end

  # Test dry-run mode
  def test_dry_run
    # Create test file
    File.write("DryRunTestFile.ts", "test content")

    # Run the script in dry-run mode
    output = @runner.run("-n", "DryRunTestFile.ts").output

    # Verify output and file status
    matcher = /\[FILE\] #{Regexp.escape(_p("DryRunTestFile.ts"))} -> dry-run-test-file.ts/
    assert_match(matcher, output, "Dry-run should show renaming intention")
    assert_file_exist("DryRunTestFile.ts", "File should not be renamed in dry-run")
    assert_file_not_exist("dry-run-test-file.ts", "Renamed file should not exist")
  end

  # Test empty directory in recursive mode
  def test_empty_directory_recursive
    # Setup test structure
    create_file_structure({
      "EmptyDir" => {
        "SubDir" => {}
      }
    })

    # Run the script
    @runner.run("-r", "-d", "EmptyDir", stdout: "/dev/null")

    # Verify both EmptyDir and EmptyDir/SubDir got renamed
    assert_file_not_exist("EmptyDir", "Original directory should not exist")
    assert_file_exist("empty-dir", "Renamed directory should exist")
    assert_file_not_exist("empty-dir/SubDir", "Original subdirectory should not exist")
    assert_file_exist("empty-dir/sub-dir", "Renamed subdirectory should exist")
  end

  # Test help output
  def test_help_output
    # Run the script with -h
    output = @runner.run("-h", stderr: 1).output

    # Verify key parts of help output
    assert_match(/hyphenate \d\d\d\d.\d\d.\d\d/, output, "Help should show version")
    assert_match(_r("Usage: hyphenate [options] [--] files|dirs"), output, "Help should show usage")
    assert_match(_r("-d, --rename-directories"), output, "Help should list rename-directories option")
  end

  # Test long filenames
  def test_long_filename
    # Create a long filename
    long_name = "LongFileName" * 20 + ".txt"
    File.write(long_name, "test content")

    # Run the script
    status = @runner.run_quietly(long_name).status

    # Verify renaming (or graceful failure)
    if status.success?
      assert_file_not_exist(long_name, "Original long file should not exist")
      assert_file_exist((["long-file-name"] * 20).join('-') + ".txt", "Renamed long file should exist")
    else
      assert_file_exist(long_name, "Original long file should remain on failure")
    end
  end

  # Test GetHyphenatedForm’s handling of multi-dot filenames
  def test_multiple_dots
    # Create files
    File.write("module.functionName.txt", "test content")
    File.write("testModule.functionName.txt", "test content")

    # Run the script
    @runner.run("module.functionName.txt", "testModule.functionName.txt", stdout: "/dev/null")

    # Verify that both files were renamed
    assert_file_not_exist("module.functionName.txt", "Original file should not exist")
    assert_file_exist("module.function-name.txt", "Renamed file should exist")
    assert_file_not_exist("testModule.functionName.txt", "Original file should not exist")
    assert_file_exist("test-module.function-name.txt", "Renamed file should exist")
  end

  # Test multiple files with same hyphenated form
  def test_multiple_files_same_hyphenated_form
    # Create files with same hyphenated form
    File.write("TestFile.txt", "test content")
    File.write("TestFile.doc", "doc content")

    # Run the script
    output = @runner.run("TestFile.txt", "TestFile.doc", stdout: 1).output

    # Verify that both files can be renamed even if they have different filename extensions
    renamed_exists = File.exist?("test-file.txt")
    assert_true(File.exist?("test-file.txt") && File.exist?("test-file.doc"),
                "Files with similar hyphenated form but different extensions should still rename")
  end

  # Test naming conflict
  def test_naming_conflict
    # Create conflicting files
    File.write("TestFile.txt", "test content")
    File.write("test-file.txt", "conflict content")

    # Run the script
    status = @runner.run_quietly("TestFile.txt").status

    # Verify failure and file status
    assert_false(status.success?, "Script should fail on naming conflict")
    assert_file_exist("TestFile.txt", "Original file should remain")
    assert_file_exist("test-file.txt", "Conflicting file should remain")
  end

  # Test empty arguments
  def test_no_arguments
    # Run the script without arguments
    status = @runner.run_quietly().status

    # Verify failure
    assert_false(status.success?, "Script should fail with no arguments")
  end

  # Test error on non-existent file
  def test_non_existent_file
    # Run the script with a non-existent file
    status = @runner.run_quietly("NonExistentFile.txt").status

    # Verify the script fails (non-zero exit status)
    assert_false(status.success?, "Script should fail on non-existent file")
  end

  # Test non-regular files (e.g., pipes or sockets)
  def test_non_regular_file_skipped
    # SKip test if mkfifo isn't available
    unless system("which mkfifo >/dev/null 2>&1")
      skip "Warning: Skipping skip on non-regular files test since mkfifo isn't available"
    end

    # Create a named pipe (if supported)
    pipe_name = "test_pipe"
    system("mkfifo #{pipe_name} 2>/dev/null")

    # Skip test if the named pipe wasn't created; probably because system doesn't support it
    unless File.exist?(pipe_name)
      skip "Warning: Skipping skip on non-regular files test since mkfifo couldn't create a file"
    end

    # Run the script
    output = @runner.run(pipe_name, stderr: 1).output

    # Verify pipe is skipped
    assert_match(_r("Warning: Skipping non-regular file \"#{_p(pipe_name)}\"."), output,
                 "Should warn about skipping non-regular file")
    assert_file_exist(pipe_name, "Non-regular file should remain unchanged")
  end

  # Test recursive mode with mixed content (files, directories, symlinks)
  def test_recursive_mode
    # Create nested structure with mixed content
    create_common_nested_structure

    # Run the script with -r, -d, and -v to rename directories and log verbosely
    output = @runner.run("-r", "-d", "-v", "ParentDir", stderr: 1).output
    File.binwrite(File.join(ENV['TMPDIR'], "test_recursive_mode.log"), output)

    # Verify verbose output
    assert_match(_r("File is already in its proper form: #{_p('ParentDir/already-hyphenated.txt')}"),
                 output, "Verbose should indicate unchanged file")
    assert_match(_r("[FILE] #{_p('ParentDir/NeedsRenaming.txt')} -> needs-renaming.txt"),
                 output, "Verbose should show file renaming")
    assert_match(_r("[FILE] #{_p('ParentDir/SomeFile.ts')} -> some-file.ts"),
                 output, "Verbose should show file renaming for TypeScript file")
    assert_match(_r("[FILE] #{_p('ParentDir/SubDir/NestedFile.ts')} -> nested-file.ts"),
                 output, "Verbose should show nested file renaming")
    assert_match(_r("Warning: Skipping symbolic link \"#{_p('ParentDir/SymLink')}\"."),
                 output, "Should warn about skipping symbolic link")
    assert_match(_r("[DIR] #{_p('ParentDir/SubDir')} -> sub-dir"),
                 output, "Verbose should show subdirectory renaming")
    assert_match(_r("[DIR] #{_p('ParentDir')} -> parent-dir"),
                 output, "Verbose should show parent directory renaming")

    # Verify renaming and skipping
    assert_file_not_exist("ParentDir", "Original parent directory should not exist")
    assert_file_exist("parent-dir", "Renamed parent directory should exist")
    assert_file_exist("parent-dir/already-hyphenated.txt", "Already hyphenated file should remain")
    assert_file_exist("parent-dir/needs-renaming.txt", "Renamed file should exist")
    assert_file_not_exist("parent-dir/SomeFile.ts", "Original TypeScript file should not exist")
    assert_file_exist("parent-dir/some-file.ts", "Renamed TypeScript file should exist")
    assert_file_not_exist("parent-dir/SubDir", "Original subdirectory should not exist")
    assert_file_exist("parent-dir/sub-dir", "Renamed subdirectory should exist")
    assert_file_not_exist("parent-dir/sub-dir/NestedFile.ts", "Original nested file should not exist")
    assert_file_exist("parent-dir/sub-dir/nested-file.ts", "Renamed nested file should exist")
    assert_true(File.symlink?("parent-dir/SymLink"), "Symbolic link should remain unchanged")
  end

  # Test recursive mode without directory renaming
  def test_recursive_mode_without_directory_rename
    # Create nested structure
    create_common_nested_structure

    # Run the script with -r but not -d
    @runner.run("-r", "ParentDir", stdout: "/dev/null")

    # Verify files renamed, directories unchanged
    assert_file_exist("ParentDir", "Parent directory should not be renamed")
    assert_file_exist("ParentDir/already-hyphenated.txt", "Already hyphenated file should remain")
    assert_file_not_exist("ParentDir/NeedsRenaming.txt", "Original file should not exist")
    assert_file_exist("ParentDir/needs-renaming.txt", "Renamed file should exist")
    assert_file_not_exist("ParentDir/SomeFile.ts", "Original TypeScript file should not exist")
    assert_file_exist("ParentDir/some-file.ts", "Renamed TypeScript file should exist")
    assert_file_exist("ParentDir/SubDir", "Subdirectory should not be renamed")
    assert_file_not_exist("ParentDir/SubDir/NestedFile.ts", "Original nested file should not exist")
    assert_file_exist("ParentDir/SubDir/nested-file.ts", "Renamed nested file should exist")
    assert_true(File.symlink?("ParentDir/SymLink"), "Symbolic link should remain unchanged")
  end

  # Test renaming current directory fails
  def test_rename_current_directory
    # Create a directory and switch to it
    Dir.mkdir("CurrentDir")
    Dir.chdir("CurrentDir")

    # Create a file inside
    File.write("SomeFile.txt", "test content")

    # Run the script with -d to rename the parent directory
    status = @runner.run_quietly("-d", "..").status

    # Verify failure
    assert_false(status.success?, "Script should fail when renaming current directory")
    assert_file_exist("../CurrentDir", "Current directory should remain unchanged")
  end

  # Test renaming a file and directory
  def test_rename_file_and_directory
    # Create test file and directory
    File.write("someFileInCamelCaseForm.ts", "test content")
    Dir.mkdir("someDirInCamelCaseForm")

    # Run the script with -d to rename directories
    @runner.run("-d", "someFileInCamelCaseForm.ts", "someDirInCamelCaseForm", stdout: "/dev/null")

    # Verify renaming
    assert_file_not_exist("someFileInCamelCaseForm.ts", "Original file should not exist")
    assert_file_exist("some-file-in-camel-case-form.ts", "Renamed file should exist")
    assert_file_not_exist("someDirInCamelCaseForm", "Original directory should not exist")
    assert_file_exist("some-dir-in-camel-case-form", "Renamed directory should exist")
  end

  # Test renaming a file only (without -d)
  def test_rename_file_only
    # Create test file and directory
    File.write("someFileInCamelCaseForm.ts", "test content")
    Dir.mkdir("someDirInCamelCaseForm")

    # Run the script without -d (directories should be ignored)
    @runner.run_quietly("someFileInCamelCaseForm.ts", "someDirInCamelCaseForm")

    # Verify file renaming, directory unchanged
    assert_file_not_exist("someFileInCamelCaseForm.ts", "Original file should not exist")
    assert_file_exist("some-file-in-camel-case-form.ts", "Renamed file should exist")
    assert_file_exist("someDirInCamelCaseForm", "Directory should not be renamed without -d")
    assert_file_not_exist("some-dir-in-camel-case-form", "Renamed directory should not exist")
  end

  # Test restricted paths
  def test_restricted_path
    # Run the script with a fake restricted path (assuming it resolves to /dev)
    status = @runner.run_quietly("/dev/null").status

    # Verify failure
    assert_false(status.success?, "Script should refuse to process restricted path")
  end

  # Test the internal sanity tests of the script
  def test_sanity_tests_option
    # Run the script
    result = @runner.run("-t", stderr: 1)

    # Verify that the tests failed
    assert(result.output =~ /Passed:/ && result.output !~ /Failed:/,
           "Sanity tests should run and pass with no failure")
    assert_true(result.status.success?, "Sanity tests should exit with status 0")
  end

  # Test files with special characters
  def test_special_characters
    # Create files with special characters
    File.write("File with Spaces.txt", "test content")
    File.write("日本語FileΔ123.txt", "test content")

    # Run the script
    @runner.run("File with Spaces.txt", "日本語FileΔ123.txt", stdout: "/dev/null")

    # Verify renaming
    assert_file_not_exist("File with Spaces.txt", "Original file with spaces should not exist")
    assert_file_exist("file-with-spaces.txt", "Renamed file with spaces should exist")
    assert_file_not_exist("日本語FileΔ123.txt", "Original Unicode file should not exist")
    assert_file_exist("日本語-file-δ123.txt", "Renamed Unicode file should exist")
  end

  # Test symbolic link
  def test_symbolic_link_skipped
    # Create a file and a symbolic link
    File.write("OriginalFile.txt", "test content")
    File.symlink("OriginalFile.txt", "SymLinkToFile")

    # Run the script
    output = @runner.run("SymLinkToFile", "OriginalFile.txt", stderr: 1).output

    # Verify symbolic link is skipped, file is renamed
    assert_match(_r("Warning: Skipping symbolic link \"#{_p('SymLinkToFile')}\"."),
                 output, "Should warn about skipping symbolic link")
    assert_true(File.symlink?("SymLinkToFile"), "Symbolic link should remain unchanged")
    assert_file_not_exist("OriginalFile.txt", "Original file should not exist")
    assert_file_exist("original-file.txt", "Renamed file should exist")
  end

  # Test verbose mode
  def test_verbose_mode
    # Create files
    File.write("already-hyphenated.txt", "test content")
    File.write("NeedsRenaming.txt", "test content")

    # Run the script with -v
    output = @runner.run("-v", "already-hyphenated.txt", "NeedsRenaming.txt", stderr: 1).output

    # Verify verbose output
    assert_match(_r("File is already in its proper form: #{_p('already-hyphenated.txt')}"), output,
                 "Verbose should indicate unchanged file")
    assert_match(_r("[FILE] #{_p('NeedsRenaming.txt')} -> needs-renaming.txt"), output,
                 "Verbose should show renaming action")
    assert_file_exist("needs-renaming.txt", "File should be renamed")
  end

  # Test verbose mode in recursive scenarios
  def test_verbose_mode_recursive
    # Setup test files
    create_file_structure({
      "TestDir" => {
        "already-hyphenated.txt" => "test content",
        "another-hyphenated-file.txt" => "test content"
      }
    })

    # Run the script with -r and -v
    output = @runner.run("-r", "-v", "TestDir", stderr: 1).output

    # Verify verbose output
    assert_match(_r("File is already in its proper form: #{_p('TestDir/already-hyphenated.txt')}"),
                 output, "Verbose should indicate first unchanged file")
    assert_match(_r("File is already in its proper form: #{_p('TestDir/another-hyphenated-file.txt')}"),
                 output, "Verbose should indicate second unchanged file")
    assert_no_match(/\[FILE\]/, output, "Verbose should not show any renaming actions")
    assert_file_exist("TestDir/already-hyphenated.txt", "First file should remain unchanged")
    assert_file_exist("TestDir/another-hyphenated-file.txt", "Second file should remain unchanged")
  end

  # Test version output
  def test_version_output
    # Run the script with -V
    output = @runner.run("-V", stderr: 1).output

    # Version must be in valid form
    assert_match(/\d\d\d\d\.\d\d\.\d\d/, output, "Version output be a valid version")
  end
end
