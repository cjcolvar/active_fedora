require File.join( File.dirname(__FILE__), "../spec_helper" )

require 'active_fedora'
require 'xmlsimple'

@@last_pid = 0

class SpecNode2
  include ActiveFedora::RelationshipsHelper
  include ActiveFedora::SemanticNode
  
  attr_accessor :pid
end

describe ActiveFedora::SemanticNode do
  
  def increment_pid
    @@last_pid += 1    
  end
    
  before(:all) do
    @pid = "test:sample_pid"
    @uri = "info:fedora/#{@pid}"
    @sample_solr_hits = [{"id"=>"_PID1_", "has_model_s"=>["info:fedora/afmodel:AudioRecord"]},
                          {"id"=>"_PID2_", "has_model_s"=>["info:fedora/afmodel:AudioRecord"]},
                          {"id"=>"_PID3_", "has_model_s"=>["info:fedora/afmodel:AudioRecord"]}]
  end
  
  before(:each) do
    class SpecNode
      include ActiveFedora::RelationshipsHelper
      include ActiveFedora::SemanticNode
      
      attr_accessor :pid

    end
    
    @node = SpecNode.new
    @node.pid = increment_pid
    @test_object = SpecNode2.new
    @test_object.pid = increment_pid    
    @stub_relationship = stub("mock_relationship", :subject => @pid, :predicate => "isMemberOf", :object => "demo:8", :class => ActiveFedora::Relationship)  
    @test_relationship = ActiveFedora::Relationship.new(:subject => @pid, :predicate => "isMemberOf", :object => "demo:9")  
    @test_relationship1 = ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_member_of, :object => "demo:10")  
    @test_relationship2 = ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_part_of, :object => "demo:11")  
    @test_relationship3 = ActiveFedora::Relationship.new(:subject => @pid, :predicate => :has_part, :object => "demo:12")
    @test_cmodel_relationship1 = ActiveFedora::Relationship.new(:subject => @pid, :predicate => :has_model, :object => "afmodel:SampleModel")
    @test_cmodel_relationship2 = ActiveFedora::Relationship.new(:subject => @pid, :predicate => "hasModel", :object => "afmodel:OtherModel")
  end
  
  after(:each) do
    Object.send(:remove_const, :SpecNode)
    begin
    @test_object.delete
    rescue
    end
    begin
    @test_object2.delete
    rescue
    end
    begin
    @test_object3.delete
    rescue
    end
    begin
    @test_object4.delete
    rescue
    end
    begin
    @test_object5.delete
    rescue
    end
  end
 
  it 'should provide .default_predicate_namespace' do
    SpecNode.should respond_to(:default_predicate_namespace)
    SpecNode.default_predicate_namespace.should == 'info:fedora/fedora-system:def/relations-external#'
  end
 
  it 'should provide .predicate_mappings' do
    SpecNode.should respond_to(:predicate_mappings)
  end

  describe "#predicate_mappings" do 

    it 'should return a hash' do
      SpecNode.predicate_mappings.should be_kind_of Hash
    end

    it "should provide mappings to the fedora ontology via the info:fedora/fedora-system:def/relations-external default namespace mapping" do
      SpecNode.predicate_mappings.keys.include?(SpecNode.default_predicate_namespace).should be_true
      SpecNode.predicate_mappings[SpecNode.default_predicate_namespace].should be_kind_of Hash
    end

    it 'should provide predicate mappings for entire Fedora Relationship Ontology' do
      desired_mappings = Hash[:is_member_of => "isMemberOf",
                            :has_member => "hasMember",
                            :is_part_of => "isPartOf",
                            :has_part => "hasPart",
                            :is_member_of_collection => "isMemberOfCollection",
                            :has_collection_member => "hasCollectionMember",
                            :is_constituent_of => "isConstituentOf",
                            :has_constituent => "hasConstituent",
                            :is_subset_of => "isSubsetOf",
                            :has_subset => "hasSubset",
                            :is_derivation_of => "isDerivationOf",
                            :has_derivation => "hasDerivation",
                            :is_dependent_of => "isDependentOf",
                            :has_dependent => "hasDependent",
                            :is_description_of => "isDescriptionOf",
                            :has_description => "hasDescription",
                            :is_metadata_for => "isMetadataFor",
                            :has_metadata => "hasMetadata",
                            :is_annotation_of => "isAnnotationOf",
                            :has_annotation => "hasAnnotation",
                            :has_equivalent => "hasEquivalent",
                            :conforms_to => "conformsTo",
                            :has_model => "hasModel"]
      desired_mappings.each_pair do |k,v|
        SpecNode.predicate_mappings[SpecNode.default_predicate_namespace].should have_key(k)
        SpecNode.predicate_mappings[SpecNode.default_predicate_namespace][k].should == v
      end
    end
  end

  it 'should provide .internal_uri' do
    @node.should  respond_to(:internal_uri)
  end
  
  it 'should provide #has_relationship' do
    SpecNode.should  respond_to(:has_relationship)
    SpecNode.should  respond_to(:has_relationship)
  end
  
  describe '#has_relationship' do
    it "should create finders based on provided relationship name" do
      SpecNode.has_relationship("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new
      local_node.should respond_to(:parts_ids)
      local_node.should respond_to(:parts_query)
      # local_node.should respond_to(:parts)
      local_node.should_not respond_to(:containers)
      SpecNode.has_relationship("containers", :is_member_of)  
      local_node.should respond_to(:containers_ids)
      local_node.should respond_to(:containers_query)
    end
    
    it "should add a subject and predicate to the relationships array" do
      SpecNode.has_relationship("parents", :is_part_of)
      SpecNode.relationships.should have_key(:self)
      @node.relationships[:self].should have_key(:is_part_of)
    end
    
    it "should use :inbound as the subject if :inbound => true" do
      SpecNode.has_relationship("parents", :is_part_of, :inbound => true)
      SpecNode.relationships.should have_key(:inbound)
      @node.relationships[:inbound].should have_key(:is_part_of)
    end
    
    it 'should create inbound relationship finders' do
      SpecNode.expects(:create_inbound_relationship_finders)
      SpecNode.has_relationship("parts", :is_part_of, :inbound => true) 
    end
    
    it 'should create outbound relationship finders' do
      SpecNode.expects(:create_outbound_relationship_finders).times(2)
      SpecNode.has_relationship("parts", :is_part_of, :inbound => false)
      SpecNode.has_relationship("container", :is_member_of)
    end
    
    it "should create outbound relationship finders that return an array of fedora PIDs" do
      SpecNode.has_relationship("containers", :is_member_of, :inbound => false)
      local_node = SpecNode.new
      local_node.expects(:loaded_fedora_properties).returns(false)
      local_node.expects(:load_fedora_properties)
      local_node.expects(:new_object?).returns(false)
      local_node.internal_uri = "info:fedora/#{@pid}"
      
      local_node.add_relationship(ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_member_of, :object => "info:fedora/container:A") )
      local_node.add_relationship(ActiveFedora::Relationship.new(:subject => :self, :predicate => :is_member_of, :object => "info:fedora/container:B") )
      containers_result = local_node.containers_ids
      containers_result.should be_instance_of(Array)
      containers_result.should include("container:A")
      containers_result.should include("container:B")
    end
    
    class MockHasRelationship < SpecNode2
      has_relationship "testing", :has_part, :type=>SpecNode2
      has_relationship "testing2", :has_member, :type=>SpecNode2
      has_relationship "testing_inbound", :has_part, :type=>SpecNode2, :inbound=>true
    end
      
    #can only duplicate predicates if not both inbound or not both outbound
