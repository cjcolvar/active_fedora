require File.join( File.dirname(__FILE__), "../spec_helper" )

require 'active_fedora'
require 'active_fedora/base'
require 'active_fedora/metadata_datastream'
require 'time'
require 'date'

class FooHistory < ActiveFedora::Base
  has_metadata :type=>ActiveFedora::MetadataDatastream, :name=>"someData" do |m|
    m.field "fubar", :string
    m.field "swank", :text
  end
  has_metadata :type=>ActiveFedora::MetadataDatastream, :name=>"withText" do |m|
    m.field "fubar", :text
  end
  has_metadata :type=>ActiveFedora::MetadataDatastream, :name=>"withText2", :label=>"withLabel" do |m|
    m.field "fubar", :text
  end 
end

@@last_pid = 0  

describe ActiveFedora::Base do
  
  def increment_pid
    @@last_pid += 1    
  end

  before(:each) do
    Fedora::Repository.instance.stubs(:nextid).returns(increment_pid.to_s)
    @test_object = Fedora::FedoraObject.new
    #@test_object.new_object = true
  end

  after(:each) do
    begin
    ActiveFedora::SolrService.stubs(:instance)
    @test_object.delete
    rescue
    end
  end

  describe '#new' do
    it "should create a new inner object" do
      Fedora::Repository.instance.expects(:save).never
      result = ActiveFedora::Base.new(:pid=>"test:1")  
      result.inner_object.should be_kind_of(Fedora::FedoraObject)    
    end

  end

  describe ".internal_uri" do
    it "should return pid as fedors uri" do
      @test_object.internal_uri.should eql("info:fedora/#{@test_object.pid}")
    end
  end

  it "should have to_param" do
    @test_object.to_param.should == @test_object.pid
  end

  it "should respond_to has_metadata" do
    ActiveFedora::Base.respond_to?(:has_metadata).should be_true
  end

  describe "has_metadata" do
    before :each do
      @n = FooHistory.new(:pid=>"monkey:99")
      @n.save
    end

    after :each do
      begin
        @n.delete
      rescue
      end
    end

    it "should create specified datastreams with specified fields" do
      @n.datastreams["someData"].should_not be_nil
      @n.datastreams["someData"].fubar_values='bar'
      @n.datastreams["someData"].fubar_values.should == ['bar']
      @n.datastreams["withText2"].label.should == "withLabel"
    end

  end

  describe ".fields" do
    it "should provide fields" do
      @test_object.should respond_to(:fields)
    end
    it "should add pid, system_create_date and system_modified_date from object attributes" do
      cdate = "2008-07-02T05:09:42.015Z"
      mdate = "2009-07-07T23:37:18.991Z"
      @test_object.expects(:create_date).returns(cdate)
      @test_object.expects(:modified_date).returns(mdate)
      fields = @test_object.fields
      fields[:system_create_date][:values].should eql([cdate])
      fields[:system_modified_date][:values].should eql([mdate])
      fields[:id][:values].should eql([@test_object.pid])
    end
    
    it "should add self.class as the :active_fedora_model" do
      fields = @test_object.fields
      fields[:active_fedora_model][:values].should eql([@test_object.class.inspect])
    end
    
    it "should call .fields on all MetadataDatastreams and return the resulting document" do
      mock1 = mock("ds1", :fields => {})
      mock2 = mock("ds2", :fields => {})
      mock1.expects(:kind_of?).with(ActiveFedora::MetadataDatastream).returns(true)
      mock2.expects(:kind_of?).with(ActiveFedora::MetadataDatastream).returns(true)

      @test_object.expects(:datastreams).returns({:ds1 => mock1, :ds2 => mock2})
      @test_object.fields
    end
  end

  it 'should provide #find' do
    ActiveFedora::Base.should respond_to(:find)
  end

  it "should provide .create_date" do
    @test_object.should respond_to(:create_date)
  end

  it "should provide .modified_date" do
    @test_object.should respond_to(:modified_date)
  end

  it 'should respond to .rels_ext' do
    @test_object.should respond_to(:rels_ext)
  end

  describe '.rels_ext' do
    it 'should create the RELS-EXT datastream if it doesnt exist' do
      mocker = mock("rels-ext")
      ActiveFedora::RelsExtDatastream.expects(:new).returns(mocker)
      @test_object.expects(:add_datastream).with(mocker)
      # Make sure the RELS-EXT datastream does not exist yet
      @test_object.datastreams["RELS-EXT"].should == nil
      @test_object.rels_ext
      # Assume that @test_object.add_datastream actually does its job and adds the datastream to the datastreams array.  Not testing that here.
    end

    it 'should return the RelsExtDatastream object from the datastreams array' do
      @test_object.expects(:datastreams).returns({"RELS-EXT" => "foo"}).at_least_once
      @test_object.rels_ext.should == "foo"
    end
  end

  it 'should provide #add_relationship' do
    @test_object.should respond_to(:add_relationship)
  end

  describe '#add_relationship' do
    it 'should call #add_relationship on the rels_ext datastream' do
      mock_relationship = mock("relationship")
      mock_rels_ext = mock("rels-ext", :add_relationship)
      mock_rels_ext.expects(:dirty=).with(true)
      @test_object.expects(:relationship_exists?).returns(false).once()
      @test_object.expects(:rels_ext).returns(mock_rels_ext).times(2) 
      @test_object.add_relationship("predicate", "object")
    end

    it "should update the RELS-EXT datastream and set the datastream as dirty when relationships are added" do
      mock_ds = mock("Rels-Ext")
      mock_ds.expects(:add_relationship).times(2)
      mock_ds.expects(:dirty=).with(true).times(2)
      @test_object.expects(:relationship_exists?).returns(false).times(2)
      @test_object.datastreams["RELS-EXT"] = mock_ds
      test_relationships = [ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_member_of, :object => "info:fedora/demo:5"), 
        ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_member_of, :object => "info:fedora/demo:10")]
      test_relationships.each do |rel|
        @test_object.add_relationship(rel.predicate, rel.object)
      end
    end
    
    it 'should add a relationship to an object only if it does not exist already' do
      Fedora::Repository.instance.stubs(:nextid).returns(increment_pid)
      @test_object3 = ActiveFedora::Base.new
      @test_object.add_relationship(:has_part,@test_object3)
      r = ActiveFedora::Relationship.new(:subject=>:self, :predicate=>:dummy, :object=>@test_object3)
      @test_object.relationships.should == {:self=>{:has_part=>[r.object]}}
      #try adding again and make sure not there twice
      @test_object.add_relationship(:has_part,@test_object3)
      @test_object.relationships.should == {:self=>{:has_part=>[r.object]}}
    end
  end
  
  it 'should provide #remove_relationship' do
    @test_object.should respond_to(:remove_relationship)
  end
  
  describe '#remove_relationship' do
    it 'should remove a relationship from the relationships hash' do
      Fedora::Repository.instance.stubs(:nextid).returns(increment_pid)
      @test_object3 = ActiveFedora::Base.new
      Fedora::Repository.instance.stubs(:nextid).returns(increment_pid)
      @test_object4 = ActiveFedora::Base.new
      @test_object.add_relationship(:has_part,@test_object3)
      @test_object.add_relationship(:has_part,@test_object4)
      r = ActiveFedora::Relationship.new(:subject=>:self, :predicate=>:dummy, :object=>@test_object3)
      r2 = ActiveFedora::Relationship.new(:subject=>:self, :predicate=>:dummy, :object=>@test_object4)
      #check both are there
      @test_object.relationships.should == {:self=>{:has_part=>[r.object,r2.object]}}
      @test_object.remove_relationship(:has_part,@test_object3)
      #check only one item removed
      @test_object.relationships.should == {:self=>{:has_part=>[r2.object]}}
      @test_object.remove_relationship(:has_part,@test_object4)
      #check last item removed and predicate removed since now emtpy
      @test_object.relationships.should == {:self=>{}}
    end
  end

  it 'should provide #relationships' do
    @test_object.should respond_to(:relationships)
  end

  describe '#relationships' do
    it 'should call #relationships on the rels_ext datastream and return that' do
      @test_object.expects(:rels_ext).returns(mock("rels-ext", :relationships))
      @test_object.relationships
    end
  end

  describe '.save' do
    
    
    it "should return true if object and datastreams all save successfully" do
      @test_object.expects(:create).returns(true)
      @test_object.save.should == true
    end
    
    it "should raise an exception if object fails to save" do
      server_response = mock("Server Error")
      Fedora::Repository.instance.expects(:save).with(@test_object.inner_object).raises(Fedora::ServerError, server_response)
      lambda {@test_object.save}.should raise_error(Fedora::ServerError)
      #lambda {@test_object.save}.should raise_error(Fedora::ServerError, "Error Saving object #{@test_object.pid}. Server Error: RubyFedora Error Msg")
    end
    
    it "should raise an exception if any of the datastreams fail to save" do
      Fedora::Repository.instance.expects(:save).with(@test_object.inner_object).returns(true)
      Fedora::Repository.instance.expects(:save).with(kind_of(ActiveFedora::RelsExtDatastream)).raises(Fedora::ServerError,  mock("Server Error")) 
      lambda {@test_object.save}.should raise_error(Fedora::ServerError)
    end
    
    it "should call .save on any datastreams that are dirty" do
      to = FooHistory.new
      to.expects(:update_index)
      Fedora::Repository.instance.expects(:save).with(to.inner_object)
      Fedora::Repository.instance.expects(:save).with(kind_of(ActiveFedora::RelsExtDatastream))
      Fedora::Repository.instance.expects(:save).with(to.datastreams["withText"])
      Fedora::Repository.instance.expects(:save).with(to.datastreams["withText2"])
      to.datastreams["someData"].stubs(:dirty?).returns(true)
      to.datastreams["someData"].stubs(:new_object?).returns(true)
      to.datastreams["someData"].expects(:save)
      to.expects(:refresh)
      to.save
    end
    it "should call .save on any datastreams that are new" do
      ds = ActiveFedora::Datastream.new(:dsid => 'ds_to_add')
      @test_object.add_datastream(ds)
      ds.expects(:save)
      @test_object.instance_variable_set(:@new_object, false)
      Fedora::Repository.instance.expects(:save).with(@test_object.inner_object)
      #Fedora::Repository.instance.expects(:save).with(kind_of(ActiveFedora::RelsExtDatastream))
      @test_object.expects(:refresh)
      @test_object.save
    end
    it "should not call .save on any datastreams that are not dirty" do
      @test_object = FooHistory.new
      @test_object.expects(:update_index)
      @test_object.expects(:refresh)
      @test_object.dc.should be_nil #heh, haven't saved it yet!
      Fedora::Repository.instance.expects(:save).with(@test_object.inner_object)
      Fedora::Repository.instance.expects(:save).with(kind_of(ActiveFedora::RelsExtDatastream))
      Fedora::Repository.instance.expects(:save).with(@test_object.datastreams["withText"])
      Fedora::Repository.instance.expects(:save).with(@test_object.datastreams["withText2"])
      @test_object.datastreams["someData"].should_not be_nil
      @test_object.datastreams['someData'].stubs(:dirty?).returns(false)
      @test_object.datastreams['someData'].stubs(:new_object?).returns(false)
      @test_object.datastreams['someData'].expects(:save).never
      @test_object.save
    end
    it "should update solr index with all metadata if any MetadataDatastreams have changed" do
      Fedora::Repository.instance.stubs(:save)
      dirty_ds = ActiveFedora::MetadataDatastream.new
      dirty_ds.expects(:dirty?).returns(true)
      dirty_ds.expects(:save).returns(true)
      mock2 = mock("ds2", :dirty? => false, :new_object? => false)
      @test_object.stubs(:datastreams_in_memory).returns({:ds1 => dirty_ds, :ds2 => mock2})
      @test_object.expects(:update_index)
      @test_object.expects(:refresh)
      
      @test_object.save
    end
    it "should NOT update solr index if no MetadataDatastreams have changed" do
      Fedora::Repository.instance.stubs(:save)
      mock1 = mock("ds1", :dirty? => false, :new_object? => false)
      mock2 = mock("ds2", :dirty? => false, :new_object? => false)
      @test_object.stubs(:datastreams_in_memory).returns({:ds1 => mock1, :ds2 => mock2})
      @test_object.expects(:update_index).never
      @test_object.expects(:refresh)
      @test_object.instance_variable_set(:@new_object, false)
      
      @test_object.save
    end
    it "should update solr index if RELS-EXT datastream has changed" do
      Fedora::Repository.instance.stubs(:save)
      rels_ext = ActiveFedora::RelsExtDatastream.new
      rels_ext.expects(:dirty?).returns(true)
      rels_ext.expects(:save).returns(true)
      clean_ds = mock("ds2", :dirty? => false, :new_object? => false)
      @test_object.stubs(:datastreams_in_memory).returns({"RELS-EXT" => rels_ext, :clean_ds => clean_ds})
      @test_object.instance_variable_set(:@new_object, false)
      @test_object.expects(:refresh)
      @test_object.expects(:update_index)
      
      @test_object.save
    end
  end


  describe ".to_xml" do
    it "should provide .to_xml" do
      @test_object.should respond_to(:to_xml)
    end

    it "should add pid, system_create_date and system_modified_date from object attributes" do
      @test_object.expects(:create_date).returns("cDate")
      @test_object.expects(:modified_date).returns("mDate")
      solr_doc = @test_object.to_solr
      solr_doc["system_create_dt"].should eql("cDate")
      solr_doc["system_modified_dt"].should eql("mDate")
      solr_doc[:id].should eql("#{@test_object.pid}")
    end

    it "should add self.class as the :active_fedora_model" do
      solr_doc = @test_object.to_solr
      solr_doc["active_fedora_model_s"].should eql(@test_object.class.inspect)
    end

    it "should call .to_xml on all MetadataDatastreams and return the resulting document" do
      ds1 = ActiveFedora::MetadataDatastream.new
      ds2 = ActiveFedora::MetadataDatastream.new
      [ds1,ds2].each {|ds| ds.expects(:to_xml)}

      @test_object.expects(:datastreams).returns({:ds1 => ds1, :ds2 => ds2})
      @test_object.to_xml
    end
  end
  
  describe ".to_solr" do
    
    # before(:all) do
    #   # Revert to default mappings after running tests
    #   ActiveFedora::SolrService.load_mappings
    # end
    
    after(:all) do
      # Revert to default mappings after running tests
      ActiveFedora::SolrService.load_mappings
    end
    
    it "should provide .to_solr" do
      @test_object.should respond_to(:to_solr)
    end

    it "should add pid, system_create_date and system_modified_date from object attributes" do
      @test_object.expects(:create_date).returns("cDate")
      @test_object.expects(:modified_date).returns("mDate")
      solr_doc = @test_object.to_solr
      solr_doc["system_create_dt"].should eql("cDate")
      solr_doc["system_modified_dt"].should eql("mDate")
      solr_doc[:id].should eql("#{@test_object.pid}")
    end

    it "should omit base metadata and RELS-EXT if :model_only==true" do
      @test_object.add_relationship(:has_part, "foo")
      # @test_object.expects(:modified_date).returns("mDate")
      solr_doc = @test_object.to_solr(Hash.new, :model_only => true)
      solr_doc["system_create_dt"].should be_nil
      solr_doc["system_modified_dt"].should be_nil
      solr_doc["id"].should be_nil
      solr_doc["has_part_s"].should be_nil
    end
    
    it "should add self.class as the :active_fedora_model" do
      solr_doc = @test_object.to_solr
      solr_doc["active_fedora_model_s"].should eql(@test_object.class.inspect)
    end

    it "should use mappings.yml to decide names of solr fields" do      
      cdate = "2008-07-02T05:09:42.015Z"
      mdate = "2009-07-07T23:37:18.991Z"
      @test_object.stubs(:create_date).returns(cdate)
      @test_object.stubs(:modified_date).returns(mdate)
      solr_doc = @test_object.to_solr
      solr_doc["system_create_dt"].should eql(cdate)
      solr_doc["system_modified_dt"].should eql(mdate)
      solr_doc[:id].should eql("#{@test_object.pid}")
      solr_doc["active_fedora_model_s"].should eql(@test_object.class.inspect)
      
      ActiveFedora::SolrService.load_mappings(File.join(File.dirname(__FILE__), "..", "..", "config", "solr_mappings_af_0.1.yml"))
      solr_doc = @test_object.to_solr
      [:system_create_dt, :system_modified_dt, :active_fedora_model_s].each do |fn|
        solr_doc[fn].should == nil
      end
      solr_doc["system_create_date"].should eql(cdate)
      solr_doc["system_modified_date"].should eql(mdate)
      solr_doc[:id].should eql("#{@test_object.pid}")
      solr_doc["active_fedora_model_field"].should eql(@test_object.class.inspect)
    end
    
    it "should call .to_solr on all MetadataDatastreams and NokogiriDatastreams, passing the resulting document to solr" do
      mock1 = mock("ds1", :to_solr)
      mock2 = mock("ds2", :to_solr)
      ngds = mock("ngds", :to_solr)
      mock1.expects(:kind_of?).with(ActiveFedora::MetadataDatastream).returns(true)
      mock2.expects(:kind_of?).with(ActiveFedora::MetadataDatastream).returns(true)
      ngds.expects(:kind_of?).with(ActiveFedora::MetadataDatastream).returns(false)
      ngds.expects(:kind_of?).with(ActiveFedora::NokogiriDatastream).returns(true)
      
      @test_object.expects(:datastreams).returns({:ds1 => mock1, :ds2 => mock2, :ngds => ngds})
      @test_object.to_solr
    end
    it "should call .to_solr on the RELS-EXT datastream if it is dirty" do
      @test_object.add_relationship(:has_collection_member, "foo member")
      rels_ext = @test_object.datastreams_in_memory["RELS-EXT"]
      rels_ext.dirty?.should == true
      rels_ext.expects(:to_solr)
      @test_object.to_solr
    end
    
  end

  describe ".update_index" do
    it "should provide .update_index" do
      @test_object.should respond_to(:update_index)
    end
  end

  describe ".label" do
    it "should return the label of the inner object" do 
      @test_object.inner_object.expects(:label).returns("foo label")
      @test_object.label.should == "foo label"
    end
  end
  
  describe ".label=" do
    it "should set the label of the inner object" do
      @test_object.label.should_not == "foo label"
      @test_object.label = "foo label"
      @test_object.label.should == "foo label"
    end
  end
  
  it "should get a pid but not save on init" do
    Fedora::Repository.instance.expects(:save).never
    Fedora::Repository.instance.expects(:nextid).returns('mooshoo:24')
    f = FooHistory.new
    f.pid.should_not be_nil
    f.pid.should == 'mooshoo:24'
  end
  it "should not clobber a pid if i'm creating!" do
    FooHistory.any_instance.expects(:configure_defined_datastreams)
    f = FooHistory.new(:pid=>'numbnuts:1')
    f.pid.should == 'numbnuts:1'

  end
  
  describe "get_values_from_datastream" do
    it "should look up the named datastream and call get_values with the given pointer/field_name" do
      mock_ds = mock("Datastream", :get_values=>["value1", "value2"])
      @test_object.stubs(:datastreams_in_memory).returns({"ds1"=>mock_ds})
      @test_object.get_values_from_datastream("ds1", "--my xpath--").should == ["value1", "value2"]
    end
  end
  
  describe "update_datastream_attributes" do
    it "should look up any datastreams specified as keys in the given hash and call update_attributes on the datastream" do
      mock_desc_metadata = mock("descMetadata")
      mock_properties = mock("properties")
      mock_ds_hash = {'descMetadata'=>mock_desc_metadata, 'properties'=>mock_properties}
      
      ds_values_hash = {
        "descMetadata"=>{ [{:person=>0}, :role]=>{"0"=>"role1", "1"=>"role2", "2"=>"role3"} },
        "properties"=>{ "notes"=>"foo" }
      }
      m = FooHistory.new
      m.stubs(:datastreams_in_memory).returns(mock_ds_hash)
      mock_desc_metadata.expects(:update_indexed_attributes).with( ds_values_hash['descMetadata'] )
      mock_properties.expects(:update_indexed_attributes).with( ds_values_hash['properties'] )
      m.update_datastream_attributes( ds_values_hash )
    end
    it "should not do anything and should return an empty hash if the specified datastream does not exist" do
      ds_values_hash = {
        "nonexistentDatastream"=>{ "notes"=>"foo" }
      }
      m = FooHistory.new
      untouched_xml = m.to_xml
      m.update_datastream_attributes( ds_values_hash ).should == {}
      m.to_xml.should == untouched_xml
    end
  end
  
  describe "update_attributes" do

    it "should call .update_attributes on all metadata datastreams & nokogiri datastreams" do
      m = FooHistory.new
      att= {"fubar"=>{"-1"=>"mork", "0"=>"york", "1"=>"mangle"}}
      
      m.metadata_streams.each {|ds| ds.expects(:update_attributes)}
      m.update_attributes(att)
    end
    
    it "should be able to update attr on text fields" do
      m = FooHistory.new
      m.should_not be_nil
      m.datastreams['someData'].swank_values.should == []
      m.update_attributes(:swank=>'baz')
      m.should_not be_nil
      m.datastreams['someData'].swank_values.should == ['baz']
    end

    it "should have update_attributes" do
      n = FooHistory.new
      n.update_attributes(:fubar=>'baz')
      n.datastreams["someData"].fubar_values.should == ['baz']
      n.update_attributes('fubar'=>'bak')
      n.datastreams["someData"].fubar_values.should == ['bak']
      #really? should it hit all matching datastreams?
      n.datastreams["withText"].fubar_values.should == ['bak']
    end

    it "should allow deleting of values" do
      n = FooHistory.new
      n.datastreams["someData"].fubar_values.should == []
      n.update_attributes(:fubar=>'baz')
      n.datastreams["someData"].fubar_values.should == ['baz']
      n.update_attributes(:fubar=>:delete)
      n.datastreams["someData"].fubar_values.should == []
      n.update_attributes(:fubar=>'baz')
      n.datastreams["someData"].fubar_values.should == ['baz']
      n.update_attributes(:fubar=>"")
      n.datastreams["someData"].fubar_values.should == []
    end
    
    it "should take a :datastreams argument" do 
      m = FooHistory.new
      m.should_not be_nil
      m.datastreams['someData'].fubar_values.should == []
      m.datastreams['withText'].fubar_values.should == []
      m.datastreams['withText2'].fubar_values.should == []

      m.update_attributes({:fubar=>'baz'}, :datastreams=>"someData")
      m.should_not be_nil
      m.datastreams['someData'].fubar_values.should == ['baz']
      m.datastreams["withText"].fubar_values.should == []
      m.datastreams['withText2'].fubar_values.should == []
      
      m.update_attributes({:fubar=>'baz'}, :datastreams=>["someData", "withText2"])
      m.should_not be_nil
      m.datastreams['someData'].fubar_values.should == ['baz']
      m.datastreams["withText"].fubar_values.should == []
      m.datastreams['withText2'].fubar_values.should == ['baz']
    end
  end
  
  describe "update_indexed_attributes" do
    it "should call .update_indexed_attributes on all metadata datastreams & nokogiri datastreams" do
      m = FooHistory.new
      att= {"fubar"=>{"-1"=>"mork", "0"=>"york", "1"=>"mangle"}}
      
      m.datastreams_in_memory.each_value {|ds| ds.expects(:update_indexed_attributes)}
      m.update_indexed_attributes(att)
    end
    it "should take a :datastreams argument" do 
      att= {"fubar"=>{"-1"=>"mork", "0"=>"york", "1"=>"mangle"}}
      m = FooHistory.new
      m.update_indexed_attributes(att, :datastreams=>"withText")
      m.should_not be_nil
      m.datastreams['someData'].fubar_values.should == []
      m.datastreams["withText"].fubar_values.should == ['mork', 'york', 'mangle']
      m.datastreams['withText2'].fubar_values.should == []
      
      att= {"fubar"=>{"-1"=>"tork", "0"=>"work", "1"=>"bork"}}
      m.update_indexed_attributes(att, :datastreams=>["someData", "withText2"])
      m.should_not be_nil
      m.datastreams['someData'].fubar_values.should == ['tork', 'work', 'bork']
      m.datastreams["withText"].fubar_values.should == ['mork', 'york', 'mangle']
      m.datastreams['withText2'].fubar_values.should == ['tork', 'work', 'bork']
    end
  end

  it "should expose solr for real." do
    sinmock = mock('solr instance')
    conmock = mock("solr conn")
    sinmock.expects(:conn).returns(conmock)
    conmock.expects(:query).with('pid: foobar', {}).returns({:baz=>:bif})
    ActiveFedora::SolrService.expects(:instance).returns(sinmock)
    FooHistory.solr_search("pid: foobar").should == {:baz=>:bif}
  end
  it "should expose solr for real. and pass args through" do
    sinmock = mock('solr instance')
    conmock = mock("solr conn")
    sinmock.expects(:conn).returns(conmock)
    conmock.expects(:query).with('pid: foobar', {:ding, :dang}).returns({:baz=>:bif})
    ActiveFedora::SolrService.expects(:instance).returns(sinmock)
    FooHistory.solr_search("pid: foobar", {:ding=>:dang}).should == {:baz=>:bif}
  end

  it 'should provide #named_relationships' do
    @test_object.should respond_to(:named_relationships)
  end
  
  describe '#named_relationships' do
    
    class MockNamedRelationships < ActiveFedora::Base
      has_relationship "testing", :has_part, :type=>ActiveFedora::Base
      has_relationship "testing2", :has_member, :type=>ActiveFedora::Base
      has_relationship "testing_inbound", :has_part, :type=>ActiveFedora::Base, :inbound=>true
    end
    
    it 'should return current named relationships' do
      Fedora::Repository.instance.stubs(:nextid).returns(increment_pid)
      @test_object2 = MockNamedRelationships.new
      @test_object2.add_relationship(:has_model, ActiveFedora::ContentModel.pid_from_ruby_class(MockNamedRelationships))
      @test_object.add_relationship(:has_model, ActiveFedora::ContentModel.pid_from_ruby_class(ActiveFedora::Base))
      #should return expected named relationships
      @test_object2.named_relationships
      @test_object2.named_relationships.should == {:self=>{"testing"=>[],"testing2"=>[]}}
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:dummy,:object=>@test_object})
      @test_object2.add_named_relationship("testing",@test_object)
      @test_object2.named_relationships.should == {:self=>{"testing"=>[r.object],"testing2"=>[]}}
    end 
  end

  
  describe '#create_named_relationship_methods' do
    class MockCreateNamedRelationshipMethodsBase < ActiveFedora::Base
      register_named_relationship :self, "testing", :is_part_of, :type=>ActiveFedora::Base
      create_named_relationship_methods "testing"
    end
      
    it 'should append and remove using helper methods for each outbound relationship' do
      Fedora::Repository.instance.stubs(:nextid).returns(increment_pid)
      @test_object2 = MockCreateNamedRelationshipMethodsBase.new 
      @test_object2.should respond_to(:testing_append)
      @test_object2.should respond_to(:testing_remove)
      #test executing each one to make sure code added is correct
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_model,:object=>ActiveFedora::ContentModel.pid_from_ruby_class(ActiveFedora::Base)})
      @test_object.add_relationship(r.predicate,r.object)
      @test_object2.add_relationship(r.predicate,r.object)
      @test_object2.testing_append(@test_object)
      #create relationship to access generate_uri method for an object
      r = ActiveFedora::Relationship.new(:subject=>:self, :predicate=>:dummy, :object=>@test_object)
      @test_object2.named_relationships.should == {:self=>{"testing"=>[r.object]}}
      @test_object2.testing_remove(@test_object)
      @test_object2.named_relationships.should == {:self=>{"testing"=>[]}}
    end
  end
end
