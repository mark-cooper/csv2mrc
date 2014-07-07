require 'spec_helper'
require 'pp'

describe "Initializing Csv2Mrc" do

  it "should fail when the config file is not json" do
    expect{ Csv2Mrc.new("spec/example.tsv") }.to raise_error( JSON::ParserError )
  end

  it "should work when the input file is json" do
    expect{ Csv2Mrc.new("spec/example.json") }.not_to raise_error
  end

  it "should define the leader specification" do
    c2m = Csv2Mrc.new("spec/example.json")
    expect(c2m.leader).not_to be_nil
    expect(c2m.leader).to have_key "0005" 
  end

  # other initializers ...

end

describe "Processing fields from CSV" do

  before :each do
    @c2m    = Csv2Mrc.new("spec/example.json", field_delimiter: ";")
    @csv      = CSV.new( IO.read("spec/example.tsv"), headers: true, col_sep: "\t" )
    @record = MARC::Record.new
    @row  = @csv.shift
  end

  context "control fields" do

    it "fails if the leader uses an empty value" do
      @row["year"] = ""
      expect{ @c2m.process_row(@row) }.to raise_error( Csv2MrcLeaderValueError )
    end

    it "fails if the value is incorrect length for byte range" do
      @row["year"] = "20"
      expect{ @c2m.process_control_fields(@record, @row) }.to raise_error( Csv2MrcLeaderByteLengthError )
    end

    it "creates the leader correctly" do
      @c2m.process_control_fields @record, @row
      expect(@record.leader[5]).to eq "n"
      expect(@record.leader[6]).to eq "m"
      expect(@record.leader[7]).to eq "a"
      expect(@record["008"].value[7..10]).to eq "2014"
      expect(@record["008"].value[35..37]).to eq "eng"
    end

  end

  context "variable fields" do

    it "joins fields if join specified" do
      @c2m.process_variable_fields @record, @row
      expect(@record["260"]["b"] ).to eq "Example Inc.,"
      expect(@record["260"]["c"] ).to eq "2014."
      expect(@record["773"].to_s).to eq "773 0  $t IWRDB Journal. $g Vol. 1. No. 1. 2014. p. 1-5. $l 1 $q p. 1-5 $v 1 "
    end

    it "makes join fields unique" do
      @c2m.process_variable_fields @record, @row
      expect(@record.fields.find_all { |f| f.tag == "260" }.size).to eq 1
      expect(@record.fields.find_all { |f| f.tag == "773" }.size).to eq 1
    end

  end

  context "adding fields" do

    it "appends the fields to the record" do
      @c2m.process_field_adds @record
      expect(@record["022"]["a"] ).to eq "1234-5678"
      expect(@record["040"]["c"] ).to eq "test"
      expect(@record["041"]["a"] ).to eq "eng"
    end

    it "protects against duplicate field tags when specified" do
      @c2m.process_variable_fields @record, @row
      expect(@record.fields.find_all { |f| f.tag == "100" }.size).to eq 1
      expect(@record.fields.find_all { |f| f.tag == "700" }.size).to eq 1
    end

  end

  context "adding subfields" do

    it "does nothing if there is not a datafield to append to" do
      expect{ @c2m.process_subfield_adds(@record) }.not_to raise_error
    end

    it "appends the subfields to an existing datafield" do
      @c2m.process_variable_fields @record, @row
      @c2m.process_subfield_adds @record
      expect(@record["856"]["y"] ).to eq "Link to article."
    end
  
  end

  context "replacements" do
  
    it "replaces existing values" do
      @c2m.process_variable_fields @record, @row
      expect(@record["260"]["b"] ).to eq "Example Inc.,"
      @c2m.process_replacements @record
      expect(@record["260"]["b"] ).to eq "Override publisher,"
    end

  end

  context "author is present" do

    it "fixes the author order and updates title indicators" do
      @c2m.process_variable_fields @record, @row
      @c2m.process_author_title @record
      expect(@record["245"].indicator1.to_i ).to eq 1
    end

  end

  context "processing a row" do

    it "does not raise an error" do
      expect { @c2m.process_row @row }.not_to raise_error
    end

    it "returns the assembled marc record" do
      record = @c2m.process_row @row
      expect(record.fields.size).to eq 14
    end

  end

end
