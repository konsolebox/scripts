#!/usr/bin/env ruby

# ----------------------------------------------------------------------

# hyphenate
#
# Renames files and directories to the hyphenated version of their
# filename
#
# Usage: hyphenate[.rb] [options] [--] files|dirs
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
require 'optparse'
require 'ostruct'
require 'pathname'

VERSION = "2025.04.28"

@options = OpenStruct.new(
  :dry_run            => false,
  :rename_directories => false,
  :recursive          => false,
  :sanity_tests_only  => false,
  :verbose            => false
)

@dependencies_map = {}
@processed_map    = {}
@results_map      = {}
@targets_map      = {}

def log_message(msg = "")
  puts msg
end

def log_warning(msg = "")
  puts "Warning: #{msg}"
end

def log_error(msg = "", prefix = "Error: ")
  puts "#{prefix}#{msg}"
end

def log_verbose(msg = "")
  puts msg if @options.verbose
end

# Module GetHyphenatedForm provides a method to convert strings (e.g., function names, filenames)
# into hyphenated form, supporting Unicode letters, numbers, and namespaced inputs.
# Example: GetHyphenatedForm.get_hyphenated_form("getTagUUID1234") => "get-tag-uuid1234"
#
# Conversion strategy:
# - Kanji numbers are handled as non-numeric characters
# - Numbers attach to uppercase-led segments (e.g., getTagUUID1234UXY234 → get-tag-uuid1234uxy234)
#   and form new segments otherwise (e.g., getUuid1234extra → get-uuid-1234extra,
#   日本語123Data → 日本語-123-data).
# - Lowercase letters attach to numbers (1234extra) and Kanji (日本語days) when the numbers don't
#   attach to uppercase or titlecase letters
# - The last letter in a sequence of uppercase letters may form its own segment if it's followed
#   a sequence of lowercase letters (e.g. fetchHTTPRequest → fetch-http-request).
# - Special characters, modifier characters, and other non-alphanumeric characters are
#   discarded, acting as separators in the form of hyphens (e.g., ʾmodi’fierʰCharʼactersDiscarded →
#   modi-fier-char-acters-discarded).
# - The conversion function uses a universal pattern (\p{N}) to match numbers and doesn't treat
#   script-specific numbers (e.g., Greek numerals) differently to maintain simplicity.  As a result,
#   numbers may attach to preceding uppercase letters in mixed-script inputs (e.g., 日本語Δ123Data
#   converts to 日本語-δ123-data, not 日本語-δ-123-data).
module GetHyphenatedForm
  class ArgumentNotAStringError < ArgumentError
    def initialize
      super("Argument must be a string")
    end
  end

  class CantHyphenatedComponentError < ArgumentError
    def initialize(component, basename)
      super("Cannot hyphenate component '#{component}' in '#{basename}' to a valid string")
    end
  end

  MATCHER = Regexp.compile([
    '[\p{N}\p{Lu}]*[\p{Lu}\p{Lt}]',             # Matches 00ZXY4321A, ZXYA, 4321A, 3421YXǅ, A or ǅ
    '\p{Ll}*\p{N}+',                            # Matches txet4321 or simply 4321
    '\p{Ll}+(?:\p{Lu}|\p{Lt}|\p{Lo}+\p{Lt}?)?', # Matches meǅ, meG or 日本語days
    '\p{Lo}+\p{Lt}?',                           # Matches 汉ǅ, 汉汉, or just 汉
  ].join('|')).freeze

  def self.get_hyphenated_form(basename)
    raise ArgumentNotAStringError unless basename.is_a?(String)
    return "" if basename.empty?

    basename.split('.', -1).map do |component|
      next "" if component.empty?
      segments = component.reverse.scan(MATCHER)
      raise CantHyphenatedComponentError.new(component, basename) if segments.empty?
      segments.join('-').reverse
    end.join('.').downcase
  end

  module Test
    TEST_SAMPLES = {
      "1" => "1",
      "123OnlyNumbers" => "123-only-numbers",
      "ABC123Def456" => "abc123-def-456",
      "A" => "a",
      "NoValidLetters123!" => "no-valid-letters-123",
      "UPPERCASE123" => "uppercase123",
      "VeryLongInputWithMultipleSegments123AndUnicodeΔ日本語" => "very-long-input-with-multiple-segments-123-and-unicode-δ-日本語",
      "a" => "a",
      "calcΠrofit123" => "calc-πrofit-123",
      "calcΠrofit٠١٢" => "calc-πrofit-٠١٢",
      "camelCase123" => "camel-case-123",
      "fetch123ØreData" => "fetch-123-øre-data",
      "fetchHTTP2Request" => "fetch-http2-request",
      "fetchHTTP١٢Request" => "fetch-http١٢-request",
      "fetchØre½Data" => "fetch-øre-½-data",
      "fetchΔeltaΣigma123" => "fetch-δelta-σigma-123",
      "fetchШифр123Code" => "fetch-шифр-123-code",
      "fetch一二三Tag" => "fetch-一二三-tag",
      "get1234xyzTag1234UUID" => "get-1234xyz-tag-1234-uuid",
      "getSomeUUIDString" => "get-some-uuid-string",
      "getTagName123ABC" => "get-tag-name-123-abc",
      "getTagName" => "get-tag-name",
      "getTagUUID1234UXY234" => "get-tag-uuid1234uxy234",
      "getTagUUID1234UXY" => "get-tag-uuid1234uxy",
      "getTagUUID1234" => "get-tag-uuid1234",
      "getTagÑame" => "get-tag-ñame",
      "getTag١٢٣" => "get-tag-١٢٣",
      "getTag一١Ⅲ" => "get-tag-一-١ⅲ",
      "getUuid1234Extra" => "get-uuid-1234-extra",
      "getUuid1234extra" => "get-uuid-1234extra",
      "getÄpfel123Count" => "get-äpfel-123-count",
      "getÄpfelⅣCount" => "get-äpfel-ⅳ-count",
      "getÄÖÜ123String" => "get-äöü123-string",
      "getČeský123Tag" => "get-český-123-tag",
      "getČeský一Tag" => "get-český-一-tag",
      "getŁódź123City" => "get-łódź-123-city",
      "getŁódź万ⅡCity" => "get-łódź-万-ⅱ-city",
      "module!!!..test" => "module..test",
      "module.functionName" => "module.function-name",
      "module.parseÜbung" => "module.parse-übung",
      "module.parse十١Function" => "module.parse-十-١-function",
      "module." => "module.",
      "module....test" => "module....test",
      "parseUUIDⅢData" => "parse-uuidⅲ-data",
      "parseXMLData" => "parse-xml-data",
      "parseÉtéData" => "parse-été-data",
      "parseΚατάσταση456" => "parse-κατάσταση-456",
      "parse日本語十百٠Data" => "parse-日本語十百-٠-data",
      "saveDoc123日本語456" => "save-doc-123-日本語-456",
      "saveDocⅤ日本語" => "save-doc-ⅴ-日本語",
      "saveДок123File" => "save-док-123-file",
      "save٠١٢Ⅲ一" => "save-٠١٢ⅲ-一",
      "save日本語Doc123" => "save-日本語-doc-123",
      "save日本語١File" => "save-日本語-١-file",
      "single" => "single",
      "snake_case_to_camelCase" => "snake-case-to-camel-case",
      "!spaces and$other@characters:convert|to*dashes" => "spaces-and-other-characters-convert-to-dashes",
      "!!!get!!!Tag!!!123!!!" => "get-tag-123",
      "" => "",
      "__underscore__Test" => "underscore-test",
      "ǅtitleCase123" => "ǆtitle-case-123",
      "ǅ" => "ǆ",
      "ǅǄtitleCase123" => "ǆ-ǆtitle-case-123",
      "ʾmodi’fierʰCharʼactersDiscarded" => "modi-fier-char-acters-discarded",
      "日" => "日",
      "日本語123Data" => "日本語-123-data",
      "日本語Only" => "日本語-only",
      "日本語days1234" => "日本語days-1234",
      "日本語daysExtra123" => "日本語days-extra-123",
      "日本語ʾΔ123Data" => "日本語-δ123-data",
      "日本語Δ123Data" => "日本語-δ123-data"
    }.freeze

    PERFORMANCE_TEST_SAMPLES = [
      {
        input: ("Segment" * 100) + "123" + "日本語",
        expected: ("segment-" * 99) + "segment-123-日本語",
        passed_message: "Long input converts to proper hyphenate form",
        failed_message: "Long input failed to convert to proper hyphenate form"
      }
    ].freeze

    RAISE_TEST_SAMPLES = {
      :symbol => ArgumentNotAStringError,
      "!!!" => CantHyphenatedComponentError,
      "module.!!!.test" => CantHyphenatedComponentError
    }.freeze

    def self.test(always_show_results)
      test_results = TEST_SAMPLES.merge.map do |input, expected|
        got = GetHyphenatedForm.get_hyphenated_form(input)
        { input: input, expected: expected, got: got, result: expected == got ? :pass : :fail }
      end

      performance_test_results = PERFORMANCE_TEST_SAMPLES.map do |sample|
        got = GetHyphenatedForm.get_hyphenated_form(sample[:input])
        { got: got, result: sample[:expected] == got ? :pass : :fail }.merge(sample)
      end

      raise_test_results = RAISE_TEST_SAMPLES.map do |input, error_class|
        raised = false

        begin
          GetHyphenatedForm.get_hyphenated_form(input)
        rescue Exception => e
          raised = e.is_a?(error_class)
        end

        { input: input, error_class: error_class, raised: raised }
      end

      failed = test_results.any?{ |result| result[:result] == :fail } ||
               raise_test_results.any?{ |result| result[:raised] == false }

      if failed || always_show_results
        (test_results + performance_test_results).each do |result|
          input, expected, got, passed_message, failed_message = result.values_at(:input, :expected,
              :got, :passed_message, :failed_message)

          if result[:result] == :fail
            prefix = failed_message ? "Failed: #{failed_message}: " : "Failed: "
            log_error "\"#{input}\" converts to \"#{got}\" instead of \"#{expected}\"", prefix
          else
            passed_message ||= "\"#{input}\" converts to \"#{expected}\""
            log_message "Passed: #{passed_message}"
          end
        end

        raise_test_results.each do |result|
          input, error_class, raised = result.values_at(:input, :error_class, :raised)

          if raised
            log_message "Passed: \"#{input}\" raises #{error_class.name} as expected"
          else
            log_error "\"#{input}\" doesn't raise #{error_class.name} as expected", "Failed: "
          end
        end

        if failed
          log_error "", ""
          log_error "Some tests on the converion function failed.", ""
        end
      end

      return !failed
    end
  end
