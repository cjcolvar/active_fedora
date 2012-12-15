require 'spec_helper'

describe ActiveFedora::FieldMapper do
  
  # --- Test Mappings ----
  
  class TestMapper0 < ActiveFedora::FieldMapper 
    id_field 'ident'
    index_as :searchable, :suffix => '_s',    :default => true
    index_as :edible,     :suffix => '_food'
    index_as :laughable,  :suffix => '_haha', :default => true do |type|
      type.integer :suffix => '_ihaha' do |value, field_name|
        "How many #{field_name}s does it take to screw in a light bulb? #{value.capitalize}."
      end
      type.default do |value|
        "Knock knock. Who's there? #{value.capitalize}. #{value.capitalize} who?"
      end
    end
    index_as :fungible, :suffix => '_f0' do |type|
      type.integer :suffix => '_f1'
      type.date
      type.default :suffix => '_f2'
    end
    index_as :unstemmed_searchable, :suffix => '_s' do |type|
      type.date do |value|
        "#{value} o'clock"
      end
    end
  end
  
  class TestMapper1 < TestMapper0
    index_as :searchable do |type|
      type.date :suffix => '_d'
    end
    index_as :fungible, :suffix => '_f3' do |type|
      type.garble  :suffix => '_f4'
      type.integer :suffix => '_f5'
    end
  end
  
  after(:all) do
  end
  
  # --- Tests ----
  
  it "should handle the id field" do
    TestMapper0.id_field_name.should == 'ident'
  end
  
  describe '.solr_name' do

    it "should map based on index_as" do
      TestMapper0.solr_name('bar', :string, :edible).should == 'bar_food'
      TestMapper0.solr_name('bar', :string, :laughable).should == 'bar_haha'
    end

    it "should default the index_type to :searchable" do
      TestMapper0.solr_name('foo', :string).should == 'foo_s'
    end
    
    it "should map based on data type" do
      TestMapper0.solr_name('foo', :integer, :fungible).should == 'foo_f1'
      TestMapper0.solr_name('foo', :garble,  :fungible).should == 'foo_f2'  # based on type.default
      TestMapper0.solr_name('foo', :date,    :fungible).should == 'foo_f0'  # type.date falls through to container
    end
  
    it "should return nil for an unknown index types" do
      TestMapper0.solr_name('foo', :string, :blargle).should == nil
    end
    
    it "should allow subclasses to selectively override suffixes" do
      TestMapper1.solr_name('foo', :date).should == 'foo_d'   # override
      TestMapper1.solr_name('foo', :string).should == 'foo_s' # from super
      TestMapper1.solr_name('foo', :integer, :fungible).should == 'foo_f5'  # override on data type
      TestMapper1.solr_name('foo', :garble,  :fungible).should == 'foo_f4'  # override on data type
      TestMapper1.solr_name('foo', :fratz,   :fungible).should == 'foo_f2'  # from super
      TestMapper1.solr_name('foo', :date,    :fungible).should == 'foo_f3'  # super definition picks up override on index type
    end
    
    it "should support field names as symbols" do
      TestMapper0.solr_name(:active_fedora_model, :symbol).should == "active_fedora_model_s"
    end
    
    it "should support scenarios where field_type is nil" do
      ActiveFedora::FieldMapper::Default.solr_name(:heifer, nil, :searchable).should == "heifer_t"
    end
  end
  
  describe '.solr_names_and_values' do

    it "should map values based on index_as" do
      TestMapper0.solr_names_and_values('foo', 'bar', :string, [:searchable, :laughable, :edible]).should == {
        'foo_s'    => ['bar'],
        'foo_food' => ['bar'],
        'foo_haha' => ["Knock knock. Who's there? Bar. Bar who?"]
      }
    end
    
    it "should apply default index_as mapping unless excluded with not_" do
      TestMapper0.solr_names_and_values('foo', 'bar', :string, []).should == {
        'foo_s' => ['bar'],
        'foo_haha' => ["Knock knock. Who's there? Bar. Bar who?"]
      }
      TestMapper0.solr_names_and_values('foo', 'bar', :string, [:edible, :not_laughable]).should == {
        'foo_s' => ['bar'],
        'foo_food' => ['bar']
      }
      TestMapper0.solr_names_and_values('foo', 'bar', :string, [:not_searchable, :not_laughable]).should == {}
    end
  
    it "should apply mappings based on data type" do
      TestMapper0.solr_names_and_values('foo', 'bar', :integer, [:searchable, :laughable]).should == {
        'foo_s'     => ['bar'],
        'foo_ihaha' => ["How many foos does it take to screw in a light bulb? Bar."]
      }
    end
    
    it "should skip unknown index types" do
        TestMapper0.solr_names_and_values('foo', 'bar', :string, [:blargle]).should == {
          'foo_s' => ['bar'],
          'foo_haha' => ["Knock knock. Who's there? Bar. Bar who?"]
        }
    end
    
    it "should generate multiple mappings when two return the _same_ solr name but _different_ values" do
      TestMapper0.solr_names_and_values('roll', 'rock', :date, [:unstemmed_searchable, :not_laughable]).should == {
        'roll_s' => ["rock o'clock", 'rock']
      }
    end
    
    it "should not generate multiple mappings when two return the _same_ solr name and the _same_ value" do
      TestMapper0.solr_names_and_values('roll', 'rock', :string, [:unstemmed_searchable, :not_laughable]).should == {
        'roll_s' => ['rock'],
      }
    end
  end

  describe ActiveFedora::FieldMapper::Default do

    it "should call the id field 'id'" do
      ActiveFedora::FieldMapper::Default.id_field_name.should == 'id'
    end
    
    it "should apply mappings for searchable by default" do
      # Just sanity check a couple; copy & pasting all data types is silly
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', 'bar', :string, []).should == { 'foo_t' => ['bar'] }
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', "1", :integer, []).should == { 'foo_i' =>["1"] }
    end

    it "should support full ISO 8601 dates" do
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', "2012-11-06",              :date, []).should == { 'foo_dt' =>["2012-11-06T00:00:00Z"] }
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', "November 6th, 2012",      :date, []).should == { 'foo_dt' =>["2012-11-06T00:00:00Z"] }
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', Date.parse("6 Nov. 2012"), :date, []).should == { 'foo_dt' =>["2012-11-06T00:00:00Z"] }
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', '', :date, []).should == { 'foo_dt' => [] }
    end
    
    it "should support displayable, facetable, sortable, unstemmed" do
      ActiveFedora::FieldMapper::Default.solr_names_and_values('foo', 'bar', :string, [:displayable, :facetable, :sortable, :unstemmed_searchable]).should == {
        'foo_t' => ['bar'],
        'foo_display' => ['bar'],
        'foo_facet' => ['bar'],
        'foo_sort' => ['bar'],
        'foo_unstem_search' => ['bar'],
      }
    end
  end
  
end
