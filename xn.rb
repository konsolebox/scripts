#!/usr/bin/env ruby

# ----------------------------------------------------------------------

# xn
#
# Renames files and directories based on their 160-bit KangarooTwelve
# checksum while avoiding conflict on files with different content
#
# Usage: xn[.rb] [options] [--] files|dirs
#
# To use this tool, the gem 'digest-kangarootwelve' should also be
# installed.
#
# Copyright © 2024 konsolebox
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

require 'digest/kangarootwelve'
require 'fileutils'
require 'optparse'
require 'ostruct'
require 'pathname'

DEFAULT_BIT_SIZE = 160
MAX_BIT_SIZE     = 512
MAX_PREFIX_SIZE  = 100
VERSION          = "2024.07.13"

@options = OpenStruct.new(
  :bit_size             => DEFAULT_BIT_SIZE,
  :custom_string        => nil,
  :convert_to_lowercase => false,
  :one_extension        => false,
  :overwrite_diff_files => false,
  :overwrite_same_files => true,
  :prefix               => "",
  :process_directories  => false,
  :recursive            => false,
  :replace_directories  => false,
  :skip_processed_files => false,
  :verbose              => false
)

@cmd_bit_size     = DEFAULT_BIT_SIZE
@cmd_name         = "xn"
@dependencies_map = {}
@processed_map    = {}
@results_map      = {}
@targets_map      = {}

def log_message(msg = "")
  puts msg
end

def log_warning(msg)
  puts "Warning: #{msg}"
end

def log_error(msg)
  puts "Error: #{msg}"
end

def log_verbose(msg)
  puts msg if @options.verbose
end

def digest
  @digest ||= Digest::KangarooTwelve.implement(d: digest_size, c: @options.custom_string)
end

def digest_size
  @digest_size ||= @options.bit_size / 8
end

def digest_hex_size
  @digest_hex_size ||= digest_size * 2
end

def base_hashed_form?(form, prefix)
  @base_hashed_form_regex ||= Regexp.new("^#{Regexp.escape(prefix)}[0-9a-f]{#{digest_hex_size}}$")
  @base_hashed_form_regex =~ form
end

def base_congruent_form?(form, prefix)
  @base_congruent_form_regex ||= Regexp.new("^#{Regexp.escape(prefix)}[0-9a-f]" \
      "{#{digest_hex_size}}-[0-9a-f]{4,}$")
  @base_congruent_form_regex =~ form
end

def target?(path)
  if path && path.length > 0
    if @targets_map.has_key?(path)
      return true
    elsif @options.recursive
      dirname = File.dirname(path)

      if dirname.length < path.length && target?(dirname)
        @targets_map[path] = true
        return true
      end
    end
  end

  false
end

def rename_dir(source, dest)
  dest_base = File.basename(dest)

  if File.exist?(dest)
    log_message "[DIR] #{source} => #{dest_base}"

    begin
      FileUtils.rm_r(dest)
    rescue SystemCallError => ex
      raise "Failed to remove file or directory \"#{ex.message}\": #{ex.message}"
    end
  else
    log_message "[DIR] #{source} -> #{dest_base}"
  end

  begin
    FileUtils.move(source, dest)
  rescue SystemCallError => ex
    raise "Failed to rename directory \"#{source}\" to \"#{dest_base}\": #{ex.message}"
  end

  @results_map.delete(source)
  @results_map[dest] = true
end

def rename_dir_congruently(source, dest_prefix)
  for i in 0..Float::INFINITY do
    dest = sprintf("%s-%04x", dest_prefix, i)
    break unless File.exist?(dest)
  end

  dest_base = File.basename(dest)
  log_message "[DIR] #{source} -> #{dest_base}"

  begin
    FileUtils.move(source, dest)
  rescue SystemCallError => ex
    raise "Failed to rename directory \"#{source}\" to \"#{dest_base}\": #{ex.message}"
  end

  dest
end

