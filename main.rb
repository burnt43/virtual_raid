#!/usr/local/bin/ruby
require 'singleton'

class Byte
  def initialize(bit_string); @bit_string = bit_string end
  def to_s;                   @bit_string.to_s         end
end

class JFile

  def initialize
    @data = Array.new
  end

  def puts(string)
    create_bytes_from_string(string + "\n").each { |byte| @data << byte }
    STDOUT.puts "@data is now: #{@data}"
  end

  def save
  end

  private

  def create_bytes_from_string(string)
    result     = Array.new
    bit_buffer = Array.new
    string.unpack('B*').first.each_char { |char|
        bit_buffer << char
        if bit_buffer.length == 8
          result << Byte.new(bit_buffer.join)
          bit_buffer = Array.new
        end
    }
    result
  end

end

class FileSystem

  include Singleton

  def initialize
  end

end

class VirtualDrive
end

class PhysicalDrive

  def initialize(storage_size,block_size)
    @storage_size = storage_size
    @block_size   = block_size
  end

end

x = JFile.new
x.puts('ABCD')
