require 'spec_helper'

describe ActiveFedora::FieldNameMapper do
  
  before(:all) do
    class TestFieldNameMapper
      include ActiveFedora::FieldNameMapper
    end
  end
  
  describe "#mappings" do
    it "should return at least an id_field value" do
      TestFieldNameMapper.id_field.should == "id"
    end
  end
  
  describe '#solr_name' do
    it "should generate solr field names" do
      TestFieldNameMapper.solr_name(:active_fedora_model, :symbol).should == "active_fedora_model_s"
    end
  end
  
  describe "#load_mappings" do 
    it "should take mappings file as an optional argument" do
      file_path = File.join(File.dirname(__FILE__), "..", "fixtures","test_solr_mappings.yml")
      TestFieldNameMapper.load_mappings(file_path)
      mappings_from_file = YAML::load(File.open(file_path))
      TestFieldNameMapper.id_field.should == "pid"
      TestFieldNameMapper.mappings[:edible].opts[:default].should == true
      TestFieldNameMapper.mappings[:edible].data_types[:boolean].opts[:suffix].should == "_edible_bool"
      mappings_from_file["edible"].each_pair do |k,v|
        TestFieldNameMapper.mappings[:edible].data_types[k.to_sym].opts[:suffix].should == v        
      end
      TestFieldNameMapper.mappings[:displayable].opts[:suffix].should == mappings_from_file["displayable"]
      TestFieldNameMapper.mappings[:facetable].opts[:suffix].should == mappings_from_file["facetable"]
      TestFieldNameMapper.mappings[:sortable].opts[:suffix].should == mappings_from_file["sortable"]
    end
    it 'should default to using the mappings from config/solr_mappings.yml' do
      TestFieldNameMapper.load_mappings
      default_file_path = File.join(File.dirname(__FILE__), "..", "..","config","solr_mappings.yml")
      mappings_from_file = YAML::load(File.open(default_file_path))
      TestFieldNameMapper.id_field.should == mappings_from_file["id"]
      mappings_from_file["searchable"].each_pair do |k,v|
        TestFieldNameMapper.mappings[:searchable].data_types[k.to_sym].opts[:suffix].should == v        
      end
      TestFieldNameMapper.mappings[:displayable].opts[:suffix].should == mappings_from_file["displayable"]
      TestFieldNameMapper.mappings[:facetable].opts[:suffix].should == mappings_from_file["facetable"]
      TestFieldNameMapper.mappings[:sortable].opts[:suffix].should == mappings_from_file["sortable"]
    end
    it "should wipe out pre-existing mappings without affecting other FieldMappers" do
      TestFieldNameMapper.load_mappings
      file_path = File.join(File.dirname(__FILE__), "..", "fixtures","test_solr_mappings.yml")
      TestFieldNameMapper.load_mappings(file_path)
      TestFieldNameMapper.mappings[:searchable].should be_nil
      ActiveFedora::FieldMapper::Default.mappings[:searchable].should_not be_nil
    end
    it "should raise an informative error if the yaml file is structured improperly"
    it "should raise an informative error if there is no YAML file"
  end
end