end

def get_hyphenated_form_full(path)
  dirname, basename = File.split(path)
  File.join(dirname, GetHyphenatedForm.get_hyphenated_form(basename))
end

def check_naming_conflict(path, hyphenated_form)
  if File.exist?(hyphenated_form)
    raise "Another file or directory already owns the hyphenated form of \"#{path}\": #{hyphenated_form}"
  end
end

def rename_file_or_dir(source, dest, is_source_dir)
  dest_base = File.basename(dest)

  if File.exist?(dest)
    raise "Destination file should no longer exist at this point: #{dest}"
  end

  log_message "[#{is_source_dir ? "DIR" : "FILE"}] #{source} -> #{dest_base}"

  unless @options.dry_run
    begin
      FileUtils.move(source, dest)
    rescue SystemCallError => ex
      raise "Failed to rename #{is_source_dir ? "file" : "directory"} \"#{source}\" to \"#{dest_base}\": #{ex.message}"
    end
  end

  @results_map.delete(source)
  @results_map[dest] = true
end

def process_dir(dir)
  log_verbose "Processing directory \"#{dir}\"."
  @processed_map[dir] = true

  if !@options.recursive && !@options.rename_directories
    log_warning "Nothing to do with directory: #{dir}";
    @results_map[dir] = true
    return
  end

  if @options.recursive
    entries = Dir.entries(dir).reject{ |e| e === "." || e === ".." }.map{ |e| dir + "/" + e }
    process entries
  end

  if @options.rename_directories
    base = File.basename(dir)

    unless @options.recursive
      deps = @dependencies_map[dir]

      if deps
        log_verbose "Processing dependencies of \"#{dir}\"."
        process deps
      end
    end

    hyphenated_form = get_hyphenated_form_full(dir)

    if dir == hyphenated_form
      log_verbose "Directory is already in its hyphenated form: #{dir}"
      @results_map[dir] = true
      return
    end

    check_naming_conflict(dir, hyphenated_form)
    rename_file_or_dir(dir, hyphenated_form, true)
  end