def process_dir(dir)
  log_verbose "Processing directory \"#{dir}\"."
  @processed_map[dir] = true

  if !@options.recursive && !@options.process_directories
    log_warning "Nothing to do with directory: #{dir}";
    @results_map[dir] = true
    return
  end

  if @options.recursive
    entries = Dir.entries(dir).reject{ |e| e === "." || e === ".." }.map{ |e| dir + "/" + e }
    process entries
  end

  if @options.process_directories
    base = File.basename(dir)

    if @options.skip_processed_files && base_hashed_form?(base)
      log_verbose "Skipping processed directory \"#{dir}\"."
      @results_map[dir] = true
      return
    end

    unless @options.recursive
      deps = @dependencies_map[dir]

      if deps
        log_verbose "Processing dependencies of \"#{dir}\"."
        process deps
      end
    end

    begin
      seed = Dir.entries(dir).reject{ |e| e === '.' || e === '..' }.sort.map{ |e| e + "\n" }
          .join('')
      sum = digest.hexdigest(seed)
    rescue Interrupt
      raise
    rescue Exception => ex
      raise "Unable to generate KangarooTwelve form of directory \"#{dir}\": #{ex.message}"
    end

    proper_form = File.join(File.dirname(dir), @options.prefix + sum)

    if dir == proper_form
      log_verbose "Directory is already in its proper form: #{dir}"
      @results_map[dir] = true
      return
    end

    if !File.exist?(proper_form)
      rename_dir(dir, proper_form)
    elsif target?(proper_form) && !@results_map.has_key?(proper_form)
      if base_congruent_form?(base) &&
          base[(@options.prefix.length)..-1].gsub(/-.+$/, '') == sum
        log_verbose "Holding directory's form: #{dir}"
        @results_map[dir] = true
      else
        dir = rename_dir_congruently(dir, proper_form)
      end

      process [proper_form]

      if !File.exist?(proper_form) || @options.replace_directories && File.directory?(proper_form)
        rename_dir(dir, proper_form)
      end
    elsif @options.replace_directories && File.directory?(proper_form)
      rename_dir(dir, proper_form)
    else
      rename_dir_congruently(dir, proper_form)
    end
  end
end

def rename_file(source, dest)
  dest_base = File.basename(dest)

  if File.exist?(dest)
    log_message "[FILE] #{source} => #{dest_base}"

    begin
      FileUtils.rm_r(dest)
    rescue SystemCallError => ex
      raise "Failed to remove file or directory \"#{dest}\": #{ex.message}"
    end
  else
    log_message "[FILE] #{source} -> #{dest_base}"
  end

  begin
    FileUtils.move(source, dest)
  rescue SystemCallError => ex
    raise "Failed to rename file \"#{source}\" to \"#{dest_base}\": #{ex.message}"
  end

  @results_map.delete(source)
  @results_map[dest] = true
end

def rename_file_congruently(source, dest_prefix, dest_suffix)
  for i in 0..Float::INFINITY do
    dest = sprintf("%s-%04x%s", dest_prefix, i, dest_suffix)
    break unless File.exist?(dest)
  end

  dest_base = File.basename(dest)
  log_message "[FILE] #{source} -> #{dest_base}"

  begin
    FileUtils.move(source, dest)
  rescue SystemCallError => ex
    raise "Failed to rename file \"#{source}\" to \"#{dest_base}\": #{ex.message}"
  end

  dest
end

def get_filename_ext(path, one_extension)
  File.basename(path).gsub(/^[^.]+/, '').tap do |ext|
    until ext.empty? || !(ext =~ /[[:space:]]|[.][.]/ || one_extension && ext =~ /[.].+[.]/)
      ext.gsub!(/^[.][^.]*/, '')
    end
  end
end

def replace_with_file?(target, source)
  return false unless File.file?(target)
  log_verbose "Checking if \"#{source}\" and \"#{File.basename(target)}\" are the same."
  FileUtils.identical?(target, source) ? @options.overwrite_same_files :
      @options.overwrite_diff_files
end

