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
  def ^(other)
    result = ""
    8.times { |i| result += (self.bit_string[i].to_i(2) ^ other.bit_string[i].to_i(2)).to_s }
    Byte.new(result)
  end
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

module VirtualDriveInterface
  def size_in_bytes
    raise 'implement'
  end
  def write_byte(byte,index=nil)
    raise 'implement'
  end
  def read_bytes(byte_indices)
    raise 'implement'
  end
end

module PhysicalDriveMappingInterface
  attr_reader :physical_drive, :byte_index
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

class Raid5VirtualDrive

  include VirtualDriveInterface

  class Stripe

    def initialize
      @data_blocks  = nil
      @parity_block = nil
    end

    def set_blocks(data_blocks,parity_block)
      @data_blocks  = data_blocks
      @parity_block = parity_block
    end

    def write_parity_block
      @parity_block.physical_drive_mappings.each_index { |i|
        xor_byte = @data_blocks.collect { |data_block| data_block.physical_drive_mappings[i].read_byte || Byte.new('00000000') }.reduce(:^)
        physical_drive_mapping = @parity_block.physical_drive_mappings[i]
        $LOG.info "Writing Parity Byte #{xor_byte.to_s} to #{physical_drive_mapping.physical_drive} at index #{physical_drive_mapping.byte_index}"
        physical_drive_mapping.write_byte(xor_byte)
      }
    end
  end

  class Block
    attr_reader :physical_drive_mappings
    def initialize(physical_drive_mappings)
      @physical_drive_mappings = physical_drive_mappings
    end
  end

  class PhysicalDriveMapping

    include PhysicalDriveMappingInterface

    def initialize(stripe,physical_drive,byte_index)
      @stripe         = stripe
      @physical_drive = physical_drive
      @byte_index     = byte_index
    end

  end
  
  def initialize(physical_drives)
    @physical_drives  = physical_drives
    @stripes          = Array.new

    number_of_stripes = @physical_drives.length
    number_of_drives  = @physical_drives.length
    block_size        = @physical_drives.first.storage_size / @physical_drives.length

    number_of_stripes.times { |stripe_id|
      stripe           = Stripe.new
      parity_block     = nil
      data_blocks      = Array.new
      byte_index_range = ((stripe_id * block_size)..(((stripe_id+1)*block_size)-1))
      @physical_drives.each_index { |physical_drive_index|
        physical_drive          = @physical_drives[physical_drive_index]
        physical_drive_mappings = Array.new
        byte_index_range.each { |byte_index| physical_drive_mappings.push(PhysicalDriveMapping.new(stripe,physical_drive,byte_index)) }
        block = Block.new(physical_drive_mappings)
        if physical_drive_index == (@physical_drives.length - (stripe_id+1))
          parity_block = block
        else
          data_blocks.push(block)
        end
      }
      stripe.set_blocks(data_blocks,parity_block)
      stripe.write_parity_block
      @stripes.push(stripe)
    }
    $LOG.info "Creating #{self.class} with #{@physical_drives.length} disks of size #{size_in_bytes} bytes"
  end

  def size_in_bytes
    (@physical_drives.length - 1) * @physical_drives.first.storage_size
  end
  
  def write_byte(byte,index=nil)
    raise 'implement'
  end

  def read_bytes(byte_indices)
    raise 'implement'
  end

end

class OneToOneVirtualDrive

  include VirtualDriveInterface

  class PhysicalDriveMapping

    include PhysicalDriveMappingInterface

    def initialize(physical_drive,byte_index)
      @physical_drive = physical_drive
      @byte_index     = byte_index
    end

  end

  def initialize(physical_drive)
    @physical_drive          = physical_drive
    @physical_drive_mappings = Array.new
    size_in_bytes.times { |index| @physical_drive_mappings.push(PhysicalDriveMapping.new(@physical_drive,index)) }
    $LOG.info "Creating #{self.class} with 1 disk of size #{size_in_bytes} bytes"
  end

  def size_in_bytes
    @physical_drive.storage_size
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

  def initialize(storage_size,state=:up)
    @storage_size = storage_size
    @bytes        = Array.new
    @state        = state
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

# 1 to 1
=begin
physical_drive = PhysicalDrive.new(1 * 2**10)
virtual_drive = OneToOneVirtualDrive.new(physical_drive)
FileSystem.instance.mount_volume('/',virtual_drive)
JFile.open('foo.txt') { |f| f.puts 'Hello 1' }
JFile.open('bar.txt') { |f| f.puts 'Hello 2' }
JFile.open('foo.txt') { |f| f.puts 'Hello 3' }
JFile.open('foo.txt') { |f| STDOUT.puts f.to_s }
=end

# Raid 5
physical_drives = Array.new
4.times { physical_drives.push(PhysicalDrive.new(1 * 2**6)) }
virtual_drive = Raid5VirtualDrive.new(physical_drives)

