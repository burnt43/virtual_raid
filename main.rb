#!/usr/local/bin/ruby
require 'singleton'

class Byte
  attr_reader :bit_string
  def initialize(bit_string); @bit_string = bit_string        end
  def to_s;                   @bit_string.to_s                end
  def newline?;               @bit_string.to_i(2) == 10       end
  def ==(other);              @bit_string == other.bit_string end
end

class JFile

  attr_reader :name, :data
  NEWLINE_ASCII_BYTE = Byte.new('00001010')

  def initialize(name,data=Array.new)
    @name = name
    @data = data
  end

  def self.find_or_create_by_filename(filename)
    data = FileSystem.instance.read_file(filename)
    data ? JFile.new(filename,data) : JFile.new(filename)
  end

  def self.open(filename)
    file = JFile.find_or_create_by_filename(filename)
    yield(file)
    file.save
  end

  def to_s
    @data.collect { |byte| byte.to_s }.pack('B*' * @data.length )
  end

  def puts(string)
    create_bytes_from_string(string + "\n").each { |byte| @data << byte }
  end

  def each_line
    to_s.split("\n").each { |e| yield(e) }
  end

  def save
    FileSystem.instance.write_file(self)
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
    @mount_hash      = Hash.new
    @file_bytes_hash = Hash.new
  end

  def mount_volume(mount_point,virtual_drive)
    if @mount_hash.has_key?(mount_point)
      raise "#{mount_point} is already mounted"
    else
      @mount_hash[mount_point] = virtual_drive
    end
  end

  def write_file(file)
    @file_bytes_hash[file.name] = Array.new
    virtual_drive = find_virtual_drive_by_filename(file.name)
    file.data.each { |byte|
      byte_written = virtual_drive.write_byte(byte)
      @file_bytes_hash[file.name].push(byte_written)
    }
  end

  def read_file(filename)
    return nil unless byte_indices = @file_bytes_hash[filename]
    virtual_drive = find_virtual_drive_by_filename(filename)
    virtual_drive.read_bytes(byte_indices)
  end

  private

  def find_virtual_drive_by_filename(filename)
    split_filename = filename.split('/')
    while split_filename.length > 0
      virtual_drive = @mount_hash[split_filename.join('/')]
      return virtual_drive if virtual_drive
      split_filename.pop
    end
    default_mount_point
  end

  def default_mount_point
    @mount_hash['/']
  end

end

class VirtualDrive

  def initialize(size_in_bytes)
    @bytes = Array.new
    size_in_bytes.times { @bytes.push(nil) }
  end

  def write_byte(byte)
    free_byte_index = find_first_free_byte
    @bytes[free_byte_index] = byte
    return free_byte_index
  end

  def read_bytes(byte_indices)
    @bytes.values_at(*byte_indices)
  end

  private

  def find_first_free_byte
    @bytes.each_index { |i| return i unless @bytes[i] }
    nil
  end

end

class PhysicalDrive

  def initialize(storage_size,block_size)
    @storage_size = storage_size
    @block_size   = block_size
  end

end

virtual_drive = VirtualDrive.new(1 * 2**10)
FileSystem.instance.mount_volume('/',virtual_drive)
JFile.open('/home/jcarson/foo.txt') { |f|
  f.puts 'James'
  f.puts 'Carson'
}
JFile.open('/home/jcarson/foo.txt') { |f|
  f.each_line { |line| puts line }
}
