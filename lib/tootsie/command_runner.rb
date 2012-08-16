module Tootsie

  class CommandExecutionFailed < StandardError; end

  class CommandRunner

    def initialize(command_line, options = {})
      @options = options.symbolize_keys
      @options.assert_valid_keys(:ignore_exit_code, :output_encoding)
      @command_line = command_line
      @logger = Application.get.logger
    end

    def run(params = {}, &block)
      command_line = @command_line
      if params.any?
        params = params.with_indifferent_access
        command_line = command_line.gsub(/(^|\s):(\w+)/) do
          pre, key, all = $1, $2, $~[0]
          if params.include?(key)
            value = params[key]
            value = "'#{value}'" if value =~ /\s/
            "#{pre}#{value}"
          else
            all
          end
        end
      end
      command_line = "#{command_line} 2>&1"

      @logger.info("Running command: #{command_line}") if @logger.info?
      IO.popen(command_line, "r:#{@options[:output_encoding] || 'utf-8'}") do |output|
        output.each_line do |line|
          line.split(/\r/).each do |linepart|
            @logger.info("[Command output] #{linepart.strip}") if @logger.info?
            yield linepart if block_given?
          end
        end
      end
      status = $?
      if status.exited?
        if status.exitstatus != 0
          if @options[:ignore_exit_code]
            return false
          else
            raise CommandExecutionFailed, "Command failed with exit code #{status.exitstatus}: #{command_line}"
          end
        end
      elsif status.stopped?
        raise CommandExecutionFailed, "Command stopped unexpectedly with signal #{status.stopsig}: #{command_line}"
      elsif status.signaled?
        raise CommandExecutionFailed, "Command died unexpectedly by signal #{status.termsig}: #{command_line}"
      else
        raise CommandExecutionFailed, "Command died unexpectedly: #{command_line}"
      end
      true
    end
  
  end
end