def process_file(file)
  log_verbose "Processing file \"#{file}\"."
  @processed_map[file] = true
  base = File.basename(file)
  ext = get_filename_ext(base, @options.one_extension)
  ext_l = ext.downcase
  no_ext = base[0..-(ext.length + 1)]

  if @options.convert_to_lowercase && !(ext == ext_l)
    ext = ext_l
  elsif @options.skip_processed_files && base_hashed_form?(no_ext, @options.prefix)
    log_verbose "Skipping processed file \"#{file}\"."
    @results_map[file] = true
    return true
  end

  begin
    sum = digest.file(file).hexdigest
  rescue Interrupt
    raise
  rescue Exception => ex
    raise "Unable to generate KangarooTwelve form of file \"#{file}\": #{ex.message}"
  end

  proper_form_without_ext = File.join(File.dirname(file), @options.prefix + sum)
  proper_form = proper_form_without_ext + ext

  if file == proper_form
    log_verbose "File is already in its proper form: #{file}"
    @results_map[file] = true
    return true
  end

  if !File.exist?(proper_form)
    rename_file(file, proper_form)
  elsif target?(proper_form) && !@results_map.has_key?(proper_form)
    if base_congruent_form?(no_ext, @options.prefix) &&
        no_ext[(@options.prefix.length)..-1].gsub(/-.*$/, '') == sum
      log_verbose "Holding file's form: #{file}"
      @results_map[file] = true
    else
      file = rename_file_congruently(file, proper_form_without_ext, ext)
    end

    process [proper_form]

    if !File.exist?(proper_form) || replace_with_file?(proper_form, file)
      rename_file(file, proper_form)
    end
  elsif replace_with_file?(proper_form, file)
    rename_file(file, proper_form)
  else
    rename_file_congruently(file, proper_form_without_ext, ext)
  end
end

def process(targets)
  targets.each do |t|
    if @processed_map.has_key?(t)
      log_verbose "Skipping on-process or recently processed file or directory \"#{t}\"."
    elsif @results_map.has_key?(t)
      log_verbose "Skipping result file or directory \"#{t}\"."
    elsif File.symlink?(t)
      log_warning "Skipping symbolic link \"#{t}\"."
      @results_map[t] = true
    elsif File.directory?(t)
      process_dir(t)
    elsif File.file?(t)
      process_file(t)
    elsif File.exist?(t)
      log_warning "Skipping non-regular file \"#{t}\"."
      @results_map[t] = true
    else
      raise "File or directory \"#{t}\" was lost during process."
    end
  end
end

def get_real_path(path)
  Pathname.new(path).realpath.to_s
rescue
  nil
end

def parse_error(msg)
  $stderr.puts msg
  exit 2
end

def parse_bit_size(bit_size_str)
  bit_size = Integer(bit_size_str) rescue nil
  parse_error "Invalid bit size: #{bit_size_str}" \
      unless bit_size && bit_size > 1 && bit_size % 8 == 0
  parse_error "Bit size exceeds maximum size which is #{MAX_BIT_SIZE}." \
      if bit_size > MAX_BIT_SIZE
  bit_size
end

