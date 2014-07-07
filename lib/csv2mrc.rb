require 'csv'
require 'json'
require 'marc'

class Csv2MrcLeaderValueError < RuntimeError ; end
class Csv2MrcLeaderByteLengthError < RuntimeError ; end
class Csv2MrcSpecError < RuntimeError ; end

class Csv2Mrc

  attr_reader :leader, :spec

  def initialize(config, options = {})
    @config = JSON.parse( IO.read(config), symbolize_names: false )

    @options = {
      field_delimiter: ",",
    }.merge! options

    @leader = @config["leader"]
    @spec    = @config["spec"]
  end

  def process_control_fields(record, row)
    fixed_field = ' ' * 40 # start with empty fixed field positions
    leader.each do |where, value|
      tag, byte = where[0..2], where[3..-1] # first three characters are tag, rest are byte positions
      value = check_csv_value(row, value) # if value matches a csv header use the csv value
    
      if byte_is_range? byte
        bytes = get_bytes byte # array of two elements, position 1 and 2 (i.e. date1, date2)
        size = (bytes[1] - bytes[0]) + 1 # length value should be to be consistent
        raise Csv2MrcLeaderByteLengthError, "CSV value for byte range #{byte} is incorrect length" unless value.size == size

        if leader_tag? tag
          record.leader[bytes[0]..bytes[1]] = value
        else
          fixed_field[ bytes[0]..bytes[1] ] = value
        end
      else 
        if leader_tag? tag
          record.leader[byte.to_i] = value
        else
          fixed_field[byte.to_i] = value
        end
      end
    end
    record.append( MARC::ControlField.new("008", fixed_field) )
    record
  end

  def process_row(row)
    record = MARC::Record.new

    # values from csv can be injected into 008 so pass it
    process_control_fields record, row
    process_variable_fields record, row
    record
  end

  def process_variable_fields(record, row)
    fields_created = {}
    spec.each do |csv_mapper| # each mapper is a {} with key that should match a row column
      csv_mapper.each do |column, rules|
        raise Csv2MrcSpecError, "Invalid spec key #{column} not found in headers" unless row.has_key? column
        field_value = row[column]
        next unless has_content? field_value # nothing to do if empty
        if rules["join"]
          if fields_created.include? rules["tag"]
            datafield = record[rules["tag"]]
            subfield = datafield.find { |s| s.code == rules["sub"] }
            if subfield
              subfield.value += "#{rules["prepend"]}#{field_value}#{rules["append"]}"
            else
              field_value = "#{rules["prepend"]}#{field_value}".strip
              field_value += rules["append"] unless field_value[-1] == rules["append"]
              datafield.append( MARC::Subfield.new(rules["sub"], field_value) )
            end
          else
            field_value = "#{rules["prepend"]}#{field_value}".strip
            field_value += rules["append"] unless field_value[-1] == rules["append"]
            df = MARC::DataField.new(rules["tag"], rules["ind1"], rules["ind2"], [rules["sub"], field_value])
            record << df unless record.fields.find { |f| f == df }
            fields_created[rules["tag"]] = true
          end
        else
          # split field_value
        end
      end
    end
    record
  end

  private

  def byte_is_range?(byte)
    byte =~ /../
  end

  def check_csv_value(row, value)
    if row.has_key? value
      raise Csv2MrcLeaderValueError, "CSV header #{value} contains no data for leader" unless has_content? row[value]
      value = row[value].strip
    end
    value
  end

  def get_bytes(byte_range)
    byte_range.split('..').map{ |d| Integer(d) }
  end

  def leader_tag?(tag)
    tag == "000"
  end

  # return true only if string is defined and not empty
  def has_content?(string)
    !string.nil? and !string.empty?
  end

end

__END__

# gather config elements
_conf    = JSON.parse( IO.read( _conf ) )
_leader  = _conf["leader"]
_spec    = _conf["spec"]
_f_adds  = _conf["f_adds"]
_s_adds  = _conf["s_adds"]
_protect = _conf["protect"]
_replace = _conf["replace"]

# create marc writer 
_writer  = _xml ? MARC::XMLWriter.new(_output) : MARC::Writer.new(_output)