=begin
    class MockHasRelationshipDuplicatePredicate < SpecNode2
      has_relationship "testing", :has_member, :type=>SpecNode2
      had_exception = false
      begin
        has_relationship "testing2", :has_member, :type=>SpecNode2
      rescue
        had_exception = true
      end
      raise "Did not raise exception if duplicate predicate used" unless had_exception 
    end
=end

=begin      
    #can only duplicate predicates if not both inbound or not both outbound
    class MockHasRelationshipDuplicatePredicate2 < SpecNode2
      has_relationship "testing", :has_member, :type=>SpecNode2, :inbound=>true
      had_exception = false
      begin
        has_relationship "testing2", :has_member, :type=>SpecNode2, :inbound=>true
      rescue
        had_exception = true
      end
      raise "Did not raise exception if duplicate predicate used" unless had_exception 
    end
=end
      
    it 'should create relationship descriptions both inbound and outbound' do
      @test_object2 = MockHasRelationship.new
      @test_object2.pid = increment_pid
      @test_object2.stubs(:testing_inbound).returns({})
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_model,:object=>ActiveFedora::ContentModel.pid_from_ruby_class(SpecNode2)})
      @test_object2.add_relationship(r)
      @test_object2.should respond_to(:testing_append)
      @test_object2.should respond_to(:testing_remove)
      @test_object2.should respond_to(:testing2_append)
      @test_object2.should respond_to(:testing2_remove)
      #make sure append/remove method not created for inbound rel
      @test_object2.should_not respond_to(:testing_inbound_append)
      @test_object2.should_not respond_to(:testing_inbound_remove)
      
      @test_object2.relationships_desc.should == 
      {:inbound=>{"testing_inbound"=>{:type=>SpecNode2, 
                                     :predicate=>:has_part, 
                                      :inbound=>true, 
                                      :singular=>nil}}, 
       :self=>{"testing"=>{:type=>SpecNode2, 
                           :predicate=>:has_part, 
                           :inbound=>false, 
                           :singular=>nil},
               "testing2"=>{:type=>SpecNode2, 
                            :predicate=>:has_member, 
                            :inbound=>false, 
                            :singular=>nil}}}
    end
  end
    
  describe '#create_inbound_relationship_finders' do
    
    class AudioRecord; end;
    it 'should respond to #create_inbound_relationship_finders' do
      SpecNode.should respond_to(:create_inbound_relationship_finders)
    end
    
    it "should create finders based on provided relationship name" do
      SpecNode.create_inbound_relationship_finders("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new
      local_node.should respond_to(:parts_ids)
      local_node.should_not respond_to(:containers)
      SpecNode.create_inbound_relationship_finders("containers", :is_member_of, :inbound => true)  
      local_node.should respond_to(:containers_ids)
      local_node.should respond_to(:containers)
      local_node.should respond_to(:containers_from_solr)
      local_node.should respond_to(:containers_query)
    end
    
    it "resulting finder should search against solr and use Model#load_instance to build an array of objects" do
      solr_result = (mock("solr result", :is_a? => true, :hits => @sample_solr_hits))
      #mock_repo = mock("repo")
      # mock_repo.expects(:find_model).with("_PID1_", "AudioRecord").returns("AR1")
      # mock_repo.expects(:find_model).with("_PID2_", "AudioRecord").returns("AR2")
      # mock_repo.expects(:find_model).with("_PID3_", "AudioRecord").returns("AR3")


      SpecNode.create_inbound_relationship_finders("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new()
      local_node.expects(:loaded_fedora_properties).returns(false)
      local_node.expects(:load_fedora_properties)
      local_node.expects(:pid).returns("test:sample_pid")
      SpecNode.expects(:relationships_desc).returns({:inbound=>{"parts"=>{:predicate=>:is_part_of}}}).at_least_once()
      ActiveFedora::SolrService.instance.conn.expects(:query).with("is_part_of_s:info\\:fedora/test\\:sample_pid", :rows=>25).returns(solr_result)
      # Fedora::Repository.expects(:instance).returns(mock_repo).times(3)
      Kernel.expects(:const_get).with("AudioRecord").returns(AudioRecord).times(3)
      AudioRecord.expects(:desolrize).with(@sample_solr_hits[0]).returns("AR1")
      AudioRecord.expects(:desolrize).with(@sample_solr_hits[1]).returns("AR2")
      AudioRecord.expects(:desolrize).with(@sample_solr_hits[2]).returns("AR3")
      local_node.parts.should == ["AR1", "AR2", "AR3"]
    end
    
    it "resulting finder should accept :solr as :response_format value and return the raw Solr Result" do
      solr_result = mock("solr result")
      SpecNode.create_inbound_relationship_finders("constituents", :is_constituent_of, :inbound => true)
      local_node = SpecNode.new
      local_node.expects(:loaded_fedora_properties).returns(false)
      local_node.expects(:load_fedora_properties)
      mock_repo = mock("repo")
      mock_repo.expects(:find_model).never
      local_node.expects(:pid).returns("test:sample_pid")
      SpecNode.expects(:relationships_desc).returns({:inbound=>{"constituents"=>{:predicate=>:is_constituent_of}}}).at_least_once()
      ActiveFedora::SolrService.instance.conn.expects(:query).with("is_constituent_of_s:info\\:fedora/test\\:sample_pid", :rows=>101).returns(solr_result)
      local_node.constituents(:response_format => :solr, :rows=>101).should equal(solr_result)
    end
    
    
    it "resulting _ids finder should search against solr and return an array of fedora PIDs" do
      SpecNode.create_inbound_relationship_finders("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new
      local_node.expects(:loaded_fedora_properties).returns(false)
      local_node.expects(:load_fedora_properties)
      local_node.expects(:pid).returns("test:sample_pid")
      SpecNode.expects(:relationships_desc).returns({:inbound=>{"parts"=>{:predicate=>:is_part_of}}}).at_least_once() 
      ActiveFedora::SolrService.instance.conn.expects(:query).with("is_part_of_s:info\\:fedora/test\\:sample_pid", :rows=>25).returns(mock("solr result", :hits => [Hash["id"=>"pid1"], Hash["id"=>"pid2"]]))
      local_node.parts(:response_format => :id_array).should == ["pid1", "pid2"]
    end
    
    it "resulting _ids finder should call the basic finder with :result_format => :id_array" do
      SpecNode.create_inbound_relationship_finders("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new
      local_node.expects(:parts).with(:response_format => :id_array)
      local_node.parts_ids
    end

    it "resulting _query finder should call relationship_query" do
      SpecNode.create_inbound_relationship_finders("parts", :is_part_of, :inbound => true)
      local_node = SpecNode.new
      local_node.expects(:relationship_query).with("parts")
      local_node.parts_query
    end
    
    it "resulting finder should provide option of filtering results by :type"
  end
  
  describe '#create_outbound_relationship_finders' do
    
    it 'should respond to #create_outbound_relationship_finders' do
      SpecNode.should respond_to(:create_outbound_relationship_finders)
    end
    
    it "should create finders based on provided relationship name" do
      SpecNode.create_outbound_relationship_finders("parts", :is_part_of)
      local_node = SpecNode.new
      local_node.should respond_to(:parts_ids)
      #local_node.should respond_to(:parts)  #.with(:type => "AudioRecord")  
      local_node.should_not respond_to(:containers)
      SpecNode.create_outbound_relationship_finders("containers", :is_member_of)  
      local_node.should respond_to(:containers_ids)
      local_node.should respond_to(:containers)  
      local_node.should respond_to(:containers_from_solr)  
      local_node.should respond_to(:containers_query)
    end
    
    describe " resulting finder" do
      it "should read from relationships array and use Repository.find_model to build an array of objects" do
        SpecNode.create_outbound_relationship_finders("containers", :is_member_of)
        local_node = SpecNode.new
        local_node.expects(:loaded_fedora_properties).returns(false)
        local_node.expects(:load_fedora_properties)
        local_node.expects(:outbound_relationships).returns({:is_member_of => ["my:_PID1_", "my:_PID2_", "my:_PID3_"]}).times(2)      
        local_node.expects(:new_object?).returns(false)
        mock_repo = mock("repo")
        solr_result = mock("solr result", :is_a? => true)
        sample_solr_hits = [{"id"=> "my:_PID1_", "has_model_s"=>["info:fedora/afmodel:SpecNode"]},
                       {"id"=> "my:_PID2_", "has_model_s"=>["info:fedora/afmodel:SpecNode"]}, 
                       {"id"=> "my:_PID3_", "has_model_s"=>["info:fedora/afmodel:SpecNode"]}]
        solr_result.expects(:hits).returns(sample_solr_hits)

        ActiveFedora::SolrService.instance.conn.expects(:query).with("id:my\\:_PID1_ OR id:my\\:_PID2_ OR id:my\\:_PID3_").returns(solr_result)
        SpecNode.expects(:desolrize).with(sample_solr_hits[0]).returns("AR1")
        SpecNode.expects(:desolrize).with(sample_solr_hits[1]).returns("AR2")
        SpecNode.expects(:desolrize).with(sample_solr_hits[2]).returns("AR3")
        local_node.containers.should == ["AR1", "AR2", "AR3"]
      end
    
      it "should accept :solr as :response_format value and return the raw Solr Result" do
        solr_result = mock("solr result")
        SpecNode.create_outbound_relationship_finders("constituents", :is_constituent_of)
        local_node = SpecNode.new
        local_node.expects(:loaded_fedora_properties).returns(false)
        local_node.expects(:load_fedora_properties)
        local_node.expects(:new_object?).returns(false)
        mock_repo = mock("repo")
        mock_repo.expects(:find_model).never
        local_node.stubs(:internal_uri)
        ActiveFedora::SolrService.instance.conn.expects(:query).returns(solr_result)
        local_node.constituents(:response_format => :solr).should equal(solr_result)
      end
      
      it "(:response_format => :id_array) should read from relationships array" do
        SpecNode.create_outbound_relationship_finders("containers", :is_member_of)
        local_node = SpecNode.new
        local_node.expects(:loaded_fedora_properties).returns(false)
        local_node.expects(:load_fedora_properties)
        local_node.expects(:outbound_relationships).returns({:is_member_of => []}).times(2)
        local_node.expects(:new_object?).returns(false)
        local_node.containers_ids
      end
    
      it "(:response_format => :id_array) should return an array of fedora PIDs" do
        SpecNode.create_outbound_relationship_finders("containers", :is_member_of)
        local_node = SpecNode.new
        local_node.expects(:loaded_fedora_properties).returns(false)
        local_node.expects(:load_fedora_properties)
        local_node.add_relationship(@test_relationship1)
        local_node.expects(:new_object?).returns(false)
        result = local_node.containers_ids
        result.should be_instance_of(Array)
        result.should include("demo:10")
      end
      
      it "should provide option of filtering results by :type"
    end
    
    describe " resulting _ids finder" do
      it "should call the basic finder with :result_format => :id_array" do
        SpecNode.create_outbound_relationship_finders("parts", :is_part_of)
        local_node = SpecNode.new
        local_node.expects(:parts).with(:response_format => :id_array)
        local_node.parts_ids
      end
    end

    it "resulting _query finder should call relationship_query" do
      SpecNode.create_outbound_relationship_finders("containers", :is_member_of)
      local_node = SpecNode.new
      local_node.expects(:relationship_query).with("containers")
      local_node.containers_query
    end
  end
  
  describe ".create_bidirectional_relationship_finder" do
    before(:each) do
      SpecNode.create_bidirectional_relationship_finders("all_parts", :has_part, :is_part_of)
      @local_node = SpecNode.new
      @local_node.pid = @pid
      @local_node.internal_uri = @uri
    end
    it "should create inbound & outbound finders" do
      @local_node.should respond_to(:all_parts_inbound)
      @local_node.should respond_to(:all_parts_outbound)
    end
    it "should rely on inbound & outbound finders" do      
      @local_node.expects(:all_parts_inbound).with(:rows => 25).returns(["foo1"])
      @local_node.expects(:all_parts_outbound).with(:rows => 25).returns(["foo2"])
      @local_node.all_parts.should == ["foo1", "foo2"]
    end
    it "(:response_format => :id_array) should rely on inbound & outbound finders" do
      @local_node.expects(:all_parts_inbound).with(:response_format=>:id_array, :rows => 34).returns(["fooA"])
      @local_node.expects(:all_parts_outbound).with(:response_format=>:id_array, :rows => 34).returns(["fooB"])
      @local_node.all_parts(:response_format=>:id_array, :rows => 34).should == ["fooA", "fooB"]
    end
    it "(:response_format => :solr) should construct a solr query that combines inbound and outbound searches" do
      # get the id array for outbound relationships then construct solr query by combining id array with inbound relationship search
      @local_node.expects(:outbound_relationships).returns({:has_part=>["mypid:1"]}).at_least_once()
      id_array_query = ActiveFedora::SolrService.construct_query_for_pids(["mypid:1"])
      solr_result = mock("solr result")
      ActiveFedora::SolrService.instance.conn.expects(:query).with("#{id_array_query} OR (is_part_of_s:info\\:fedora/test\\:sample_pid)", :rows=>25).returns(solr_result)
      @local_node.all_parts(:response_format=>:solr)
    end

    it "should register both inbound and outbound predicate components" do
      @local_node.relationships[:inbound].has_key?(:is_part_of).should == true
      @local_node.relationships[:self].has_key?(:has_part).should == true
    end
  
    it "should register relationship names for inbound, outbound" do
      @local_node.relationship_names.include?("all_parts_inbound").should == true
      @local_node.relationship_names.include?("all_parts_outbound").should == true
    end

    it "should register finder methods for the bidirectional relationship name" do
      @local_node.should respond_to(:all_parts)
      @local_node.should respond_to(:all_parts_ids)
      @local_node.should respond_to(:all_parts_query)
      @local_node.should respond_to(:all_parts_from_solr)
    end

    it "resulting _query finder should call relationship_query" do
      SpecNode.create_bidirectional_relationship_finders("containers", :is_member_of, :has_member)
      local_node = SpecNode.new
      local_node.expects(:relationship_query).with("containers")
      local_node.containers_query
    end
  end
  
  describe "#has_bidirectional_relationship" do
    it "should ..." do
      SpecNode.expects(:create_bidirectional_relationship_finders).with("all_parts", :has_part, :is_part_of, {})
      SpecNode.has_bidirectional_relationship("all_parts", :has_part, :is_part_of)
    end

    it "should have relationships_by_name and relationships hashes contain bidirectionally related objects" do
      SpecNode.has_bidirectional_relationship("all_parts", :has_part, :is_part_of)
      @local_node = SpecNode.new
      @local_node.pid = "mypid1"
      @local_node2 = SpecNode.new
      @local_node2.pid = "mypid2"
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_model,:object=>ActiveFedora::ContentModel.pid_from_ruby_class(SpecNode)}) 
      @local_node.add_relationship(r)
      @local_node2.add_relationship(r)
      r2 = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>@local_node2})
      @local_node.add_relationship(r2)
      r3 = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>@local_node})
      @local_node2.add_relationship(r3)
      @local_node.relationships.should == {:self=>{:has_model=>[r.object],:has_part=>[r2.object]},:inbound=>{:is_part_of=>[]}}
      @local_node2.relationships.should == {:self=>{:has_model=>[r.object],:has_part=>[r3.object]},:inbound=>{:is_part_of=>[]}}
      @local_node.relationships_by_name.should == {:self=>{"all_parts_outbound"=>[r2.object]},:inbound=>{"all_parts_inbound"=>[]}}
      @local_node2.relationships_by_name.should == {:self=>{"all_parts_outbound"=>[r3.object]},:inbound=>{"all_parts_inbound"=>[]}}
    end
  end
  
  describe ".add_relationship" do
    it "should add relationship to the relationships hash" do
      @node.add_relationship(@test_relationship)
      @node.relationships.should have_key(@test_relationship.subject) 
      @node.relationships[@test_relationship.subject].should have_key(@test_relationship.predicate)
      @node.relationships[@test_relationship.subject][@test_relationship.predicate].should include(@test_relationship.object)
    end
    
    it "adding relationship to an instance should not affect class-level relationships hash" do 
      local_test_node1 = SpecNode.new
      local_test_node2 = SpecNode.new
      local_test_node1.add_relationship(@test_relationship1)
      #local_test_node2.add_relationship(@test_relationship2)
      
      local_test_node1.relationships[:self][:is_member_of].should == ["info:fedora/demo:10"]      
      local_test_node2.relationships[:self][:is_member_of].should be_nil
    end
    
  end
  
  describe '#relationships' do
    
    it "should return a hash" do
      SpecNode.relationships.class.should == Hash
    end

  end

    
  it "should provide a relationship setter"
  it "should provide a relationship getter"
  it "should provide a relationship deleter"
      
  describe '.register_triple' do
    it 'should add triples to the relationships hash' do
      @node.register_triple(:self, :is_part_of, "info:fedora/demo:10")
      @node.register_triple(:self, :is_member_of, "info:fedora/demo:11")
      @node.relationships[:self].should have_key(:is_part_of)
      @node.relationships[:self].should have_key(:is_member_of)
      @node.relationships[:self][:is_part_of].should include("info:fedora/demo:10")
      @node.relationships[:self][:is_member_of].should include("info:fedora/demo:11")
    end
    
    it "should not be a class level method"
  end
  
  it 'should provide #predicate_lookup that maps symbols to common RELS-EXT predicates' do
    SpecNode.should respond_to(:predicate_lookup)
    SpecNode.predicate_lookup(:is_part_of).should == "isPartOf"
    SpecNode.predicate_lookup(:is_member_of).should == "isMemberOf"
    SpecNode.predicate_lookup("isPartOfCollection").should == "isPartOfCollection"
    SpecNode.predicate_config[:predicate_mapping].merge!({"some_namespace"=>{:has_foo=>"hasFOO"}})
    SpecNode.find_predicate(:has_foo).should == ["hasFOO","some_namespace"]
    SpecNode.predicate_lookup(:has_foo,"some_namespace").should == "hasFOO"
    #SpecNode.predicate_lookup(:has_foo)
    lambda { SpecNode.predicate_lookup(:has_foo) }.should raise_error ActiveFedora::UnregisteredPredicateError
  end
  
  describe '#to_rels_ext' do
    
    before(:all) do
      @sample_rels_ext_xml = <<-EOS
      <rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'>
        <rdf:Description rdf:about='info:fedora/test:sample_pid'>
          <isMemberOf rdf:resource='info:fedora/demo:10' xmlns='info:fedora/fedora-system:def/relations-external#'/>
          <isPartOf rdf:resource='info:fedora/demo:11' xmlns='info:fedora/fedora-system:def/relations-external#'/>
          <hasPart rdf:resource='info:fedora/demo:12' xmlns='info:fedora/fedora-system:def/relations-external#'/>
          <hasModel rdf:resource='info:fedora/afmodel:OtherModel' xmlns='info:fedora/fedora-system:def/model#'/>
          <hasModel rdf:resource='info:fedora/afmodel:SampleModel' xmlns='info:fedora/fedora-system:def/model#'/>
        </rdf:Description>
      </rdf:RDF>
      EOS
    end
    
    it 'should serialize the relationships array to Fedora RELS-EXT rdf/xml' do
      @node.add_relationship(@test_relationship1)
      @node.add_relationship(@test_relationship2)
      @node.add_relationship(@test_relationship3)
      @node.add_relationship(@test_cmodel_relationship1)
      @node.add_relationship(@test_cmodel_relationship2)
      @node.internal_uri = @uri
      # returned_xml = XmlSimple.xml_in(@node.to_rels_ext(@pid))
      # returned_xml.should == XmlSimple.xml_in(@sample_rels_ext_xml)
      EquivalentXml.equivalent?(@node.to_rels_ext(@pid), @sample_rels_ext_xml).should be_true
    end
    
    it "should treat :self and self.pid as equivalent subjects"
  end
  
  it 'should provide #relationships_to_rdf_xml' 

  describe '#relationships_to_rdf_xml' do
    it 'should serialize the relationships array to rdf/xml'
  end
  
  it "should provide .outbound_relationships" do 
    @node.should respond_to(:outbound_relationships)
  end
  
    
  it 'should provide #unregister_triple' do
    @test_object.should respond_to(:unregister_triple)
  end
  
  describe '#unregister_triple' do
    it 'should remove a triple from the relationships hash' do
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>"info:fedora/3"})
      r2 = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>"info:fedora/4"})
      @test_object.add_relationship(r)
      @test_object.add_relationship(r2)
      #check both are there
      @test_object.relationships.should == {:self=>{:has_part=>[r.object,r2.object]}}
      @test_object.unregister_triple(r.subject,r.predicate,r.object)
      #check returns false if relationship does not exist and does nothing
      @test_object.unregister_triple(:self,:has_member,r2.object).should == false
      #check only one item removed
      @test_object.relationships.should == {:self=>{:has_part=>[r2.object]}}
      @test_object.unregister_triple(r2.subject,r2.predicate,r2.object)
      #check last item removed and predicate removed since now emtpy
      @test_object.relationships.should == {:self=>{}}
      
    end
  end

  it 'should provide #remove_relationship' do
    @test_object.should respond_to(:remove_relationship)
  end

  describe '#remove_relationship' do
    it 'should remove a relationship from the relationships hash' do
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>"info:fedora/3"})
      r2 = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_part,:object=>"info:fedora/4"})
      @test_object.add_relationship(r)
      @test_object.add_relationship(r2)
      #check both are there
      @test_object.relationships.should == {:self=>{:has_part=>[r.object,r2.object]}}
      @test_object.remove_relationship(r)
      #check returns false if relationship does not exist and does nothing with different predicate
      rBad = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_member,:object=>"info:fedora/4"})
      @test_object.remove_relationship(rBad).should == false
      #check only one item removed
      @test_object.relationships.should == {:self=>{:has_part=>[r2.object]}}
      @test_object.remove_relationship(r2)
      #check last item removed and predicate removed since now emtpy
      @test_object.relationships.should == {:self=>{}}
      
    end
  end
  
  it 'should provide #relationship_exists?' do
    @test_object.should respond_to(:relationship_exists?)
  end
  
  describe '#relationship_exists?' do
    it 'should return true if a relationship does exist' do
      @test_object3 = SpecNode2.new
      @test_object3.pid = increment_pid
      r = ActiveFedora::Relationship.new({:subject=>:self,:predicate=>:has_member,:object=>@test_object3})
      @test_object.relationship_exists?(r.subject,r.predicate,r.object).should == false
      @test_object.add_relationship(r)
      @test_object.relationship_exists?(r.subject,r.predicate,r.object).should == true
    end
  end

  it 'should provide #assert_kind_of' do
    @test_object.should respond_to(:assert_kind_of)
  end

  describe '#assert_kind_of' do
    it 'should raise an exception if object supplied is not the correct type' do
      had_exception = false
      begin
        @test_object.assert_kind_of 'SpecNode2', @test_object, ActiveFedora::Base
      rescue
        had_exception = true
      end
      raise "Failed to throw exception with kind of mismatch" unless had_exception
      #now should not throw any exception
      @test_object.assert_kind_of 'SpecNode2', @test_object, SpecNode2
    end
  end
end
