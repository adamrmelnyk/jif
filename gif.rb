class Gif
  # Header and LFD are a fixed size
  END_OF_HEADER_AND_LFD = 103
  GIF_TRAILER = "00111011" # 0x3B
  IMAGE_SEPARATOR = "00101100" # 0x2C
  EXTENSION_INTRODUCER = "00100001" # 0x21

  # Extension Labels
  GRAPHICS_CONTROL_EXTENSION_LABEL = "11111001"
  PLAIN_TEXT_LABEL = "00000001" # 0x01
  APPLICATION_EXTENSION_LABEL = "11111111" # 0xFF
  COMMENT_EXTENSION_LABEL = "11111110" # 0xFE

  attr_accessor :header, :logical_screen_descriptor, :canvas_width,
                :canvas_height, :packed_field, :background_color_index, :pixel_aspect_ratio,
                :global_color_table_flag, :color_resolution, :sort_flag,
                :size_of_global_color_table, :global_color_table, :tail

  def initialize(file_name)
    s = File.binread(file_name)
    bits = s.unpack("B*")[0]
    raise "Unable to parse File Gif must be GIF89a, found: #{b_to_h(bits[0..47])}" unless b_to_h(bits[0..47]) == "0x474946383961"

    @header = bits[0..47]
    @logical_screen_descriptor = bits[48..103]
    @canvas_width = logical_screen_descriptor[0..15]
    @canvas_height = logical_screen_descriptor[16..31]
    @packed_field = logical_screen_descriptor[32..39]
    @background_color_index = logical_screen_descriptor[40..47]
    @pixel_aspect_ratio = logical_screen_descriptor[48..74]
    @global_color_table_flag = packed_field[0]
    @color_resolution = packed_field[1..3]
    @sort_flag = packed_field[4]
    @size_of_global_color_table = packed_field[5..7]

    bits = bits[(END_OF_HEADER_AND_LFD + 1)..-1]
    if @global_color_table_flag == "1"
      @global_color_table = color_table_parser(bits, @size_of_global_color_table)
      bits = bits[@global_color_table.size..-1]
    end

    @tail = [] # An Array of hashes containing the remainder of the file broken into blocks
    until (bits[0..7] == GIF_TRAILER)
      if bits[0..7] == EXTENSION_INTRODUCER
        case bits[8..15]
        when GRAPHICS_CONTROL_EXTENSION_LABEL
          graphics_control_extension = graphics_control_extension_parser bits
          @tail.push graphics_control_extension
          bits = bits[graphics_control_extension[:total_block_size]..-1]
        when PLAIN_TEXT_LABEL, APPLICATION_EXTENSION_LABEL
          extension = extension_parser bits
          @tail.push extension
          bits = bits[extension[:total_block_size]..-1]
        when COMMENT_EXTENSION_LABEL
          comment_extension = comment_extension_parser bits
          @tail.push comment_extension
          bits = bits[comment_extension[:total_block_size]..-1]
        end
      elsif bits[0..7] == IMAGE_SEPARATOR
        image_descriptor = image_descriptor_parser bits
        bits = bits[image_descriptor[:total_block_size]..-1]
        local_color_table = nil
        if image_descriptor[:packed_field][:local_color_table_flag] == "1"
          local_color_table = color_table_parser(bits, image_descriptor[:packed_field][:size_of_local_color_table])
          bits = bits[local_color_table.size..-1]
        end
        image_data = image_data_parser bits
        data = {
          image_descriptor: image_descriptor,
          local_color_table: local_color_table,
          image_data: image_data,
        }
        @tail.push data

        bits = bits[data[:image_data][:total_block_size]..-1]
      else
        puts "Unknown block header: #{bits[0..7]}"
        raise "Error"
      end
    end
  end

  def table_size s
    (3 * 2**((s).to_i(2) + 1) * 8)
  end

  # Color table
  def color_table_parser(bits, size)
    color_table_size = table_size size
    bits[0..(color_table_size - 1)]
  end

  # Graphics control extension
  # 0xF9
  def graphics_control_extension_parser bits
    {
      extension_introducer: bits[0..7],
      label: bits[8..15],
      byte_size: bits[16..23],
      packed_field: {
        reserved_for_future_use: bits[24..26],
        disposal_method: bits[27..29],
        user_input_flag: bits[30],
        transparent_color_flag: bits[31]
      },
      delay_time: bits[32..47],
      transparent_colour_index: bits[48..55],
      block_terminator: bits[56..63],
      total_block_size: 64
    }
  end

  def graphics_control_extension_builder block
    s = block[:extension_introducer]
    s += block[:label]
    s += block[:byte_size]
    s += block[:packed_field][:reserved_for_future_use]
    s += block[:packed_field][:disposal_method]
    s += block[:packed_field][:user_input_flag]
    s += block[:packed_field][:transparent_color_flag]
    s += block[:delay_time]
    s += block[:transparent_colour_index]
    s += block[:block_terminator]
  end

  def sub_blocks_parser bits
    sub_blocks = []
    while (bits[0..7] != "00000000")
      # subtract 1 for index, add 8 to include first byte containing the size
      block_size = (8 * bits[0..7].to_i(2)) + 7
      sub_blocks.push bits[0..block_size]
      bits = bits[(block_size + 1)..-1]
    end
    sub_blocks.push bits[0..7]
  end

  # Extension
  # 0x01 || 0xFF
  def extension_parser bits
    data = {
      extension_introducer: bits[0..7],
      label: bits[8..15],
      skipped_block_length: bits[16..23],
      skipped_bits: bits[24..((8 * bits[16..23].to_i(2)) + 23)],
      sub_blocks: [],
      total_block_size: 0,
    }
    b_size = 24 + (8 * data[:skipped_block_length].to_i(2))
    bits = bits[b_size..-1]
    data[:sub_blocks] = sub_blocks_parser bits
    data[:total_block_size] = 24 + data[:skipped_bits].size + data[:sub_blocks].join.size
    data
  end

  def extension_builder block
    s = block[:extension_introducer]
    s += block[:label]
    s += block[:skipped_block_length]
    s += block[:skipped_bits]
    block[:sub_blocks].each { |sb| s += sb }
    s
  end

  # Comment Extension
  # 0xFE
  def comment_extension_parser bits
    data = {
      extension_introducer: bits[0..7],
      label: bits[8..15],
      sub_blocks: [],
      total_block_size: 0,
    }
    bits = bits[16..-1]
    data[:sub_blocks] = sub_blocks_parser bits
    data[:total_block_size] = 16 + data[:sub_blocks].join.size
    data
  end

  def comment_extension_builder block
    s = block[:extension_introducer]
    s += block[:label]
    block[:sub_blocks].each { |sb| s += sb }
    s
  end

  # Image Descriptor
  # 0x2C
  def image_descriptor_parser bits
    {
      image_separator: bits[0..15],
      image_left: bits[16..31],
      image_top: bits[32..47],
      image_width: bits[48..63],
      image_height: bits[64..71],
      packed_field: {
        local_color_table_flag: bits[72],
        interlace_flag: bits[73],
        sort_flag: bits[74],
        reserved_for_future_use: bits[75..76],
        size_of_local_color_table: bits[77..79],
      },
      total_block_size: 80,
    }
  end

  def image_descriptor_builder block
    s = block[:image_separator]
    s += block[:image_left]
    s += block[:image_top]
    s += block[:image_width]
    s += block[:image_height]
    s += block[:packed_field][:local_color_table_flag]
    s += block[:packed_field][:interlace_flag]
    s += block[:packed_field][:sort_flag]
    s += block[:packed_field][:reserved_for_future_use]
    s += block[:packed_field][:size_of_local_color_table]
  end

  def image_data_parser bits
    data = {
      lzw_minimum_code_size: bits[0..7],
      sub_blocks: [],
      total_block_size: 0,
    }
    bits = bits[8..-1]
    data[:sub_blocks] = sub_blocks_parser bits
    data[:total_block_size] = 8 + data[:sub_blocks].join.size
    data
  end

  def image_data_builder block
    s = block[:lzw_minimum_code_size]
    block[:sub_blocks].each { |sb| s += sb }
    s
  end

  def rebuild new_file_name
    # TODO: Create a gif using the gif data
  end

  # For Testing
  def b_to_h binary_string
    "0x%02x" % binary_string.to_i(2)
  end
end