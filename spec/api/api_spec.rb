require 'spec_helper'

include WebMock::API
include Tootsie::API

describe V1 do

  include Rack::Test::Methods

  def app
    V1
  end

  before :each do
    Tootsie::Configuration.instance.update(
      aws_access_key_id: "KEY",
      aws_secret_access_key: "SECRET",
      paths: {
        dustin_hoffman: {}
      })
  end

  ["/jobs", "/job"].each do |path|
    describe "POST #{path}" do

      it 'posts job on queue' do
        attributes = {
          type: 'image',
          notification_url: "http://example.com/transcoder_notification",
          reference: {'meaning' => 42},
          params: {}
        }

        expect(Configuration.instance.river).to receive(:publish) do |event|
          expect(event[:uid]).to match /^tootsie\.job:dustin_hoffman\$/
          expect(event[:type]).to eq 'image'
          expect(event[:event]).to eq 'tootsie.job'
          expect(event[:reference]).to eq({'meaning' => 42})
          expect(event[:params]).to eq({})
          expect(event[:notification_url]).to eq "http://example.com/transcoder_notification"
        end
        post '/jobs', JSON.dump(attributes.merge(
          path: 'dustin_hoffman'
        ))
        last_response.status.should eq 201
      end

      it 'accepts job without a path, defaults to "tootsie"' do
        attributes = {
          type: 'image',
          notification_url: "http://example.com/transcoder_notification",
          reference: {'meaning' => 42},
          params: {}
        }

        expect(Configuration.instance.river).to receive(:publish) do |event|
          expect(event[:uid]).to match /^tootsie\.job:default\$/
        end
        post '/jobs', JSON.dump(attributes)
        last_response.status.should eq 201
      end

    end
  end

end