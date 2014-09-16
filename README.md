Tootsie
=======

**Note: Tootsie is currently distributed as an application, and no longer as a gem.**

Tootsie is a simple, robust, scalable audio/video/image transcoding/modification application.

Tootsie can transcode audio, video and images between different formats, and also perform basic manipulations such as photo scaling and cropping, for generating thumbnails and photos at different resolutions.

For integrating into web apps, we recommend [Tiramisu](http://github.com/bengler/tiramisu), which is written specifically for Tootsie.

Overview
--------

Tootsie is divided into multiple independent parts:

### API

The API providers a simple way to submit new jobs.

### Job manager

The job manager typically runs as a daemon. It processes new job requests in the queue and executes them.

### Transcoding processors

There are multiple processors. External transcoding tools such as ffmpeg and ImageMagick are used to perform the actual transcoding.

### Storage

Tootsie can read files via HTTP[S], and can upload data via HTTP[S] POSTs. In addition, Amazon S3 buckets are also supported.

Dependencies
------------

* Ruby 1.9.3 or later.
* Unix-like system (no Windows support currently).
* AMQP server such as RabbitMQ.
* **For video jobs**
  * FFmpeg
  * id3v2 (optional)
* **For image jobs**
  * ImageMagick
  * Exiv2
  * pngcrush (optional)
* Amazon S3 account (optional), for loading and storage of files.

Installation
------------

    git clone https://github.com/bengler/tootsie.git

Running
-------

First, create a YAML configuration file and put it in `config/tootsie.conf`:

    aws_access_key_id: <your Amazon key>
    aws_secret_access_key: <your Amazon secret>

Start the job manager with:

    $ bin/tootsie start -p tootsie.pid --daemon

To run the web service, you will need a Rack-compatible web server, such as Unicorn. To start Unicorn on port 8080:

    $ unicorn config.ru

Jobs may now be posted to the web service API. For example:

    $ cat << END | curl -XPOST -d @- http://localhost:8080/api/tootsie/v1/jobs
    {
      "type": "video",
      "notification_url": "http://example.com/transcoder_notification",
      "params": {
        "input_url": "http://example.com/test.3gp",
        "versions": {
          "target_url": "s3:mybucket/test.mp4?acl=public-read",
          "audio_sample_rate": 44100,
          "audio_bitrate": 64000,
          "format": "flv",
          "content_type": "video/x-flv"
        }
      }
    }
    END

Configuration
-------------

The configuration `config/tootsie.conf` is a YAML document with the following keys:

* `aws_access_key_id`: Your Amazon key.
* `aws_secret_access_key`: Your Amazon secret.
* `create_failure_queue`: If true, a queue is automatically created that is bound to the exchange with a routing key such that any permanently failed jobs end up here. This queue can be used to inspect failures and requeue them.
* `failure_queue_ttl`: If set, the failure queue will be created with this TTL setting (requires RabbitMQ). Unlike RabbitMQ, this specifies the timeout in _seconds_.
* `use_legacy_completion_event`: If true, use the event type `tootsie_completed` instead of `tootsie.completed`.
* `paths`: Specify separate paths that will be mapped to queues, each of which have different processing behaviours. See section below.

### Paths

To specify multiple concurrent queues that can be targeted by the API and have different workers:

    paths:
      high_priority:
        worker_count: 10

This will create a listener that only listens for jobs added with the path `high_priority`. The worker setting means this listener will get more workers than the default queue.

The default path is `default`. It gets the worker count specified on the daemon command line.

**Important**: If you previously have run without any paths set, you must manually unbind the queue `tootsie` from the routing key `tootsie.job._.#._.#`. Otherwise priority-based queues will get _all_ messages.

### Old settings no longer supported

* `pid_path`: Specify with `tootsie --pidfile`.
* `log_path`: Override this by assigning `LOGGER` in your `config/site.rb`.
* `worker_count`: Specify with `tootsie --workers`.
* `queue`: The queue is always named `tootsie`. The host is always `localhost`. (The ability to override this is something we'll add back.)

Additionally, `bin/tootsie` no longer supports overriding the configuration location with `-c`.

### Exception notification

Tootise can report errors to services such as Airbrake and Rollbar. To accomplish this, provide a `LOGGER` object that supports the method:

    def exception(exception)

### Configuration overrides

Place a file `config/site.rb` containing configuration overrides. For example, this would be the place to set up any site-specific logging.

API
---

### `POST /api/tootsie/v1/jobs`

Schedule a new job. Returns 201 if the job was created. The job must be posted as an JSON hash with the content type `application/json`. Common to all jobs are these keys:

* `type`: Type of job. See sections below for details.
* `notification_url`: Optional notification URL. Progress (including completion and failure) will be reported using POSTs.
* `retries`: Maximum number of retries, if any. Defaults to 5.
* `params`: Job-type-specific parameters.
* `reference`: A client-supplied value (or hash of values). Tootsie ignores the contents of this value. The value will be passed as part of notifications.
* `path`: The root path of the UID generated for each job. Optional, defaults to `tootsie`. This can be used to create multiple concurrent queues, by creating separate listeners for each path. See section on configuration. Note that a path must be registered in the configuration before it can be used by the API.

### `GET /api/tootsie/v1/status`

Get some current processing status as a JSON hash.

Workflow
--------

The Tootsie daemon pops jobs from a queue and processes them. Each job specifies an input, an output, and transcoding parameters. Optionally the job may also specify a notification URL which is invoked to inform the caller about job progress.

Supported inputs at the moment:

* HTTP resource. Currently only public (non-authenticated) resources are supported.
* Amazon S3 bucket resource. S3 buckets must have the appropriate ACLs so that Tootsie can read the files; if the input file is not public, Tootsie must be run with an AWS access key that is granted read access to the file.

Supported outputs:

* HTTP resource. The encoded file will be `POST`ed to a URL.
* Amazon S3 bucket resource. Tootsie will need write permissions to any S3 buckets.

Each job may have multiple outputs given a single input. Design-wise, the reason for doing this — as opposed to requiring that the client submit multiple jobs, one for each output — is twofold:

1. It allows the job to cache the input data locally for the duration of the job, rather than fetching it multiple times. One could suppose that multiple jobs could share the same cached input, but this would be awkward in a distributed setting where each node has its own file system; in such a case, a shared storage mechanism (file system, database or similar) would be needed.

2. It allows the client to be informed when *all* transcoded versions are available, something which may drastically simplify client logic. For example, a web application submitting a job to produce multiple scaled versions of an image may only start showing these images when all versions have been produced. To know whether all versions have been produced, it needs to maintain state somewhere about the progress. Having a single job produce all versions means this state can be reduced to a single boolean value.

When using multiple outputs per job one should keep in mind that this reduces job throughput, requiring more concurrent job workers to be deployed.

FFmpeg and ImageMagick are invoked for each job to perform the transcoding. These are abstracted behind set of generic options specifying format, codecs, bit rate and so on.

### Video transcoding jobs

Video jobs have the `type` key set to either `video`, `audio`. Currently, `audio` is simply an alias for `video` and handled by the same pipeline. The key `params` must be set to a hash with these keys:

* `input_url`: URL to input file, either an HTTP URL or an S3 URL (see below).
* `versions`: Either a hash or an array of such hashes, each with the following keys:
    * `target_url`: URL to output resource, either an HTTP URL which accepts POSTs, or an S3 URL.
    * `thumbnail`: If specified, a thumbnail will be generated based on the options in this hash with the following keys:
        * `target_url`: URL to output resource, either an HTTP URL which accepts POSTs, or an S3 URL.
        * `width`: Desired width of thumbnail, defaults to output width.
        * `height`: Desired height of thumbnail, defaults to output height.
        * `at_seconds`: Desired point (in seconds) at which the thumbnail frame should be captured. Defaults to 50% into stream.
        * `at_fraction`: Desired point (in percentage) at which the thumbnail frame should be captured. Defaults to 50% into stream.
        * `force_aspect_ratio`: If `true`, force aspect ratio; otherwise aspect is preserved when computing dimensions.
    * `audio_sample_rate`: Audio sample rate, in hertz.
    * `audio_bitrate`: Audio bitrate, in bits per second.
    * `audio_codec`: Audio codec name, eg. `mp4`.
    * `video_frame_rate`: video frame rate, in hertz.
    * `video_bitrate`: video bitrate, in bits per second.
    * `video_codec`: video codec name, eg. `mp4`.
    * `width`: desired video frame width in pixels.
    * `height`: desired video frame height in pixels.
    * `quality`: A quality value between 0.0 (low quality, low size) and 1.0 (high quality, large size) which will be translated to a compression level depending on the output coding. The default is 1.0.
    * `format`: File format.
    * `content_type`: Content type of resultant file. Tootsie will not be able to guess this at the moment.
    * `strip_metadata`: If true, metadata such as ID3 will be deleted. Since recent ffmpeg versions have issues with ID3 tags and character encodings, this is recommended for audio files. Requires `id3v2` tool.

Completion notification provides the following data:

* `outputs` contains an array of results. Each is a hash with the following keys:
    * `url`: the completed file.
    * `metadata`: image metadata as a hash. These are raw EXIF and IPTC data from ImageMagick.

#### Quality setting

The `quality` setting is an abstraction of the ffmpeg `-qscale` option. Tootsie maps to a static scale between 1 and 31. This yields constant quality with a variable bitrate (VBR).

### Image transcoding jobs

Image jobs have the `type` key set to `image`. The key `params` must be set to a hash with these keys:

* `input_url`: URL to input file, either an HTTP URL, `file:/path` URL or an S3 URL (see below).
* `versions`: Either a hash or an array of such hashes, each with the following keys:
    * `target_url`: URL to output resource, either an HTTP URL, `file:/path` URL which accepts POSTs, or an S3 URL.
    * `width`: Optional desired width of output image.
    * `height`: Optional desired height of output image.
    * `scale`: One of the following values:
        * `down` (default): The input image is scaled to fit within the dimensions `width` x `height`, giving priority to the width. If only `width` or only `height` is specified, then the other component will be computed from the aspect ratio of the input image.
        * `up`: As `fit`, but allow scaling to dimensions that are larger than the input image.
        * `fit`: Similar to `down`, but the dimensions are chosen so the output width and height are always met or exceeded. In other words, if you pass in an image that is 100x50, specifying output dimensions as 100x100, then the output image will be 150x100.
        * `none`: Don't scale at all.
    * `crop`: If true, crop the image to the output dimensions.
    * `format`: Either `jpeg`, `png` or `gif`.
    * `quality`: A quality value between 0.0 and 1.0 which will be translated to a compression level depending on the output coding. The default is 1.0.
    * `strip_metadata`: If true, metadata such as EXIF and IPTC will be deleted. For thumbnails, this often reduces the file size considerably.
    * `medium`: If `web`, the image will be optimized for web usage. See below for details.
    * `content_type`: Content type of resultant file. The system will be able to guess basic types such as `image/jpeg`.

Note that scaling always preserves the aspect ratio of the original image; in other words, if the original is 100x200, then passing the dimensions 100x100 will produce an image that is 50x100. Enabling cropping, however, will force the aspect ratio of the specified dimensions.

If the option `medium` specifies `web`, the following additional transformations will be performed:

* The image will be automatically rotated based on EXIF orientation metadata, since web browsers don't do this.
* CMYK images will be converted to RGB, since most web browsers don't seem to display CMYK correctly.

Completion notification provides the following data:

* `outputs` contains an array of results. Each is a hash with the following keys:
    * `url`: URL for the completed file.
* `metadata`: image metadata as a hash. These are raw EXIF and IPTC data from ImageMagick.
* `width`: width, in pixels, of original image.
* `height`: height, in pixels, of original image.
* `depth`: depth, in bits, of original image.

## Notifications

Tootsie will publish notifications to AMQP. It also supports a webhook.

By default, Tootsie will publish notifications to an AMQP exchange called `pebblebed.river.<environment>`. Each event contains:

* `event`: See below.
* `uid`: The unique ID of the job.
* `reference`: If the job was posted with a reference value, this contains that reference.
* `time_taken`: See below.
* `reason`: See below.

In addition, job-specific data is added to the event. See the different job types for information about those keys.

The event type is also used as the routing key, prefixed with `tootsie.`. This allows clients to listen to specific events. Types of events:

* `started`: The job was started.
* `completed`: The job was complete. The key `time_taken` will contain the time taken for the job, in seconds. Additional data will be provided that are specific to the type of job.
* `progress`: The job was progressing. Sent every 30s.
* `failed`: The job failed. The key `reason` will contain a textual explanation for the failure.
* `failed_will_retry`: The job failed, but is being rescheduled for retrying. The key `reason` will contain a textual explanation for the failure.

If a notification webhook URL is provided in original job request, events will instead be sent to that URL using `POST` requests as JSON data. These are 'fire and forget' and will not be retried on failure, and the response status code is ignored.

Previous versions would publish the AMQP event `tootsie_completed`. To continue using this event, set `use_legacy_completion_event: true` in the configuration file.

## Resource URLs

Tootsie supports referring to inputs and outputs using URLs, namely `file:` and `http:`. Additionally, Tootsie supports its own proprietary S3 URL format.

To specify S3 URLs, we use a custom URI format:

    s3:<bucketname></path/to/file>[?<options>]

The components are:

* `bucketname`: The name of the S3 bucket.
* `/path/to/file`: The actual S3 key.
* `options`: Optional parameters for storage, an URL query string.

The options are:

* `acl`: One of `private` (default), `public-read`, `public-read-write` or `authenticated-read`.
* `storage_class`: Either `standard` (default) or `reduced_redundancy`.
* `content_type`: Override stored content type.

Example S3 URLs:

* `s3:myapp/video`
* `s3:myapp/thumbnails?acl=public-read&storage_class=reduced_redundancy`
* `s3:myapp/images/12345?content_type=image/jpeg`

License
-------

This software is licensed under the MIT License.

Copyright © 2010-2014 Alexander Staubo

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
