require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/tty'

require 'shellwords'

module Macinbox

  class Task

    def self.run(cmd)
      Logger.info "Running command: #{Shellwords.join(cmd)}" if $verbose
      system(*cmd) or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$? >> 8}")
    end

    def self.run_as_sudo_user(cmd)
      Logger.info "Running command: sudo -u #{ENV["SUDO_USER"]} #{Shellwords.join(cmd)}" if $verbose
      system "sudo", "-u", ENV["SUDO_USER"], *cmd or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$?.to_i}")
    end

    def self.progress_bar(activity, percent_done)
      @spinner ||= Enumerator.new { |e| loop { e.yield '|'; e.yield '/'; e.yield '-'; e.yield '\\' } }
      columns = STDOUT.winsize[1] - 8
      header = activity + ": " + percent_done.round(0).to_s + "% done "
      bar = ""
      if percent_done.round(0).to_i < 100
        bar_available_size = columns - header.size - 2
        bar_size = (percent_done * bar_available_size / 100.0).to_i
        bar_remainder = bar_available_size - bar_size
        bar_full = "#" * bar_size
        bar_empty = @spinner.next + " " * (bar_remainder-1) rescue ""
        bar = "[" + bar_full + bar_empty + "]"
      end
      header + bar
    end

    def self.print_progress_bar(io, activity, percent_done)
      io.print TTY::Line::CLEAR + TTY::Color::GREEN + progress_bar(activity, percent_done) + TTY::Color::RESET if io.isatty
    end

    def self.run_with_progress(activity, cmd, opts={})
      STDERR.print TTY::Cursor::INVISIBLE
      print_progress_bar(STDERR, activity, 0.0)
      Logger.info "Running command: #{Shellwords.join(cmd)}" if $verbose
      IO.popen cmd, opts do |pipe|
        pipe.each_line do |line|
          percent = yield line
          print_progress_bar(STDERR, activity, percent) if percent
        end
      end
      STDERR.puts TTY::Cursor::NORMAL
      $? == 0 or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$?.to_i}")
    end

    def self.write_file_to_io_with_progress(source, destination)
      activity = Logger.prefix + File.basename(source)
      eof = false
      bytes_written = 0
      total_size = File.size(source)
      last_percent_done = -1
      STDERR.print TTY::Cursor::INVISIBLE
      print_progress_bar(STDERR, activity, 0.0)
      File.open(source) do |file|
        until eof
          begin
            bytes_written += destination.write(file.readpartial(1024*1024))
            percent_done = ((bytes_written.to_f / total_size.to_f) * 100).round(1)
            last_percent_done = percent_done
            print_progress_bar(STDERR, activity, percent_done)
          rescue EOFError
            eof = true
          end
        end
      end
      STDERR.puts TTY::Cursor::NORMAL
    end

    def self.backtick(cmd)
      Logger.info "Running command: #{Shellwords.join(cmd)}" if $verbose
      IO.popen(cmd).read.chomp
    end

    def self.run_with_input(cmd)
      Logger.info "Running command: #{Shellwords.join(cmd)}" if $verbose
      IO.popen(cmd, "w") do |pipe|
        yield pipe
      end
      $? == 0 or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$?.to_i}")
    end
  end

end
