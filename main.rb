#!/usr/local/bin/ruby
require 'singleton'
require 'logger'

$LOG = Logger.new('./raid.log')
$LOG.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end

class Byte
  attr_reader :bit_string
  def initialize(bit_string); @bit_string = bit_string        end
  def to_s;                   @bit_string.to_s                end
end

class JFile

  attr_reader :name, :data

  def initialize(name,data=Array.new)
    @name = name
    @data = data
  end

  def self.find_or_create_by_filename(filename)
    data = FileSystem.instance.read_file(filename)
    if data
      JFile.new(filename,data)
    else
      JFile.new(filename)
    end
  end

  def self.open(filename)
    $LOG.info "opening file: #{filename}"
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
    @mount_to_virtual_drive            = Hash.new
    @filename_to_byte_indices_on_drive = Hash.new
  end

  def mount_volume(mount_point,virtual_drive)
    $LOG.info "mounting volume #{virtual_drive} at #{mount_point}"
    if @mount_to_virtual_drive.has_key?(mount_point)
      raise "#{mount_point} is already mounted"
    else
      @mount_to_virtual_drive[mount_point] = virtual_drive
    end
  end

  def write_file(file)
    virtual_drive                                 = find_virtual_drive_by_filename(file.name)
    byte_indices_on_drive                         = @filename_to_byte_indices_on_drive[file.name] || Array.new
    @filename_to_byte_indices_on_drive[file.name] = Array.new if byte_indices_on_drive.empty?

    file.data.each_index { |i|
      if byte_index = byte_indices_on_drive[i]
        $LOG.info "Writing #{file.data[i]} at #{byte_index} on #{virtual_drive}"
        virtual_drive.write_byte(file.data[i],byte_index)
      else
        byte_written = virtual_drive.write_byte(file.data[i])
        $LOG.info "Writing #{file.data[i]} at #{byte_written} on #{virtual_drive}"
        @filename_to_byte_indices_on_drive[file.name].push(byte_written)
      end
    }
  end

  def read_file(filename)
    unless byte_indices = @filename_to_byte_indices_on_drive[filename]
      $LOG.info "Can't find #{filename} on drive"
      return nil
    end
    virtual_drive = find_virtual_drive_by_filename(filename)
    $LOG.info "#{filename} on #{virtual_drive} occupies the following indices #{byte_indices}"
    virtual_drive.read_bytes(byte_indices)
  end

  def debug_print_filename_to_byte_indices_on_drive
    @filename_to_byte_indices_on_drive.each { |filename,bytes| puts "Filename: #{filename} Bytes: #{bytes}" }
  end

  private

  def find_virtual_drive_by_filename(filename)
    split_filename = filename.split('/')
    while split_filename.length > 0
      virtual_drive = @mount_to_virtual_drive[split_filename.join('/')]
      return virtual_drive if virtual_drive
      split_filename.pop
    end
    default_mount_point
  end

  def default_mount_point
    @mount_to_virtual_drive['/']
  end

end

class VirtualDrive

  def initialize(size_in_bytes)
    $LOG.info "Creating #{self.class} of size #{size_in_bytes}"
    @bytes = Array.new
    size_in_bytes.times { @bytes.push(nil) }
  end

  def write_byte(byte,index=nil)
    if index
      @bytes[index] = byte
      index
    else
      free_byte_index = find_first_free_byte
      @bytes[free_byte_index] = byte
      free_byte_index
    end
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

$LOG.info '-'*80
$LOG.info 'Starting Program'

virtual_drive = VirtualDrive.new(1 * 2**10)
FileSystem.instance.mount_volume('/',virtual_drive)
JFile.open('foo.txt') { |f|
  f.puts '1234567'
}
JFile.open('bar.txt') { |f|
  f.puts 'JAMES'
}
JFile.open('foo.txt') { |f|
  f.puts '1234567'
}
FileSystem.instance.debug_print_filename_to_byte_indices_on_drive
