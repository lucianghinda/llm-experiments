#!/usr/bin/env ruby
# frozen_string_literal: true

# Downloads the one GloVe table this experiment needs.
#
#   ruby word-vector-arithmetic/scripts/fetch.rb
#   ruby word-vector-arithmetic/scripts/fetch.rb --force
#   GLOVE_ZIP=/path/to/glove.6B.zip ruby word-vector-arithmetic/scripts/fetch.rb
#
# ONLY THE 50d ENTRY CROSSES THE NETWORK. glove.6B.zip is 822MB and holds four
# tables; this experiment uses one of them, 163MB uncompressed. Both mirrors
# answer HTTP Range with 206, so this reads the zip end-of-central-directory,
# looks up the entry, and asks for exactly its compressed bytes -- about 70MB
# instead of 822MB. The saving is the point: a fetch step nobody minds running
# is a fetch step that keeps the data out of the repository.
#
# THE CHECKSUM IS OF THE EXTRACTED TABLE, NOT THE ZIP. The two mirrors ship
# archives that differ by 140 bytes (Stanford 862,182,613; Hugging Face
# 862,182,753) -- rezipped, not recompiled. Pinning a zip hash would make the
# mirror a false positive. The table inside is what the experiment reads, so the
# table is what gets pinned, and the zip's own CRC32 is checked on the way past.

require "digest"
require "fileutils"
require "zlib"
require_relative "lib/byte_source"

SOURCE = "https://nlp.stanford.edu/data/glove.6B.zip"
MIRROR = "https://huggingface.co/stanfordnlp/glove/resolve/main/glove.6B.zip"
ENTRY = "glove.6B.50d.txt"

# Recorded by the first successful run and pinned here afterwards. Until it is
# set, this script prints the hash it saw instead of comparing.
EXPECTED_SHA256 = "d8f717f8dd4b545cb7f418ef9f3d0c3e6e68a6f48b97d32f8b7aae40cb31f96f"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
DATA_DIR = File.join(EXPERIMENT_DIR, "data")
TARGET = File.join(DATA_DIR, ENTRY)

EOCD_SIG = "PK\x05\x06".b
CD_SIG = "PK\x01\x02".b
LFH_SIG = "PK\x03\x04".b
DEFLATE = 8
STORED = 0

def find_entry(reader, name)
  tail_length = [65_557, reader.size].min
  tail = reader.read(reader.size - tail_length, tail_length)
  eocd = tail.rindex(EOCD_SIG) or raise "no zip end-of-central-directory in the last #{tail_length} bytes"

  cd_size, cd_offset = tail[eocd + 12, 8].unpack("VV")
  raise "zip64 archive; this reader handles the classic format only" if cd_offset == 0xFFFFFFFF

  cd = reader.read(cd_offset, cd_size)
  pos = 0
  while (pos = cd.index(CD_SIG, pos))
    method = cd[pos + 10, 2].unpack1("v")
    crc, csize, usize, fnlen, extralen, commentlen = cd[pos + 16, 18].unpack("VVVvvv")
    local_offset = cd[pos + 42, 4].unpack1("V")
    filename = cd[pos + 46, fnlen]

    if filename == name
      return { name: filename, method: method, crc: crc, csize: csize,
               usize: usize, local_offset: local_offset }
    end

    pos += 46 + fnlen + extralen + commentlen
  end
  nil
end

def extract(reader, entry, target)
  # The central directory's extra field and the local header's need not match,
  # so the data offset is read from the local header rather than assumed.
  lfh = reader.read(entry[:local_offset], 30)
  raise "no local file header at #{entry[:local_offset]}" unless lfh.start_with?(LFH_SIG)

  fnlen, extralen = lfh[26, 4].unpack("vv")
  data_offset = entry[:local_offset] + 30 + fnlen + extralen

  case entry[:method]
  when DEFLATE, STORED then nil
  else raise "entry #{entry[:name]} uses compression method #{entry[:method]}"
  end

  inflate = entry[:method] == DEFLATE ? Zlib::Inflate.new(-Zlib::MAX_WBITS) : nil
  sha = Digest::SHA256.new
  crc = 0
  written = 0
  milestone = 0
  tmp = "#{target}.part"

  FileUtils.mkdir_p(File.dirname(target))
  File.open(tmp, "wb") do |out|
    consume = lambda do |piece|
      next if piece.nil? || piece.empty?

      out << piece
      sha << piece
      crc = Zlib.crc32(piece, crc)
      written += piece.bytesize
      if written - milestone >= 32 << 20
        milestone = written
        percent = (100.0 * written / entry[:usize]).round
        warn format("  %3d%%  %d MB", percent, written >> 20)
      end
    end

    reader.stream(data_offset, entry[:csize]) do |chunk|
      consume.call(inflate ? inflate.inflate(chunk) : chunk)
    end
    consume.call(inflate&.finish)
  end
  inflate&.close

  raise "size mismatch: got #{written}, zip says #{entry[:usize]}" unless written == entry[:usize]
  raise "CRC32 mismatch: got #{crc}, zip says #{entry[:crc]}" unless crc == entry[:crc]

  File.rename(tmp, target)
  sha.hexdigest
end

force = ARGV.include?("--force")
local_zip = ENV["GLOVE_ZIP"]

if File.exist?(TARGET) && !force
  digest = Digest::SHA256.file(TARGET).hexdigest
  if EXPECTED_SHA256.nil? || digest == EXPECTED_SHA256
    warn "#{ENTRY} already present (#{File.size(TARGET) >> 20} MB, sha256 #{digest[0, 12]})"
    exit 0
  end
  warn "present copy has sha256 #{digest}, expected #{EXPECTED_SHA256}; re-fetching"
end

reader, origin =
  if local_zip
    abort "GLOVE_ZIP=#{local_zip} does not exist" unless File.exist?(local_zip)

    [ByteSource::Local.new(local_zip), local_zip]
  else
    warn "reading zip directory from #{SOURCE}"
    begin
      [ByteSource::Http.new(SOURCE), SOURCE]
    rescue StandardError => e
      warn "  #{e.class}: #{e.message}"
      warn "falling back to #{MIRROR}"
      [ByteSource::Http.new(MIRROR), MIRROR]
    end
  end

entry = find_entry(reader, ENTRY) or abort "#{ENTRY} is not in #{origin}"
warn format("%s: %d MB compressed, %d MB extracted (%.1f%% of the %d MB archive)",
            entry[:name], entry[:csize] >> 20, entry[:usize] >> 20,
            100.0 * entry[:csize] / reader.size, reader.size >> 20)

digest = extract(reader, entry, TARGET)

if EXPECTED_SHA256 && digest != EXPECTED_SHA256
  File.unlink(TARGET)
  abort "sha256 #{digest} does not match the pinned #{EXPECTED_SHA256}; removed the download"
end

File.write(File.join(DATA_DIR, "CHECKSUM"), <<~TEXT)
  #{digest}  #{ENTRY}
  source: #{origin}
  entry:  #{ENTRY} (#{entry[:usize]} bytes, crc32 #{format("%08x", entry[:crc])})
TEXT

warn "wrote #{TARGET} (#{File.size(TARGET) >> 20} MB)"
warn "sha256 #{digest}"
warn "pin it: set EXPECTED_SHA256 in #{__FILE__.sub("#{Dir.pwd}/", "")}" if EXPECTED_SHA256.nil?
