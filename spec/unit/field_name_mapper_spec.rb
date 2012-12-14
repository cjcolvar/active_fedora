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
      TestFieldNameMapper.field_mapper.default_index_types.include?(:edible).should == true
      TestFieldNameMapper.field_mapper.mappings[[:edible,:boolean]][:suffix].should == "_edible_bool"
      mappings_from_file["edible"].each_pair do |k,v|
        TestFieldNameMapper.field_mapper.mappings[[:edible, k.to_sym]][:suffix].should == v        
      end
      TestFieldNameMapper.field_mapper.mappings[:displayable].should == mappings_from_file["displayable"]
      TestFieldNameMapper.field_mapper.mappings[:facetable].should == mappings_from_file["facetable"]
      TestFieldNameMapper.field_mapper.mappings[:sortable].should == mappings_from_file["sortable"]
    end
    it 'should default to using the mappings from config/solr_mappings.yml' do
      TestFieldNameMapper.load_mappings
      default_file_path = File.join(File.dirname(__FILE__), "..", "..","config","solr_mappings.yml")
      mappings_from_file = YAML::load(File.open(default_file_path))
      TestFieldNameMapper.id_field.should == mappings_from_file["id"]
      mappings_from_file["searchable"].each_pair do |k,v|
        TestFieldNameMapper.field_mapper.mappings[[:searchable,k.to_sym]][:suffix].should == v        
      end
      TestFieldNameMapper.field_mapper.mappings[:displayable].should == mappings_from_file["displayable"]
      TestFieldNameMapper.field_mapper.mappings[:facetable].should == mappings_from_file["facetable"]
      TestFieldNameMapper.field_mapper.mappings[:sortable].should == mappings_from_file["sortable"]
    end
    it "should wipe out pre-existing mappings without affecting other FieldMappers" do
      TestFieldNameMapper.load_mappings
      file_path = File.join(File.dirname(__FILE__), "..", "fixtures","test_solr_mappings.yml")
      TestFieldNameMapper.load_mappings(file_path)
      TestFieldNameMapper.field_mapper.mappings[:searchable].should be_nil
      ActiveFedora::FieldMapper::Default.mappings[[:searchable, :default]].should_not be_nil
    end
    it "should raise an informative error if the yaml file is structured improperly"
    it "should raise an informative error if there is no YAML file"
  end
end
