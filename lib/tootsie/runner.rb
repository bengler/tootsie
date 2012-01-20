module Tootsie

  # Runs the daemon from the command line.
  class Runner

    def initialize
      @run_as_daemon = false
      @config_path = '/etc/tootsie/tootsie.conf'
      @app = Application.new
    end

    def run!(arguments = [])
      OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($0)} [OPTIONS]"
        opts.separator ""
        opts.on("-d", "--daemon", 'Run as daemon') do
          @run_as_daemon = true
        end
        opts.on("-p PATH", "--pid", "Store pid in PATH (defaults to #{@pid_path})") do |value|
          @pid_path = File.expand_path(value)
        end
        opts.on("-c FILE", "--config FILE", "Read configuration from FILE (defaults to #{@config_path})") do |value|
          @config_path = File.expand_path(value)
        end
        opts.on("-h", "--help", "Show this help.") do
          puts opts
          exit
        end
        opts.parse!(arguments)
      end

      @app.configure!(@config_path)

      if @run_as_daemon
        daemonize!
      else
        execute!
      end
    end

    private

      def execute!
        with_pid do
          @spawner = Spawner.new(
            :num_children => @app.configuration.worker_count,
            :logger => logger)
          @spawner.on_spawn do
            $0 = "tootsie: worker"
            Signal.trap('TERM') do
              exit(2)
            end
            with_lifecycle_logging("Worker [#{Process.pid}]") do
              @app.task_manager.run!
            end
          end
          with_lifecycle_logging('Main process') do
            @spawner.run
          end
          @spawner.terminate
        end
      end

      def daemonize!(&block)
        return Process.fork {
          logger = @app.logger

          Process.setsid
          0.upto(255) do |n|
            File.for_fd(n, "r").close rescue nil
          end

          File.umask(27)
          Dir.chdir('/')
          $stdin.reopen("/dev/null", 'r')
          $stdout.reopen("/dev/null", 'w')
          $stderr.reopen("/dev/null", 'w')

          Signal.trap("HUP") do
            logger.debug("Ignoring SIGHUP")
          end

          execute!
        }
      end

      def with_pid(&block)
        path = @pid_path
        path ||= @app.configuration.pid_path
        path ||= '/var/run/tootsie.pid'

        File.open(path, 'w') do |file|
          file << Process.pid
        end
        begin
          yield
        ensure
          File.delete(path) rescue nil
        end
      end

      def with_lifecycle_logging(prefix, &block)
        logger.info("#{prefix} starting")
        yield
      rescue SystemExit, Interrupt, SignalException
        logger.info("#{prefix} signaled")
      rescue Exception => e
        logger.error("#{prefix} failed with exception #{e.class}: #{e}")
        exit(1)
      end

      def logger
        @app.logger
      end

  end

end
