# encoding: utf-8

require 'spec_helper'

include Tootsie
include Tootsie::Processors

describe VideoProcessor do

  it "performs basic ffmpeg transcoding" do
    stub_request(:get, "http://example.com/video.mp4").
      to_return(:status => 200, :body => '')

    FfmpegAdapter.any_instance.should_receive(:transcode).with(
      kind_of(String), kind_of(String), kind_of(Hash)).once
    FfmpegAdapter.any_instance.stub(:transcode) { |in_path, out_path, adapter_options|
      adapter_options.should include(
        :audio_sample_rate => 44100,
        :audio_bitrate => 64000,
        :format => "flv",
        :width => 600,
        :height => 400,
        :content_type => "video/x-flv")
      File.open(out_path, "w") { |f|
        f.write("DATA")
      }
    }

    post_stub = stub_request(:post, "http://example.com/video.flv").
      with(
        :headers => {'Content-Type' => 'video/x-flv'},
        :body => 'DATA').
      to_return(:status => 200, :body => '')

    VideoProcessor.new(
      :input_url => "http://example.com/video.mp4",
      :versions => [
        {
          :target_url => "http://example.com/video.flv",
          :audio_sample_rate => 44100,
          :audio_bitrate => 64000,
          :format => 'flv',
          :width => 600,
          :height => 400,
          :content_type => "video/x-flv"
        }
      ]).execute!

    post_stub.should have_been_requested
  end

end