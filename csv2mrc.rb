require 'csv'
require 'json'
require 'marc'
require 'optparse'
require 'pp'

# return true only if string is defined and not empty
def has_content?(string)
  !string.nil? and !string.empty?
end

$stderr.sync = true
 
# messages
_banner    = "csv2mrc -i input.tsv -c configuration.json -o output.mrc"
_file_err  = "Input (delimited) and configuration (json) must be existing files"

# files
_conf      = nil
_input     = nil
_output    = nil

# delimiters
_c_delim   = "\t" # column delimiter
_f_delim   = ";"  # delimiter for multiple values in a single column

# options
_blvl      = 'a'
_verbose   = false

# tracking variables
_count     = 0

# parse arguments
ARGV.options do |opts|
  opts.on("-b", "--blvl=val", String)      { |blvl| _blvl = blvl }
  opts.on("-c", "--conf=val", String)      { |conf| _conf = conf }
  opts.on("-d", "--delimiter=val", String) { |delimiter| _c_delim = delimiter }
  opts.on("-i", "--input=val", String)     { |input| _input = input }
  opts.on("-o", "--output=val", String)    { |output| _output = output }
  opts.on("-s", "--split=val", String)     { |split| _f_delim = split }
  opts.on("-v", "--verbose")               { |verbose| _verbose = true }
  opts.on_tail("-h", "--help")             { puts _banner }
  opts.parse!
end

# exit and print banner unless all args are supplied
raise _banner unless _conf and _input and _output
raise "#{_banner}\n#{_file_err}" unless File.exists? _input and File.exists? _conf

# __END__ # 4 TESTING

# gather config elements
_conf    = JSON.parse( IO.read( _conf ) )
_leader  = _conf["leader"]
_spec    = _conf["spec"]
_f_adds  = _conf["f_adds"]
_s_adds  = _conf["s_adds"]
_protect = _conf["protect"]
_replace = _conf["replace"]

# create marc writer 
_writer  = MARC::Writer.new _output

CSV.foreach(_input, { col_sep: _c_delim, headers: true }) do |csv|
  begin
    created = {} # use for existing tag lookup
    record = MARC::Record.new

    # leader and control fields
    ff = ' ' * 40
    _leader.each do |where, value|
      tag   = where[0..2]
      byte  = where[3..-1]
      if csv.has_key? value
        value = csv[value]
        next unless has_content? value
        value = value.strip
      end
      if byte =~ /../
        bytes = byte.split('..').map{ |d| Integer(d) }
        size = (bytes[1] - bytes[0]) + 1
        next unless value.size == size # must match length
        if tag == "000"
          record.leader[bytes[0]..bytes[1]] = value
        else
          ff[ bytes[0]..bytes[1] ] = value
        end
      else 
        if tag == "000"
          record.leader[byte.to_i] = value
        else
          ff[byte.to_i] = value
        end
      end
    end
    record.append( MARC::ControlField.new("008", ff) )

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
