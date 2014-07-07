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
  end

  context "control fields" do

    it "fails if the leader uses an empty value" do
      row  = @csv.shift
      row["year"] = ""
      expect{ @c2m.process_row(row) }.to raise_error( Csv2MrcLeaderValueError )
    end

    it "fails if the value is incorrect length for byte range" do
      row  = @csv.shift
      row["year"] = "20"
      expect{ @c2m.process_control_fields(@record, row) }.to raise_error( Csv2MrcLeaderByteLengthError )
    end

    it "creates the leader correctly" do
      row  = @csv.shift
      @c2m.process_control_fields @record, row
      expect(@record.leader[5]).to eq "n"
      expect(@record.leader[6]).to eq "m"
      expect(@record.leader[7]).to eq "a"
      expect(@record["008"].value[7..10]).to eq "2014"
      expect(@record["008"].value[35..37]).to eq "eng"
    end

  end

  context "variable fields" do

    it "joins fields if join specified" do
      row = @csv.shift
      @c2m.process_variable_fields @record, row
      expect(@record["260"]["b"] ).to eq "Example Inc.,"
      expect(@record["260"]["c"] ).to eq "2014."
    end

  end

end
