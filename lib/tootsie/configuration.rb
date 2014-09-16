module Tootsie

  class Configuration

    include Singleton

    def initialize
      @ffmpeg_thread_count = 1
      @queue_options = {}
      @river = Pebbles::River::River.new
      @logger = LOGGER if defined?(logger)
      @logger ||= Logger.new($stdout)
      @use_legacy_completion_event = true
      @failure_queue_ttl = nil
      @paths = {}
    end

    def update(config)
      config = config.with_indifferent_access

      if config.include?(:log_path)
        logger.warn "Ignoring log_path in configuration, no longer supported; " \
          "create a config/site.rb and assign LOGGER there instead"
      end

      if config.include?(:pid_path)
        logger.warn "Ignoring pid_path in configuration, no longer used; " \
          "pass path to bin/tootsie instead"
      end

      if config.include?(:worker_count)
        @logger.warn "Ignoring worker_count in configuration, no longer used; " \
          "pass --workers to bin/tootsie instead"
      end

      [:ffmpeg_thread_count,
        :aws_access_key_id,
        :aws_secret_access_key,
        :create_failure_queue,
        :failure_queue_ttl,
        :use_legacy_completion_event,
        :paths
      ].each do |key|
        if config.include?(key)
          self.send("#{key}=", config[key])
        end
      end

      @paths.each do |_, path|
        path.symbolize_keys.assert_valid_keys(:worker_count)
      end

      if @create_failure_queue
        @river.queue(
          name: 'tootsie.failed',
          event: 'tootsie.failed',
          ttl: @failure_queue_ttl ? @failure_queue_ttl * 1000 : nil)
      end
    end

    def load_from_file(file_name)
      update(YAML.load(File.read(file_name)) || {})
    end

    def s3_service
      if @aws_access_key_id and @aws_secret_access_key
        return @s3_service ||= ::S3::Service.new(
          access_key_id: @aws_access_key_id,
          secret_access_key: @aws_secret_access_key)
      else
        abort "AWS access key and secret required"
      end
    end

    def report_exception(exception, message = nil)
      if logger.respond_to?(:exception)
        # This allows us to plug in custom exception handling
        logger.error(message) if message
        logger.exception(exception)
      else
        logger.error("#{message}: #{exception.class}: #{exception}")
      end
    end

    attr_accessor :ffmpeg_thread_count
    attr_accessor :aws_secret_access_key
    attr_accessor :aws_access_key_id
    attr_accessor :create_failure_queue
    attr_accessor :failure_queue_ttl
    attr_accessor :paths

    attr_reader :river
    attr_reader :logger

  end

end