CSV.foreach(_input, { col_sep: _c_delim, headers: true }) do |csv|
  begin
    created = {} # use for existing tag lookup
    record = MARC::Record.new

    # variable fields
    _spec.each do |s|
      s.each do |field, spec|
        f = csv[field]
        if has_content? f
          if spec["join"]
            if created.include? spec["tag"]
              datafield = record[spec["tag"]]
              subfield = datafield.find { |s| s.code == spec["sub"] }
              if subfield
                subfield.value += "#{spec["prepend"]}#{f}#{spec["append"]}"
              else
                f = "#{spec["prepend"]}#{f}".strip
                f += spec["append"] unless f[-1] == spec["append"]
                datafield.append( MARC::Subfield.new(spec["sub"], f) )
              end
            else
              f = "#{spec["prepend"]}#{f}".strip
              f += spec["append"] unless f[-1] == spec["append"]
              df = MARC::DataField.new(spec["tag"], spec["ind1"], spec["ind2"], [spec["sub"], f])
              record << df unless record.fields.find { |f| f == df }
              created[spec["tag"]] = true
            end
          else
            values = f.split(_f_delim)
            values.each do |value|
              value = "#{spec["prepend"]}#{value}".strip
              value += spec["append"] unless value[-1] == spec["append"]

              tag = spec["tag"] # DO NOT MODIFY SPEC
              _protect.each do |protect_tag, use_tag|
                if tag == protect_tag and record.fields.find { |f| f.tag == protect_tag }
                  tag = use_tag
                end
              end

              df = MARC::DataField.new(tag, spec["ind1"], spec["ind2"], [spec["sub"], value])
              record << df unless record.fields.find { |f| f == df }
            end
          end
        end
      end
    end

    # do the field adds
    _f_adds.each do |field_to_add|
      df = MARC::DataField.new(field_to_add["tag"], field_to_add["ind1"], field_to_add["ind2"])
      field_to_add["subfields"].each do |subfield|
        df.append( MARC::Subfield.new(subfield[0], subfield[1]) )
      end
      record << df
    end

    # do the subfield adds
    _s_adds.each do |subfield_to_add|
      dfs = record.fields.find_all { |f| f.tag == subfield_to_add["tag"] }
      dfs.each do |df|
        subfield_to_add["subfields"].each do |subfield|
          df.append( MARC::Subfield.new(subfield[0], subfield[1]) )
        end
      end
    end

    # do replacements
    _replace.each do |replacement_tag, replacement_data|
      fields = record.fields.find_all { |f| f.tag == replacement_tag }
      fields.each do |f|
        replacement_data.each do |code, value|
          subfield = f.subfields.find { |s| s.code == code }
          subfield.value = value if subfield
        end
      end
    end 

    # fix the title field if there's an author/s
    author = record.fields.find { |f| f.tag == "100" }
    if author
      a     = author["a"].to_s
      a     = "#{a.chop.split(",").reverse.join(" ")}".strip
      additionals = record.fields.find_all { |f| f.tag == "700" }
      unless additionals.size > 3
        additionals.each do |aa|
          aa  = aa["a"].to_s
          aa  = "#{aa.chop.split(",").reverse.join(" ")}".strip
          a   += "; #{aa}"
        end
      end
      a += "."
      
      t     = "#{record["245"]["a"].to_s.chop} /"
      tsa   = record["245"].subfields.find { |f| f.code == "a" }
      tsa.value = t
      title = record["245"]
      tsc   = MARC::Subfield.new('c', "by #{a}")
      title.append(tsc)

      # fix indicators
      title.indicator1 = "1"
      case title["a"]
      when /^The / 
        title.indicator2 = "4"
      when /^An /
        title.indicator2 = "3"
      when /^A /  
        title.indicator2 = "2"
      else
        title.indicator2 = "0"
      end
    end

    # never allow duplicate 300 fields
    item_types = record.fields.find_all { |f| f.tag == "300" }
    record.fields.delete item_types[-1] if item_types.size > 1

    # sort the tags
    record.fields.sort_by! { |f| f.tag }
    
    # write to file
    _writer.write record

    # finish up
    puts record if _verbose
    _count += 1
  rescue Exception => ex
    puts "FAILED RECORD\t#{csv}"
  end
end

puts "RECORDS PROCESSED\t#{_count.to_s}" if _verbose

__END__
