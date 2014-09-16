require 'sinatra/base'

module Tootsie
  module API
    class V1 < Sinatra::Base

      include PrefixedLogging

      configure do |config|
        config.set :sessions, false
        config.set :run, false
        config.set :logging, true
        config.set :show_exceptions, false
      end

      register Sinatra::Pebblebed

      not_found do
        halt 404, "Not found"
      end

      post %r{/job(s)?/?} do
        post = JSON.parse(request.env["rack.input"].read).symbolize_keys

        path = post[:path]
        if path and not Configuration.instance.paths[path]
          logger.warn "Unregistered path, using default: #{path}"
          path = nil
        end
        path ||= 'default'

        job_data = post.except(:session, :captures, :splat, :path, :created_at)
        job_data[:uid] = ["tootsie.job:#{path}$",
          Time.now.strftime('%Y%m%d%H%M%S'),
          SecureRandom.random_number(2 ** 64).to_s(36)].join

        logger.info "Accepting job: #{job_data.inspect}"

        job = Job.new(job_data)
        unless job.valid?
          halt 400, 'Invalid job specification'
        end
        job.publish

        halt 201, job.uid
      end

    end
  end
end