class Dockly::TarDiff
  include Dockly::Util::Logger::Mixin

  # Tar header format for a ustar tar
  HEADER_UNPACK_FORMAT  = "Z100A8A8A8A12A12A8aZ100A6A2Z32Z32A8A8Z155"

  logger_prefix '[dockly tar_diff]'

  attr_reader :base, :output, :target, :base_enum, :target_enum

  def initialize(base, target, output)
    @base, @target, @output = base, target, output

    @base_enum = to_enum(:read_header, base)
    @target_enum = to_enum(:read_header, target)
  end

  def write_tar_section(output, header, size, remainder, input)
    output.write(header)
    quick_write(output, input, size)
    output.write("\0" * remainder)
  end

  def quick_write(output, input, size)
    while size > 0
      bread = input.read([size, 4096].min)
      output.write(bread)
      size -= bread.to_s.size
    end
  end

  def read_header(io)
    loop do
      # Tar header is 512 bytes large
      data = io.read(512)
      fields = data.unpack(HEADER_UNPACK_FORMAT)
      name = fields[0]
      size = fields[4].oct
      mtime = fields[5].oct
      prefix = fields[15]

      empty = (data == "\0" * 512)
      remainder = (512 - (size % 512)) % 512

      yield data, name, prefix, mtime, size, remainder, empty

      io.read(remainder)
    end
  end

  def process
    debug "Started processing tar diff"
    loop do
      begin
        target_header, target_name,  \
        target_prefix, target_mtime,  \
        target_size, target_remainder, \
        target_empty                    = target_enum.peek
      rescue StopIteration
        debug "Finished target file"
        break
      end

      if target_empty
        debug "End of target file/Empty"
        break
      end

      begin
        _, base_name, base_prefix, base_mtime, base_size, _, base_empty = base_enum.peek
      rescue StopIteration
        write_tar_section(output, target_header, target_size, target_remainder, target)
        target_enum.next
        next
      end

      if base_empty
        write_tar_section(output, target_header, target_size, target_remainder, target)
        target_enum.next
        next
      end

      target_full_name = File.join(target_prefix, target_name)
      base_full_name = File.join(base_prefix, base_name)

      target_full_name = target_full_name[1..-1] if target_full_name[0] == '/'
      base_full_name = base_full_name[1..-1] if base_full_name[0] == '/'

      if (target_full_name < base_full_name)
        write_tar_section(output, target_header, target_size, target_remainder, target)
        target_enum.next
      elsif (base_full_name < target_full_name)
        base.read(base_size)
        base_enum.next
      elsif (target_mtime != base_mtime) || (target_size != base_size)
        write_tar_section(output, target_header, target_size, target_remainder, target)
        target_enum.next
      else
        target.read(target_size)
        target_enum.next
        base.read(base_size)
        base_enum.next
      end
    end
  end
end
