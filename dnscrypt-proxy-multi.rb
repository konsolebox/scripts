#!/usr/bin/env ruby

# ----------------------------------------------------------

# dnscrypt-proxy-multi
#
# Runs multiple instances of dnscrypt-proxy.
#
# It parses a CSV file and makes use of the entries found in
# it as target remote services when creating instances of
# dnscrypt-proxy.  Remote services are checked for
# availability before an instance of dnscrypt-proxy is used
# to connect to them.  An FQDN can also be used for to check
# if remote services can resolve names.
#
# The script waits for all instances to exit before it
# exits.  It also automaticaly stops them when it receives
# SIGTERM or SIGINT.
#
# Usage: dnscrypt-proxy-multi[.rb] [options]
#
# Run with --help to see readable info about the options.
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# April 30, 2016

# ----------------------------------------------------------

require 'csv'
require 'fileutils'
require 'optparse'
require 'resolv'
require 'socket'
require 'timeout'

VERSION = '2016-04-30'
INSTANCES_LIMIT = 50

@log_buffer = []
@log_file = nil
@pids = []
@exit_status = 1

@params = Struct.new(
  :change_owner, :debug, :dnscrypt_proxy, :ignore_ip_format,
  :local_ip_range, :local_port_range, :log, :log_dir, :log_file,
  :log_level, :log_overwrite, :max_instances, :port_check_async,
  :port_check_timeout, :resolvers_list, :resolvers_list_encoding,
  :resolver_check, :resolver_check_timeout, :resolver_check_wait,
  :user, :verbose, :wait_before_next, :write_pids, :write_pids_dir
).new

def initialize_params
  @params.change_owner = false
  @params.debug = false
  @params.dnscrypt_proxy = which('dnscrypt-proxy')
  @params.ignore_ip_format = false
  @params.local_ip_range = '127.0.100.1-254'
  @params.local_port_range = '53'
  @params.log = false
  @params.log_dir = '/var/log/dnscrypt-proxy-multi'
  @params.log_file = nil
  @params.log_level = 6
  @params.log_overwrite = false
  @params.max_instances = 10
  @params.port_check_async = 10
  @params.port_check_timeout = 5.0
  @params.resolvers_list = '/usr/share/dnscrypt-proxy/dnscrypt-resolvers.csv'
  @params.resolvers_list_encoding = 'utf-8'
  @params.resolver_check = nil
  @params.resolver_check_timeout = 5.0
  @params.resolver_check_wait = 0.1
  @params.user = nil
  @params.verbose = false
  @params.wait_before_next = 0.0
  @params.write_pids = false
  @params.write_pids_dir = '/var/run/dnscrypt-proxy-multi'
end

def log(msg, stderr = false)
  if @log_buffer
    @log_buffer << "[#{Time.now.strftime('%F %T')}] #{msg}"
  elsif @log_file
    @log_file.puts "[#{Time.now.strftime('%F %T')}] #{msg}"
    @log_file.flush
  end

  stderr ? $stderr.puts(msg) : puts(msg)
end

def log_message(msg)
  log msg
end

def log_warning(msg)
  log "[Warning] #{msg}"
end

def log_error(msg)
  log "[Error] #{msg}", true
end

def log_verbose(msg)
  log msg if @params.verbose
end

def log_debug
  log "[Debug] #{msg}" if @params.debug
end

def fail(msg)
  log "[Failure] #{msg}", true
  exit 1
end

