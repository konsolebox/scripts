#!/usr/bin/env ruby

# git-diff-blame
#
# Annotates each line in a diff hunk with author and commit information
# like blame
#
# Usage: git-diff-blame[.rb] [commit [commit]] [options] [-- [path ...]]
#
# Based on <https://github.com/dmnd/git-diff-blame>
#
# This is free and unencumbered software released into the public
# domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain.  We make this dedication for the
# benefit of the public at large and to the detriment of our heirs and
# successors.  We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org>.

require 'open3'
require 'optparse'
require 'ostruct'

VERSION = "2024.11.16"

@options = OpenStruct.new(
  :color => :auto
)

def parse_hunk_header(line)
  match = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
  o_ofs, o_cnt, n_ofs, n_cnt = match.captures.map(&:to_i)
  o_cnt ||= 1
  n_cnt ||= 1
  return o_ofs, o_cnt, n_ofs, n_cnt
end

def get_blame_prefix(line)
  match = line.match(/^(\^?[0-9a-f]+\s+(\S+\s+)?\([^\)]+\))/)
  raise "Bad blame output: #{line}" unless match
  match[1].chomp
end

def puts_colored(msg, color_code)
  @color_enabled ||= (@options.color == :always || @options.color == :auto && $stdout.tty?)
  msg = "\e[#{color_code}m#{msg}\e[0m" if color_code && @color_enabled
  puts msg
end

def capture_command(*cmd, &blk)
  out, err, status = Open3.capture3(*cmd)

  if block_given?
    return yield out, err, status
  else
    unless err.nil? || err.empty? || status.success?
      err ||= "Command failed with exit status code #{status.code}: #{cmd}"
      raise err
    end

    out
  end
end

def check_commit(commit)
  raise "Invalid commit: #{commit}" unless
      commit.is_a?(String) && !commit.start_with?("-") &&
      capture_command("git", "rev-parse", "--verify", "-q", commit) do |out, err, status|
        status.success? && !out.empty?
      end
end

def get_blame_lines(commit, file, start, length)
  if length.zero? || file == "/dev/null"
    []
  else
    @blame_data ||= {}

    lines = @blame_data["#{commit}|#{file}"] ||= begin
      capture_command("git", "blame", "-M", *(commit ? [commit] : []), "--", file)
          .lines.map(&:chomp)
    end

    raise "Starting index must begin with 1: #{start}" unless start >= 1
    lines.slice(start - 1, length)
  end
end

def take_line(array, array_name)
  raise "#{array_name} is nil." if array_name.nil?
  array.shift or raise "#{array_name} is empty."
end

def capitalize_first_word(str)
  str.split(" ").tap{ |a| a.first.capitalize! }.join(" ")
end

def main
  color_mode = :auto
  file_args = []

  OptionParser.new do |parser|
    parser.on("--color [WHEN]") do |w|

      unless w.nil?
        raise "Not a valid option argument for --color: #{w.to_s}" unless
            ["always", "auto", "never"].include? w
      end

      @options.color = (w || :auto).to_sym
    end

    parser.on("-h", "--help") do
      $stderr.puts "git-diff-blame #{VERSION}"
      $stderr.puts
      $stderr.puts "Annotates each line in a diff hunk with author and commit information like blame"
      $stderr.puts "while avoiding conflict on files with different content"
      $stderr.puts
      $stderr.puts "Usage: git-diff-blame[.rb] [commit [commit]] [options] [-- [path ...]]"
      $stderr.puts
      $stderr.puts "Options:"
      $stderr.puts "      --color[=WHEN]  Show color in output.  WHEN can be 'always', 'never' or"
      $stderr.puts "                      'auto', which is the default."
      $stderr.puts "  -h, --help          Show this help info"
      $stderr.puts "  -V, --version       Show version"
      $stderr.puts
      $stderr.puts "This software is released into the public domain and comes with no warranty."
      $stderr.puts "Please refer to <https://unlicense.org/> for more information."
      exit 2
    end

    parser.on("-V", "--version") do
      puts VERSION
      exit 2
    end

    parser.on("--") do
      file_args = ARGV.dup
      ARGV.clear
      parser.terminate
    end
  end.parse!

  commit_args = ARGV.dup
  raise "Unsupported number of commit arguments" unless commit_args.size <= 2

  git_root = capture_command("git", "rev-parse", "--show-toplevel").chomp
  Dir.chdir(git_root) or raise $!

  oldrev, newrev = commit_args
  oldrev ||= "HEAD"
  check_commit(oldrev)
  check_commit(newrev) if newrev
  newrev_a = newrev ? [newrev] : []
  diff = capture_command("git", "--no-pager", "diff", oldrev, *newrev_a, "--", *file_args)

  pre = post = nil
  prefilename = postfilename = nil
  create = delete = false

  diff.each_line do |line|
    line.chomp!

    case line
    when /^diff --git .\/(.*) .\/\1$/
      pre = post = nil
      puts line
      prefilename = "./#{Regexp.last_match(1)}"
      postfilename = "./#{Regexp.last_match(1)}"
      delete = create = false
    when /^new file/
      create = true
      prefilename = "/dev/null"
    when /^deleted file/
      delete = true
      postfilename = "/dev/null"
    when /^--- #{prefilename}$/
      puts line
    when /^\+\+\+ #{postfilename}$/
      puts line
    when /^@@ /
      o_ofs, o_cnt, n_ofs, n_cnt = parse_hunk_header(line)
      pre = get_blame_lines(oldrev, prefilename, o_ofs, o_cnt)
      post = get_blame_lines(newrev, postfilename, n_ofs, n_cnt)
    when /^ /
      puts "    #{get_blame_prefix(take_line(pre, "pre"))}\t#{line}"
      take_line(post, "post") # Discard.
    when /^\-/
      puts_colored("  - #{get_blame_prefix(take_line(pre, "pre"))}\t#{line}", 31)
    when /^\+/
      puts_colored("  + #{get_blame_prefix(take_line(post, "post"))}\t#{line}", 32)
    end
  end
rescue SystemExit
  raise
rescue Interrupt
  $stderr.puts
  $stderr.puts "SIGINT caught."
  exit 1
rescue Exception => ex
  $stderr.puts capitalize_first_word(ex.message)
  exit 1
end

main
