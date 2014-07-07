require 'csv'
require 'json'
require 'marc'
require 'optparse'
require 'pp'

require_relative "../lib/csv2mrc.rb"

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
_xml       = false
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
  opts.on("-x", "--xml")                   { |xml| _xml = true }
  opts.on_tail("-h", "--help")             { puts _banner }
  opts.parse!
end

# exit and print banner unless all args are supplied
raise _banner unless _conf and _input and _output
raise "#{_banner}\n#{_file_err}" unless File.exists? _input and File.exists? _conf

# gather config elements
_csv2mrc = Csv2Mrc.new(_conf, field_delimiter: _f_delim)

# create marc writer 
_writer  = _xml ? MARC::XMLWriter.new(_output) : MARC::Writer.new(_output)

CSV.foreach(_input, { col_sep: _c_delim, headers: true }) do |csv|
  begin
    record = _csv2mrc.process_row csv

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