def which(cmd)
  raise ArgumentError.new("Argument not a string: #{cmd.inspect}") unless cmd.is_a?(String)
  return nil if cmd.empty?

  case RbConfig::CONFIG['host_os']
  when /cygwin/
    exts = nil
  when /dos|mswin|^win|mingw|msys/
    pathext = ENV['PATHEXT']
    exts = pathext ? pathext.split(';').select{ |e| e[0] == '.' } : ['.com', '.exe', '.bat']
  else
    exts = nil
  end

  if cmd[File::SEPARATOR] or (File::ALT_SEPARATOR and cmd[File::ALT_SEPARATOR])
    if exts
      ext = File.extname(cmd)

      return File.absolute_path(cmd) \
          if not ext.empty? and exts.any?{ |e| e.casecmp(ext).zero? } \
          and File.file?(cmd) and File.executable?(cmd)

      exts.each do |ext|
        exe = "#{cmd}#{ext}"
        return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
      end
    else
      return File.absolute_path(cmd) if File.file?(cmd) and File.executable?(cmd)
    end
  else
    paths = ENV['PATH']
    paths = paths ? paths.split(File::PATH_SEPARATOR).select{ |e| File.directory?(e) } : []

    if exts
      ext = File.extname(cmd)
      has_valid_ext = !ext.empty? && exts.any?{ |e| e.casecmp(ext).zero? }

      paths.unshift('.').each do |path|
        if has_valid_ext
          exe = File.join(path, "#{cmd}")
          return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
        end

        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
        end
      end
    else
      paths.each do |path|
        exe = File.join(path, cmd)
        return File.absolute_path(exe) if File.file?(exe) and File.executable?(exe)
      end
    end
  end

  nil
end

def check_tcp_port(ip, port, seconds = 1)
  Timeout::timeout(seconds) do
    begin
      start = Time.now
      TCPSocket.new(ip, port).close
      Time.now - start
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      nil
    end
  end
rescue Timeout::Error
  nil
end

def executable_file?(path)
  File.file?(path) and File.executable_file?(path) and File.readable?(path)
end

def valid_fqdn?(name)
  return false if name =~ /\.\./ or name =~ /^\./
  labels = name.split('.')
  return false if labels.size < 2 or labels.detect{ |e| not e =~ /^[[:alnum:]-]+$/ }
  true
end

module RangeCommon
  def expand_simple_range(range, min, max)
    case range
    when /^[[:digit:]]+$/
      i = Integer(range)
      return nil if i < min or i > max
      [i]
    when /^[[:digit:]]+-[[:digit:]]+$/
      a, b = range.split('-').map{ |e| Integer(e) }
      return nil if a > b or a < min or b > max
      Range.new(a, b)
    else
      nil
    end
  end

  def each
    if block_given?
      enumerate do |e|
        yield e
      end
    else
      Enumerator.new do |y|
        enumerate do |e|
          y << e
        end
      end
    end
  end

  def to_s
    return @range_string || self
  end
end

class IPAddrRange
  include RangeCommon
  include Enumerable

  def initialize(range, ignore_ip_format)
    fail "Invalid IP range specificatioin: #{range}" unless range.is_a? String

    @range = range.split(',').map do |specific_range|
      sections = specific_range.split('.')
      fail "Invalid range: #{specific_range}" unless sections.size == 4

      sections.each_with_index.map do |e, i|
        min = ignore_ip_format || i == 1 || i == 2 ? 0 : 1
        max = ignore_ip_format ? 255 : 254
        expand_simple_range(e, min, max) or fail "Invalid range: #{specific_range}"
      end
    end

    @range_string = range
  end

  def enumerate_with(ports_range)
    Enumerator.new do |y|
      enumerate do |ip|
        ports_range.each do |port|
          y << [ip, port]
        end
      end
    end
  end

protected
  def enumerate
    @range.each do |a, b, c, d|
      a.each do |w|
        b.each do |x|
          c.each do |y|
            d.each do |z|
              yield "#{w}.#{x}.#{y}.#{z}"
            end
          end
        end
      end
    end
  end
end

class PortsRange
  include RangeCommon
  include Enumerable

  def initialize(range)
    fail "Invalid range: #{range}" unless range.is_a? String

    @range = range.split(',').map do |specific_range|
      expand_simple_range(specific_range, 1, 65535) or fail "Invalid range: #{specific_range}"
    end

    @range_string = range
  end

