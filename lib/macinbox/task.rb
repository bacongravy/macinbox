require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/tty'

module Macinbox

  class Task

    include TTY

    def self.run(cmd)
      system(*cmd) or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$?.to_i}")
    end

    def self.run_as_sudo_user(cmd)
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

    def self.run_with_progress(activity, cmd, opts={})
      STDERR.print CURSOR_INVISIBLE
      STDERR.print CLEAR_LINE + GREEN + progress_bar(activity, 0.0) + BLACK
      IO.popen cmd, opts do |pipe|
        pipe.each_line do |line|
          percent = yield line
          STDERR.print CLEAR_LINE + GREEN + progress_bar(activity, percent) + BLACK if percent
        end
      end
      STDERR.puts CURSOR_NORMAL
    end

    def self.write_file_to_io_with_progress(source, destination)
      activity = Logger.prefix + File.basename(source)
      eof = false
      bytes_written = 0
      total_size = File.size(source)
      last_percent_done = -1
      STDERR.print CURSOR_INVISIBLE
      STDERR.print CLEAR_LINE + GREEN + progress_bar(activity, 0.0) + BLACK
      File.open(source) do |file|
        until eof
          begin
            bytes_written += destination.write(file.readpartial(1024*1024))
            percent_done = ((bytes_written.to_f / total_size.to_f) * 100).round(1)
            last_percent_done = percent_done
            STDERR.print CLEAR_LINE + GREEN + progress_bar(activity, percent_done) + BLACK
          rescue EOFError
            eof = true
          end
        end
      end
      STDERR.puts CURSOR_NORMAL
    end

    def self.backtick(cmd)
      IO.popen(cmd).read.chomp
    end

    def self.run_with_input(cmd)
      IO.popen(cmd, "w") do |pipe|
        yield pipe
      end
      $? == 0 or raise Macinbox::Error.new("#{cmd.slice(0)} failed with non-zero exit code: #{$?.to_i}")
    end
  end

end
