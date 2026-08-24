#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads GPT-2's token embedding matrix and its tokenizer vocabulary.
#
#   ruby word-vector-arithmetic/scripts/fetch_gpt2.rb
#   ruby word-vector-arithmetic/scripts/fetch_gpt2.rb --force
#
# WHY GPT-2 AT ALL. The talk explains GPT-3's embedding matrix and then
# demonstrates on GloVe, which is a different object trained on a different
# objective. GPT-2 is the largest embedding matrix that is openly published,
# small enough to hold in Ruby, and actually part of a language model. Running
# the same words through both is the only way to find out how much of the GloVe
# result was about embeddings in general and how much was about GloVe.
#
# ONE TENSOR, NOT THE MODEL. safetensors is an 8-byte little-endian header
# length, then a JSON header giving every tensor a dtype, a shape and a byte
# range, then one flat buffer. So the file is randomly addressable: this reads
# the header, looks up wte.weight, and asks for exactly its 147MB out of the
# 548MB file. The other 160 tensors are never transferred.
#
# THE BYTES ARE STORED RAW. 50257 x 768 float32 stays float32 on disk. Writing
# it as text would triple the size for no gain, and Ruby unpacks float32
# natively with "e*".

require "digest"
require "fileutils"
require "json"
require "net/http"
require "uri"
require_relative "lib/byte_source"

REPO = "https://huggingface.co/openai-community/gpt2/resolve/main"
SAFETENSORS = "#{REPO}/model.safetensors"
VOCAB = "#{REPO}/vocab.json"
TENSOR = "wte.weight"

# Recorded by the first successful run and pinned here afterwards.
EXPECTED_TENSOR_SHA256 = "e182e433b37dbdb47448e0413c840edf6965113c1fc8048c63b69795d8cf875a"
EXPECTED_VOCAB_SHA256 = "196139668be63f3b5d6574427317ae82f612a97c5d1cdaf36ed2256dbf636783"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
DATA_DIR = File.join(EXPERIMENT_DIR, "data")
TENSOR_PATH = File.join(DATA_DIR, "gpt2-wte.f32")
META_PATH = File.join(DATA_DIR, "gpt2-wte.meta.json")
VOCAB_PATH = File.join(DATA_DIR, "gpt2-vocab.json")

def safetensors_header(source)
  header_length = source.read(0, 8).unpack1("Q<")
  raise "implausible safetensors header length #{header_length}" if header_length > 100 << 20

  [JSON.parse(source.read(8, header_length)), 8 + header_length]
end

def download(url, path)
  uri = URI(url)
  body = fetch_body(uri)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, body)
  Digest::SHA256.hexdigest(body)
end

def fetch_body(uri, hops = 0)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    res = http.request(Net::HTTP::Get.new(uri))
    if res.is_a?(Net::HTTPRedirection)
      raise "too many redirects for #{uri}" if hops >= 5

      return fetch_body(URI.join(uri.to_s, res["location"]), hops + 1)
    end
    raise "#{uri.host} answered #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    return res.body
  end
end

force = ARGV.include?("--force")

if File.exist?(TENSOR_PATH) && File.exist?(VOCAB_PATH) && !force
  tensor_digest = Digest::SHA256.file(TENSOR_PATH).hexdigest
  vocab_digest = Digest::SHA256.file(VOCAB_PATH).hexdigest
  pinned = [EXPECTED_TENSOR_SHA256, EXPECTED_VOCAB_SHA256].compact
  if pinned.empty? || (tensor_digest == EXPECTED_TENSOR_SHA256 && vocab_digest == EXPECTED_VOCAB_SHA256)
    warn "gpt2 embeddings already present (#{File.size(TENSOR_PATH) >> 20} MB, sha256 #{tensor_digest[0, 12]})"
    exit 0
  end
  warn "present copy does not match the pinned hashes; re-fetching"
end

warn "reading safetensors header from #{SAFETENSORS}"
source = ByteSource::Http.new(SAFETENSORS)
header, data_start = safetensors_header(source)
entry = header[TENSOR] or abort "#{TENSOR} is not in the file (#{header.keys.length} tensors)"
abort "#{TENSOR} is #{entry["dtype"]}; this reader handles F32" unless entry["dtype"] == "F32"

from, to = entry["data_offsets"]
length = to - from
rows, columns = entry["shape"]
expected = rows * columns * 4
abort "shape #{entry["shape"].inspect} needs #{expected} bytes, header says #{length}" unless expected == length

warn format("%s: %s float32, %d MB of a %d MB file (%.1f%%)",
            TENSOR, entry["shape"].inspect, length >> 20, source.size >> 20,
            100.0 * length / source.size)

FileUtils.mkdir_p(DATA_DIR)
sha = Digest::SHA256.new
written = 0
milestone = 0
tmp = "#{TENSOR_PATH}.part"
File.open(tmp, "wb") do |out|
  source.stream(data_start + from, length) do |chunk|
    out << chunk
    sha << chunk
    written += chunk.bytesize
    if written - milestone >= 32 << 20
      milestone = written
      warn format("  %3d%%  %d MB", (100.0 * written / length).round, written >> 20)
    end
  end
end
abort "short read: #{written} of #{length} bytes" unless written == length

File.rename(tmp, TENSOR_PATH)
tensor_digest = sha.hexdigest

if EXPECTED_TENSOR_SHA256 && tensor_digest != EXPECTED_TENSOR_SHA256
  File.unlink(TENSOR_PATH)
  abort "tensor sha256 #{tensor_digest} does not match the pinned value; removed the download"
end

warn "downloading tokenizer vocabulary"
vocab_digest = download(VOCAB, VOCAB_PATH)
if EXPECTED_VOCAB_SHA256 && vocab_digest != EXPECTED_VOCAB_SHA256
  File.unlink(VOCAB_PATH)
  abort "vocab sha256 #{vocab_digest} does not match the pinned value; removed the download"
end

File.write(META_PATH, "#{JSON.pretty_generate({
  "source" => SAFETENSORS,
  "tensor" => TENSOR,
  "dtype" => entry["dtype"],
  "shape" => entry["shape"],
  "tensor_sha256" => tensor_digest,
  "vocab_source" => VOCAB,
  "vocab_sha256" => vocab_digest
})}\n")

warn "wrote #{TENSOR_PATH} (#{rows} x #{columns})"
warn "sha256 tensor #{tensor_digest}"
warn "sha256 vocab  #{vocab_digest}"
warn "pin them: set EXPECTED_TENSOR_SHA256 and EXPECTED_VOCAB_SHA256" unless EXPECTED_TENSOR_SHA256