protected
  def enumerate
    @range.each do |specific_range|
      specific_range.each do |e|
        yield e
      end
    end
  end
end

Entry = Struct.new(:resolver_address, :provider_name, :provider_key, :latency, :next_) do
  def resolver_ip
    @resolver_ip ||= resolver_address.gsub(/:.*$/, '')
  end

  def resolver_port
    @resolver_port ||= Integer(resolver_address.gsub(/^.*:/, ''))
  end
end

def prepare_dir(dir)
  if not File.exist? dir
    log_message "Creating directory #{dir}."

    begin
      FileUtils.mkdir_p dir
    rescue SystemCallError => ex
      fail "Failed to create directory #{dir}: #{ex.message}"
    end
  elsif not File.directory? dir
    fail "Object exists but is not a directory: #{dir}"
  end

  if @params.change_owner
    owner = @params.user || Process.uid
    log_message "Changing owner of #{dir} to #{owner}."

    begin
      FileUtils.chown(owner, nil, [dir])
    rescue SystemCallError, ArgumentError => ex
      fail "Failed to change ownership of directory #{dir} to #{owner}: #{ex.message}"
    end
  end
end

def stop_instances
  log_message "Stopping instances."

  @pids.each do |pid|
    Process.kill('TERM', pid) rescue Errno::ESRCH
  end
end

def main
  initialize_params

  #
  # Parse options.
  #

  parser = OptionParser.new

  parser.on_tail("-h", "--help", "Show this help info and exit.") do
    $stderr.puts "dnscrypt-proxy-multi #{VERSION}
Runs multiple instances of dnscrypt-proxy.

Usage: #{$0} [options]

