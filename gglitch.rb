class Gif
  # Header and LFD are a fixed size
  END_OF_HEADER_AND_LFD = 103

  attr_accessor :header, :logical_screen_descriptor, :canvas_width,
                :canvas_height, :packed_field, :background_color_index, :pixel_aspect_ratio,
                :global_color_table_flag, :color_resolution, :sort_flag, :size_of_global_color_table

  def initialize(file_name)
    s = File.binread(file_name)
    bits = s.unpack("B*")[0]

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
    @global_color_table = set_global_color_table(bits) if @global_color_table_flag
    # TODO: Set the bit where we should start reading or set bits to just be the rest of bits.

    # TODO: Construct the rest of the file

  end

  def set_global_color_table bits
    gc_table_size = 3 * 2**((size_of_global_color_table).to_i(2)+1)
    global_color_table_end = (gc_table_size * 8) + END_OF_HEADER_AND_LFD
    global_color_table = bits[END_OF_HEADER_AND_LFD..global_color_table_end]
    end_of_headers = global_color_table_end

    # TODO: return the global color table
  end

  # Graphics control extension
  # 0xF9
  def graphics_control_extension_parser bits
    {
      extension_introducer: bits[0..7],
      graphic_control_label: bits[8..15],
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
    }
  end

  # Plain Text Extension
  # 0x01
  def plain_text_extension_parser bits
    {
      extension_introducer: bits[0..7],
      plain_text_label: bits[7..15],
      block_size_until_text: bits[16..23], # blocks to skip until actual text data
      sub_blocks: {},
    }
  end

  # Application Extension
  # 0xFF
  def application_extension_parser bits
    {
      extension_introducer: bits[0..7],
      application_extension_label: bits[7..15],
      application_block_length: bits[16..23], # We can ignore these bytes 
      sub_blocks: {},
    }
  end

  # Comment Extension
  # 0xFE
  def comment_extension_parser
    {
      extension_introducer: bits[0..7],
      comment_extension_label: bits[7..15],
      sub_blocks: {},
    }
  end

  # Image Descriptor
  # 0x2C
  def image_descriptor bits
    {
      image_seperator: bits[0..15],
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
    }
  end

  # Local color table
  # exactly the same as the global color table
  def color_table(bits, size)
    color_table = {
      # TODO: Fill the color table
    }
    return color_table
  end

  def image_data bits
    image_data = {
      lzw_minimum_code_size: bits[0..7],
      sub_blocks: [],
    }
    bits = bits[8..-1]

    while (bits[0..7] != "00000000")
      # subtract 1 for index, add 8 to include first byte containing the size
      block_size = (8 * bits[0..7].to_i(2)) + 7
      image_data[:sub_blocks].push bits[0..block_size]
      bits = bits[(block_size+ 1)..-1]
    end
    image_data[:sub_blocks].push bits # should just all be zeros
    return image_data
  end

  # Trailer, gif ends with 0x3B
  def b_to_h binary_string
    "0x%02x" % binary_string.to_i(2)
  end
end

## Optional Extensions
# 0x21
def which_extension byte
  # TODO: Create all the cases for each type of byte
end
