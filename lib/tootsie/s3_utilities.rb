module Tootsie

  module S3Utilities

    class << self
      def parse_uri(url)
        if url =~ /^s3:([^\/]+)\/+(.+?)(?:\?(.*))?$/
          output = {}.with_indifferent_access
          output[:bucket], output[:key], option_string = $1, $2, $3
          unless option_string.blank?
            option_string.split('&').map { |pair| pair.scan(/^(.*?)=(.*)$/)[0] }.each do |k, v|
              v = v.to_sym if v =~ /\A[a-zA-Z_]+\Z/
              output[k] = v
            end
          end
          output
        else
          raise ArgumentError, "Not an S3 URL"
        end
      end
    end

  end

end
