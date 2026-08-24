#!/usr/bin/env ruby
# frozen_string_literal: true

# Random access to a remote or local file: give me these bytes at this offset.
#
# Both things this experiment downloads are small parts of large files -- one
# entry inside an 822MB zip, one tensor inside a 548MB safetensors -- and both
# formats put a directory somewhere you can only find by reading backwards or
# reading a header first. Range requests turn "download it all and pick" into
# "ask for the part". The zip fetch drops from 822MB to 65MB and the GPT-2
# fetch from 548MB to 147MB.
#
# A server that answers 200 instead of 206 has ignored the Range header and is
# sending the whole file. That raises rather than quietly proceeding, because
# quietly proceeding is a several-hundred-megabyte surprise.

require "net/http"
require "uri"

module ByteSource
  module_function

  def open(location)
    File.exist?(location.to_s) ? Local.new(location) : Http.new(location)
  end

  class Http
    MAX_REDIRECTS = 5
    UA = "llm-experiments/word-vector-arithmetic (+ruby #{RUBY_VERSION})"

    attr_reader :size

    def initialize(url)
      @url = url
      @size = probe_size
    end

    def read(offset, length)
      buffer = +""
      stream(offset, length) { |chunk| buffer << chunk }
      buffer
    end

    def stream(offset, length, &block)
      request("bytes=#{offset}-#{offset + length - 1}") { |res| res.read_body(&block) }
    end

    private

    def probe_size
      request("bytes=0-0") do |res|
        res.read_body { |_| nil }
        total = res["content-range"].to_s[%r{/(\d+)\z}, 1]
        raise "no total size in Content-Range: #{res["content-range"].inspect}" unless total

        total.to_i
      end
    end

    def request(range, url = @url, hops = 0, &block)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 30, read_timeout: 180) do |http|
        req = Net::HTTP::Get.new(uri)
        req["Range"] = range
        req["User-Agent"] = UA
        http.request(req) do |res|
          if res.is_a?(Net::HTTPRedirection)
            raise "too many redirects from #{@url}" if hops >= MAX_REDIRECTS

            # Hugging Face answers with a relative Location, so the redirect is
            # resolved against the URL it came from rather than parsed alone.
            return request(range, URI.join(url, res["location"]).to_s, hops + 1, &block)
          end
          raise "#{uri.host} ignored Range and answered #{res.code}" unless res.code == "206"

          return block.call(res)
        end
      end
    end
  end

  class Local
    attr_reader :size

    def initialize(path)
      @path = path
      @size = File.size(path)
    end

    def read(offset, length)
      File.open(@path, "rb") { |f| f.pread(length, offset) }
    end

    def stream(offset, length)
      File.open(@path, "rb") do |f|
        f.seek(offset)
        remaining = length
        while remaining.positive?
          chunk = f.read([remaining, 1 << 20].min) or break

          remaining -= chunk.bytesize
          yield chunk
        end
      end
    end
  end
end