end

def process_file(file)
  log_verbose "Processing file \"#{file}\"."
  @processed_map[file] = true
  hyphenated_form = get_hyphenated_form_full(file)

  if file == hyphenated_form
    log_verbose "File is already in its proper form: #{file}"
    @results_map[file] = true
    return
  end

  check_naming_conflict(file, hyphenated_form)
  rename_file_or_dir(file, hyphenated_form, false)
end

def process(targets)
  targets.each do |t|
    if @processed_map.has_key?(t)
      log_verbose "Skipping on-process or recently processed file or directory \"#{File.expand_path(t)}\"."
    elsif @results_map.has_key?(t)
      log_verbose "Skipping result file or directory \"#{File.expand_path(t)}\"."
    elsif File.symlink?(t)
      log_warning "Skipping symbolic link \"#{File.expand_path(t)}\"."
      @results_map[t] = true
    elsif File.directory?(t)
      process_dir(t)
    elsif File.file?(t)
      process_file(t)
    elsif File.exist?(t)
      log_warning "Skipping non-regular file \"#{File.expand_path(t)}\"."
      @results_map[t] = true
    else
      raise "File or directory \"#{File.expand_path(t)}\" was lost during process."
    end
  end
end

def get_real_path(path)
  Pathname.new(path).realpath.to_s
