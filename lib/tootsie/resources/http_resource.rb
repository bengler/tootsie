module Tootsie
  module Resources

    class HttpResource

      include PrefixedLogging

      def initialize(uri)
        @uri = uri
      end

      def open(mode = 'r')
        case mode
          when 'r'
            visited, uri = Set.new, @uri.to_s
            logger.info "Fetching #{@uri}"
            loop do
              close

              response = Excon.get(uri,
                :headers => {
                  'Accept' => '*/*',
                  'User-Agent' => 'Tootsie/1.0 (+https://github.com/bengler/tootsie)'
                },
                :response_block => proc { |chunk, remaining_bytes, total_bytes|
                  ensure_temp_file.write(chunk)
                })

              content_type = response.headers['Content-Type']
              logger.info "Responded with #{response.status}, content type #{content_type}"

              case response.status
                when 200
                  if ensure_temp_file.size == 0
                    logger.error "Response is unexpectedly empty"
                    raise ResourceEmpty
                  else
                    @content_type = content_type
                    ensure_temp_file.seek(0)
                    break
                  end
                when 404, 410
                  raise ResourceNotFound
                when 503
                  # According to HTTP spec, we should only retry if this header is present
                  if response.headers['Retry-After']
                    logger.info "Retry-After header, counting as retriable"
                    raise ResourceTemporarilyUnavailable,
                      "Server returned status #{response.status} for #{uri}"
                  else
                    logger.info "No Retry-After header, counting as permanent failure"
                    raise ResourceUnavailable,
                      "Server returned status #{response.status} for #{uri}"
                  end
                when 502, 503, 504
                  raise ResourceTemporarilyUnavailable,
                    "Server returned status #{response.status} for #{uri}"
                when 301, 302, 400..499
                  raise ResourceUnavailable,
                    "Server returned status #{response.status} for #{uri}"
                else
                  raise UnexpectedResponse, "Server returned status #{response.status} for #{uri}"
              end
            end
          when 'w'
            close
            ensure_temp_file
          else
            raise ArgumentError, "Invalid mode: #{mode.inspect}"
        end
        @temp_file
      rescue Timeout::Error, Excon::Errors::Timeout
        raise ResourceTemporarilyUnavailable, "Timeout fetching #{uri}"
      rescue Excon::Errors::SocketError => e
        raise ResourceTemporarilyUnavailable, "Socket error fetching #{uri}: #{e.class}: #{e}"
      end

      def close
        if @temp_file
          @temp_file.unlink rescue nil
          @temp_file.close unless @temp_file.closed?
          @temp_file = nil
        end
      end

      def save
        return unless @temp_file
        @temp_file.seek(0)
        response = Excon.post(@uri.to_s,
          :body => @temp_file,
          :headers => {'Content-Type' => @content_type || 'application/octet-stream'})
        unless (200..399).include?(response.status)
          raise UnexpectedResponse,
            "Server returned status #{response.status} when trying to POST to #{uri}"
        end
        close
      end

      def file
        @temp_file
      end

      def url
        @uri.to_s
      end
      alias_method :public_url, :url

      attr_accessor :content_type

      private

        def ensure_temp_file
          @temp_file ||= Tempfile.open('tootsie')
        end

    end

  end
end