def main
  base = File.basename($0) rescue nil

  if base && base =~ /^xn[[:digit:]]+$/
    @options.bit_size = @cmd_bit_size = parse_bit_size(base[2..-1])
    @cmd_name = base
  end

  OptionParser.new do |parser|
    parser.on("-1", "--one-extension", "Only keep one filename extension") do
      @options.one_extension = true
    end

    parser.on("-B", "--bit-size=BIT_SIZE",
        "Produce filenames based on a different bit size") do |bit_size_str|
      @options.bit_size = parse_bit_size(bit_size_str)
    end

    parser.on("-c", "--custom=CUSTOM_STRING", "Use customization string") do |str|
      @options.custom_string = str
    end

    parser.on("-d", "--process-directories", "Process directories") do
      @options.process_directories = true
    end

    parser.on("-D", "--replace-directories", "Replace directories having the same sums") do
      @options.replace_directories = true
    end

    parser.on("-l", "--convert-to-lowercase", "Convert extensions to lowercase form") do
      @options.convert_to_lowercase = true
    end

    parser.on("-n", "--no-overwrite-same-files", "Don't overwrite files with the same content") do
      @options.overwrite_same_files = false
    end

    parser.on("-N", "--no-overwrite-diff-files", "Don't overwrite different files [DEFAULT]") do
      @options.overwrite_diff_files = false
    end

    parser.on("-o", "--overwrite-same-files", "Overwrite files with the same content [DEFAULT]") do
      @options.overwrite_same_files = true
    end

    parser.on("-O", "--overwrite-diff-files", "Overwrite different files") do
      @options.overwrite_diff_files = true
    end

    parser.on("-P", "--prefix=PREFIX", "Specify filename prefix") do |prefix|
      parse_error "Invalid prefix: #{prefix}" if prefix[File::SEPARATOR]
      parse_error "Prefix exceeds maximum size which is #{MAX_PREFIX_SIZE}." \
          if prefix.length > MAX_PREFIX_SIZE
      @options.prefix = prefix
    end

    parser.on("-r", "--recursive", "Process files within directories recursively") do
      @options.recursive = true
    end

    parser.on("-s", "--skip-processed-files", "Skip files that are already in processed form") do
      @options.skip_processed_files = true
    end

    parser.on("-v", "--verbose", "Verbose mode") do
      @options.verbose = true
    end

    parser.on("-V", "--version", "Show version") do
      puts VERSION
      exit 2
    end

    parser.on("-h", "--help", "Show this help info") do
      $stderr.puts "#{@cmd_name} #{VERSION}"
      $stderr.puts
      $stderr.puts "Renames files and directories based on their #{@cmd_bit_size}-bit " \
                   "KangarooTwelve checksum"
      $stderr.puts "while avoiding conflict on files with different content"
      $stderr.puts
      $stderr.puts "Usage: #{@cmd_name} [options] [--] files|dirs"
      $stderr.puts
      $stderr.puts "Options:"
      parser.set_summary_indent("  ")
      $stderr.puts parser.summarize.tap(&:pop).map{ |e| e.sub(/    ([[:alpha:]])/, '  \1') }
      $stderr.puts
      $stderr.puts "Important Notes:"
      $stderr.puts "  - Bit size can also be specified by appending it in the command's name."
      $stderr.puts "    This is generally done by creating a symbolic link."
      $stderr.puts "  - Bit size should be a multiple of 8 and not larger than #{MAX_BIT_SIZE}."
      $stderr.puts "  - Directories are summed based on their content filenames only."
      $stderr.puts "  - Directories having the same sums don't imply having the same content."
      $stderr.puts "  - Directories are ignored when neither '-d' nor '-r' is specified."
      $stderr.puts "  - Maximum prefix size is #{MAX_PREFIX_SIZE}."
      $stderr.puts "  - Symbolic links and non-regular files are always skipped."
      $stderr.puts "  - This tool does not check filesystem's maximum filename size."
      $stderr.puts "  - This tool refuses to process /dev, /proc, /run, and /sys."
      $stderr.puts
      $stderr.puts "This tool comes with no warranty and using it means you accept the conditions"
      $stderr.puts "described in the MIT license.  Please read the tool's source code or see"
      $stderr.puts "https://mit-license.org/ for details."
      exit 2
    end

    parser.on("--") do
      parser.terminate
    end
  end.parse!

  pwd_r = get_real_path(Dir.pwd) or raise "Unable to get real path of current directory."
  log_verbose "Using prefix '#{@options.prefix}'." if @options.prefix.length > 0

  targets = ARGV.map do |t|
    if File.symlink?(t)
      log_warning "Skipping symbolic link \"#{t}\"."
      next nil
    end

    is_dir = File.directory?(t)

    if is_dir && !@options.process_directories && !@options.recursive
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

    if is_dir && @options.process_directories &&
        (pwd_r == r || pwd_r.start_with?(r + File::SEPARATOR))
      raise "We can't process a directory while we're in it."
    end

    @targets_map[r] = true
    r
  end.compact

  raise "No targets to process." if targets.empty?

  if @options.process_directories && !@options.recursive
    targets.each do |t|
      parent = File.dirname(t)
      (@dependencies_map[parent] ||= []) << t if @targets_map.has_key?(parent)
    end
  end

  process targets
rescue SystemExit
  raise
rescue Interrupt
  log_message
  log_error "SIGINT caught."
  exit 1
rescue Exception => ex
  log_error ex.message.capitalize
  exit 1
end

main