rescue
  nil
end

def each_parent(path, &blk)
  Pathname.new(File.expand_path(path)).ascend.lazy.map(&:to_s).each(&blk)
end

def setup_dependencies_map(targets)
  no_parents_from_here = {}

  targets.each do |target|
    first_parent = nil
    parent_found = false

    each_parent(target) do |parent|
      first_parent ||= parent

      if no_parents_from_here.has_key?(parent)
        break
      elsif @targets_map.has_key?(parent)
        (@dependencies_map[parent] ||= []) << target
        parent_found = true
        break
      end
    end

    no_parents_from_here[first_parent] = true unless parent_found
  end
end

def main
  OptionParser.new do |parser|
    parser.on("-d", "--rename-directories", "Rename directories as well") do
      @options.rename_directories = true
    end

    parser.on("-h", "--help", "Show this help info") do
      $stderr.puts "hyphenate #{VERSION}"
      $stderr.puts
      $stderr.puts "Renames files and directories to the hyphenated version of their filename"
      $stderr.puts
      $stderr.puts "Usage: hyphenate [options] [--] files|dirs"
      $stderr.puts
      $stderr.puts "Options:"
      $stderr.puts begin
        parser.set_summary_indent("  ")
        parser.summarize.tap(&:pop).map{ |e| e.sub(/    ([[:alpha:]])/, '  \1') }
      end
      $stderr.puts
      $stderr.puts "Important Notes:"
      $stderr.puts "  - Symbolic links and non-regular files are always skipped."
      $stderr.puts "  - This tool does not check the filesystem's maximum filename size."
      $stderr.puts "  - This tool refuses to process /dev, /proc, /run, and /sys."
      $stderr.puts
      $stderr.puts "This tool comes with no warranty and using it means you accept the conditions"
      $stderr.puts "described in the MIT license.  Please read the tool's source code or see"
      $stderr.puts "https://mit-license.org/ for details."
      exit 2
    end

    parser.on("-n", "--dry-run", "Do not rename anything") do
      @options.dry_run = true
    end

    parser.on("-r", "--recursive", "Rename files within directories recursively") do
      @options.recursive = true
    end

    parser.on("-t", "--sanity-tests-only", "Run sanity tests only") do
      @options.sanity_tests_only = true
    end

    parser.on("-v", "--verbose", "Verbose mode") do
      @options.verbose = true
    end

    parser.on("-V", "--version", "Show version") do
      puts VERSION
      exit 2
    end

    parser.on("--") do
      parser.terminate
    end
  end.parse!

  GetHyphenatedForm::Test.test(@options.sanity_tests_only) or exit 1
  exit 0 if @options.sanity_tests_only
  pwd_r = get_real_path(Dir.pwd) or raise "Unable to get real path of current directory."

  targets = ARGV.map do |t|
    if File.symlink?(t)
      log_warning "Skipping symbolic link \"#{File.expand_path(t)}\"."
      next nil
    end

    is_dir = File.directory?(t)

    if is_dir && !@options.rename_directories && !@options.recursive
      log_warning "Ignoring directory \"#{t}\"."
      next nil
    end

    r = get_real_path(t) or raise "Unable to get real path of \"#{t}\"."

    case r
    when "/", "/dev", "/proc", "/run", "/sys"
      raise "Refusing to process \"#{r}\"#{r == t ? "" : " (\"#{t}\")"}."
    when /^\/(dev|proc|run|sys)\//
      raise "Refusing to process files in /dev, /proc, /run or /sys: #{r}#{r == t ? "" : " (#{t})"}"
    end

    if is_dir && @options.rename_directories &&
        (pwd_r == r || pwd_r.start_with?(r + File::SEPARATOR))
      raise "We can't rename a directory while we're in it."
    end

    @targets_map[r] = true
    r
  end.compact

  raise "No targets to process." if targets.empty?
  setup_dependencies_map(targets) if @options.rename_directories && !@options.recursive
  log_message "Running in dry-run mode." if @options.dry_run
  process targets
rescue SystemExit
  raise
rescue Interrupt
  log_message
  log_error "SIGINT caught."
  exit 1
rescue Exception => ex
  log_error ex.message.sub(/./, &:upcase)
  exit 1
end

main
