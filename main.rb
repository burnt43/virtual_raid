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
    $LOG.info "saving file: #{@name}"
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
  
class PhysicalDriveMapping
  attr_reader :physical_drive, :byte_index
  def initialize(physical_drive,byte_index)
    @physical_drive = physical_drive
    @byte_index     = byte_index
  end
  def write_byte(byte)
    @physical_drive.write_byte(byte,@byte_index)
  end
  def read_byte
    @physical_drive.read_byte(@byte_index)
  end
  def free?
    @physical_drive.byte_index_free?(@byte_index)
  end
end

module OneToOne
  def raid_name
    'OneToOne'
  end
  def size_in_bytes
    @physical_drives.first.storage_size
  end
  def initialize_physical_drive_mappings
    size_in_bytes.times { |index|
      @physical_drive_mappings.push(PhysicalDriveMapping.new(@physical_drives.first,index))
    }
  end
end

class VirtualDrive

  include OneToOne

  def initialize(physical_drives)
    @physical_drives              = physical_drives
    @physical_drive_mappings      = Array.new
    initialize_physical_drive_mappings
    $LOG.info "Creating #{self.class} of type #{raid_name} with #{physical_drives.length} disk(s) of size #{size_in_bytes} bytes"
  end

  def write_byte(byte,index=nil)
    if index
      @physical_drive_mappings[index].write_byte(byte)
      index
    else
      physical_drive_mapping = find_first_free_physical_drive_mapping
      physical_drive_mapping.write_byte(byte)
      physical_drive_mapping.byte_index
    end
  end

  def read_bytes(byte_indices)
    @physical_drive_mappings.values_at(*byte_indices).collect { |physical_drive_mapping| physical_drive_mapping.read_byte }
  end

  private

  def find_first_free_physical_drive_mapping
    @physical_drive_mappings.find { |physical_drive_mapping| physical_drive_mapping.free? }
  end

end

class PhysicalDrive

  attr_reader :storage_size

  def initialize(storage_size)
    @storage_size = storage_size
    @bytes        = Array.new
    storage_size.times { @bytes.push(nil) }
  end

  def write_byte(byte,index)
    @bytes[index] = byte
  end

  def read_byte(index)
    @bytes[index]
  end

  def byte_index_free?(index)
    @bytes[index].nil?
  end

end

$LOG.info '-'*80
$LOG.info 'Starting Program'

physical_drives = Array.new
1.times { physical_drives.push(PhysicalDrive.new(1 * 2**10)) }
virtual_drive = VirtualDrive.new(physical_drives)
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