Options:"
    $stderr.puts parser.summarize([], 3, 80, "")
    $stderr.puts
    $stderr.puts "Notes:"
    $stderr.puts "* Directories are automatically created recursively when needed."
    $stderr.puts "* Services are checked with TCP ports since TCP is a common fallback."
    $stderr.puts "* Local ports are first used up before the next IP address in range is used."
    $stderr.puts "* Local ports are not checked if they are currently in use."
    $stderr.puts "* Names of log files are created based on the remote address, while names of"
    $stderr.puts "  PID files are based on the local address."
    $stderr.puts "* dnscrypt-proxy creates files as the calling user; not the one specified with"
    $stderr.puts "  --user, so changing ownership of directories and existing files may not be"
    $stderr.puts "  necessary."
    exit 1
  end

  parser.on("-c", "--resolver-check=FQDN[/TIMEOUT[/WAIT]]", "Check instances of dnscrypt-proxy if they can resolve FQDN, and replace them", "with another instance that targets another resolver entry if they don't.", "Default timeout is #{@params.resolver_check_timeout}.  Default amount of wait-time to allow an instance to", "load and initialize before checking it is #{@params.resolver_check_wait}.") do |fqdn_timeout|
    fqdn, timeout, wait = fqdn_timeout.split('/')

    if timeout and not timeout.empty?
      timeout = Float(timeout) rescue fail("Invalid timeout value: #{timeout}")
      @params.resolver_check_timeout = timeout
    end

    if wait and not wait.empty?
      wait = Float(wait) rescue fail("Invalid waiting time value: #{timeout}")
      @params.resolver_check_wait = wait
    end

    fail "Not a valid FQDN: #{fqdn}" unless valid_fqdn?(fqdn)
    @params.resolver_check = fqdn
  end

  parser.on("-C", "--change-owner", "Change ownership of directories to specified user or the process' UID.") do
    @params.change_owner = true
  end

  parser.on("-d", "--dnscrypt-proxy=PATH", "Set path to dnscrypt-proxy executable.", "Default is \"#{@params.dnscrypt_proxy}\".") do |path|
    fail "Not executable or does not exist: #{path}" unless executable_file?(path)
    @params.dnscrypt_proxy = path
  end

  parser.on("-D", "--debug", "Show debug messages.") do
    @params.debug = true
  end

  parser.on("-i", "--local-ip=RANGE", "Set range of IP addresses to listen to.  Default is \"#{@params.local_ip_range}\".", "Example: \"127.0.1-254.1-254,10.0.0.1\"") do |range|
    @params.local_ip_range = range
  end

  parser.on("-I", "--ignore-ip-format", "Do not check if a local IP address starts or ends with 0 or 255.") do
    @params.ignore_ip_format = true
  end

  parser.on("-l", "--log [LOG_DIR]", "Enable logging files to LOG_DIR.", "Default directory is \"#{@params.log_dir}\".") do |dir|
    @params.log = true
    @params.log_dir = dir if dir
  end

  parser.on("-L", "--log-level=LEVEL", "When logging is enabled, tell dnscrypt-proxy to use log level LEVEL.", "Default level is #{@params.log_level}.  See dnscrypt-proxy(8) for info.") do |level|
    fail "Value for log level an unsigned integer: #{level}" unless level =~ /^[[:digit:]]+$/
    @params.log_level = Integer(level)
  end

  parser.on("-m", "--max-instances=N", "Set maximum number of dnscrypt-proxy instances.  Default is #{@params.max_instances}.") do |n|
    fail "Value for max instances must be an unsigned integer: #{n}" unless n =~ /^[[:digit:]]+$/
    n = Integer(n)
    fail "Value for max instances cannot be 0 or greater than #{INSTANCES_LIMIT}: #{n}" if n.zero? or n > INSTANCES_LIMIT
    @params.max_instances = n
  end

  parser.on("-o", "--log-output=FILE", "When logging is enabled, write main log output to FILE.",  "Default is \"<LOG_DIR>/dnscrypt-proxy-multi.log\".") do |file|
    @params.log_file = file
  end

  parser.on("-O", "--log-overwrite", "When logging is enabled, do not append output to main log-file.") do
    @params.log_overwrite = true
  end

  parser.on("-p", "--local-port=RANGE", "Set range of ports to listen to.", "Default is \"#{@params.local_port_range}\".  Example: \"2053,5300-5399\"") do |range|
    @params.local_port_range = range
  end

  parser.on("-r", "--resolvers-list=PATH", "Set resolvers list file to use.", "Default is \"#{@params.resolvers_list}\".") do |path|
    fail "Not a readable file: #{path}" unless File.file?(path) and File.readable?(path)
    @params.resolvers_list = path
  end

  parser.on("-R", "--resolvers-list-encoding", "Set encoding of resolvers list.  Default is \"#{@params.resolvers_list_encoding}\".") do |e|
    @params.resolvers_list_encoding = e
  end

  parser.on("-s", "--port-check-async=N", "Set number of port-check queries to send simultaneously.  Default is #{@params.port_check_async}.") do |n|
    fail "Value for number of simultaneous checks must be an unsigned integer: #{n}" unless n =~ /^[[:digit:]]+$/
    n = Integer(n)
    fail "Value for number of simultaneous checks can't be 0." if n.zero?
    @params.port_check_async = n
  end

  parser.on("-t", "--port-check-timeout=SECONDS", "Set timeout when waiting for a port-check reply.  Default is #{@params.port_check_timeout}.") do |secs|
    secs = Float(secs) rescue fail("Value for check timeout must be a number: #{secs}")
    fail "Value for check timeout can't be 0." if secs.zero?
    @params.port_check_timeout = secs
  end

  parser.on("-u", "--user USER", "Tell dnscrypt-proxy to run as USER.  This also affects --change-owner.") do |user|
    fail "User can't be an empty string." if user.empty?
    @params.user = user
  end

  parser.on("-v", "--verbose", "Show verbose messages.") do
    @params.verbose = true
  end

  parser.on("-V", "--version", "Show version and exit.") do
    $stderr.puts "dnscrypt-proxy-multi #{VERSION}"
    exit 1
  end

  parser.on("-w", "--wait-before-next=SECONDS", "Wait SECONDS before creating the next instance of dnscrypt-proxy.", "Default is #{@params.wait_before_next}.") do |secs|
    @params.wait_before_next = Float(secs) rescue fail("Invalid value for instance-wait: #{secs}.")
  end

  parser.on("-W", "--write-pids [DIR]", "Enable writing PID's to DIR.", "Default directory is \"#{@params.write_pids_dir}\".") do |dir|
    @params.write_pids = true
    @params.write_pids_dir = dir if dir
  end

  parser.parse!

  begin
    #
    # Show startup message.
    #

    log_message "----------------------------------------"
    log_message "Starting up."

    #
    # Setup SIGTERM trap.
    #

    Signal.trap('TERM') do
      log_message "SIGTERM caught."
      stop_instances
      exit 1
    end

    #
    # Prepare stuff.
    #

    range = @params.local_ip_range
    ip_addr_range = IPAddrRange.new(range, @params.ignore_ip_format) or fail "Invalid range of IP addresses: #{range}"

    range = @params.local_port_range
    ports_range = PortsRange.new(range) or fail "Invalid range of ports: #{range}"

    log_warning "Specified local ip-port pairs are fewer than maximum number of instances." unless \
        ip_addr_range.enumerate_with(ports_range).take(@params.max_instances).to_a.size >= @params.max_instances

    prepare_dir(@params.write_pids_dir) if @params.write_pids
    prepare_dir(@params.log_dir) if @params.log
    mode = @params.log_overwrite ? 'w' : 'a'

    if @params.log
      log_file = @params.log_file || File.join(@params.log_dir, "dnscrypt-proxy-multi.log")
      fail "Log-file exists but is a directory: #{log_file}" if File.directory?(log_file)

      begin
        @log_file = File.open(log_file, mode)
      rescue Errno::EACCES, Errno::ENOENT => ex
        fail "Failed to open file #{log_file}: #{ex.message}"
      end

      @log_file.puts @log_buffer
      @log_file.flush
    end

    @log_buffer = nil

    #
    # Parse resolver list.
    #

    entries = []

    CSV.foreach(@params.resolvers_list, encoding: @params.resolvers_list_encoding) do |row|
      resolver_address, provider_name, provider_key = row.values_at(10, 11, 12)

      if not resolver_address =~ /^([[:alnum:]]{1,3}.){3}[[:alnum:]]{1,3}:[[:digit:]]+$/
        log_warning "Ignoring entry with invalid or unsupported resolver address: #{resolver_address}"
      elsif not provider_name =~ /^[[:alnum:]]+[[:alnum:]-.]+[.][[:alpha:]]+$/
        log_warning "Ignoring entry with invalid provider name: #{resolver_address} (#{provider_name})"
      elsif not provider_key =~ /^([[:alnum:]]{4}:){15}[[:alnum:]]{4}$/
        log_warning "Ignoring entry with invalid provider key: #{resolver_address} (#{provider_key})"
      else
        entries << Entry.new(resolver_address, provider_name, provider_key)
      end
    end

    #
    # Check avaiability of services.
    #

    entries.each_slice(@params.port_check_async) do |r|
      threads = []

      r.each do |e|
        log_message "Checking resolver address #{e.resolver_address}."
        log_verbose "Timeout is #{@params.port_check_timeout}."

        threads << Thread.new(e) do |e|
          e.latency = check_tcp_port(e.resolver_ip, e.resolver_port, @params.port_check_timeout)
        end
      end

      threads.each(&:join)
    end

    reachable_entries = entries.select(&:latency).sort_by(&:latency)

    if @params.verbose
      reachable_entries.each{ |e| log_verbose "Reachable entry: #{e.resolver_address} (#{e.latency})" }
      entries.reject(&:latency).each{ |e| log_verbose "Unreachable entry: #{e.resolver_address}" }
    end

    fail "No reachable entry." if reachable_entries.empty?

    #
    # Start instances.
    #

    reachable_entries_enum = reachable_entries.to_enum
    entry = nil, pid = nil
    opts = {:in => '/dev/null', :out => '/dev/null', :err => '/dev/null'}

    ip_addr_range.enumerate_with(ports_range).each do |local_ip, local_port|
      while entry = reachable_entries_enum.next rescue nil
        logfile_prefix = File.join(@params.log_dir, "dnscrypt-proxy.#{entry.resolver_ip}.#{entry.resolver_port}")

        cmd = [@params.dnscrypt_proxy,
            "--local-address=#{local_ip}:#{local_port}",
            "--resolver-address=#{entry.resolver_address}",
            "--provider-key=#{entry.provider_key}",
            "--provider-name=#{entry.provider_name}"]
        cmd += ["--logfile=#{logfile_prefix}.log",
            "--loglevel=#{@params.log_level}"] if @params.log
        cmd << "--user=#{@params.user}" if @params.user

        if @params.write_pids
          file = File.join(@params.write_pids_dir, "dnscrypt-proxy.#{local_ip}.#{local_port}.pid")
          cmd << "--pidfile=#{file}"
        end

        log_message "Starting dnscrypt-proxy instance for #{entry.resolver_address} (#{local_ip}:#{local_port})."

        begin
          log_verbose "Command: #{cmd.map{ |e| e.inspect }.join(' ')}" if @params.verbose

          if @params.log
            stdout, stderr = ['stdout', 'stderr'].map do |e|
              file = "#{logfile_prefix}.#{e}.log"

              begin
                File.open(file, @params.log_overwrite ? 'w' : 'a')
              rescue SystemCallError => ex
                fail "Failed to open log file #{file}: #{ex.message}"
              end
            end

            pid = Process.fork do
              opts[:out] = stdout
              opts[:err] = stderr
              Process.exec(*cmd, opts)
            end

            stdout.close
            stderr.close
          else
            pid = Process.spawn(*cmd, opts)
          end
        rescue Exception => ex
          log_error "Failed to create instance of dnscrypt-proxy: #{ex.message}"
          next
        end

        if @params.resolver_check
          log_message "Checking if #{entry.resolver_address} (#{local_ip}:#{local_port}) can resolve #{@params.resolver_check}."
          log_verbose "Timeout is #{@params.resolver_check_timeout}."

          sleep @params.resolver_check_wait

          begin
            r = Resolv::DNS.new(nameserver_port: [[local_ip, local_port]])
            r.timeouts = @params.resolver_check_timeout
            ipv4 = r.getaddress(@params.resolver_check)
            log_message "Success: #{ipv4.to_name.to_s.gsub(/\.in-addr\.arpa$/, '')}"
          rescue Resolv::ResolvError => ex
            log_error "Resolve error: #{ex.message}"
            log_verbose "Stopping instance."
            Process.kill('TERM', pid) rescue SystemCallError
            Process.wait(pid) rescue SystemCallError
            next
          end
        end

        @pids << pid
        raise if @pids.size > @params.max_instances
        break
      end

      break if entry.nil? or @pids.size == @params.max_instances
      Kernel.sleep(@params.wait_before_next) if @params.wait_before_next > 0.0
    end

    #
    # Wait for all processes to exit and shutdown.
    #

    r = Process.waitall
    @exit_status = 0 if r.is_a?(Array) and r.all?{ |a| a.last.exitstatus == 0 }
  rescue Interrupt
    log_message "SIGINT caught."
    stop_instances if @pids
  ensure
    log_message "Exiting."
    @log_file.close if @log_file
  end

  @exit_status
end

main
