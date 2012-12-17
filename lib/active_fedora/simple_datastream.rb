module ActiveFedora
  #This class represents a simple xml datastream. 
  class SimpleDatastream < NokogiriDatastream

    class_attribute :class_fields
    self.class_fields = []
    
    
     set_terminology do |t|
       t.root(:path=>"fields", :xmlns=>nil)
     end

    define_template :creator do |xml,name|
      xml.creator() do
        xml.text(name)
      end
    end
    

    # This method generates the various accessor and mutator methods on self for the datastream metadata attributes.
    # each field will have the 2 magic methods:
    #   name=(arg) 
    #   name 
    #
    #
    # 'datatype' is a datatype, currently :string, :integer and :date are supported.
    #
    # opts is an options hash, which  will affect the generation of the xml representation of this datastream.
    #
    # Currently supported modifiers: 
    # For +SimpleDatastream+:
    #   :element_attrs =>{:foo=>:bar} -  hash of xml element attributes
    #   :xml_node => :nodename  - The xml node to be used to represent this object (in dcterms namespace)
    #   :encoding=>foo, or encodings_scheme  - causes an xsi:type attribute to be set to 'foo'
    #   :multiple=>true -  mark this field as a multivalue field (on by default)
    #
    #
    #There is quite a good example of this class in use in spec/examples/oral_history.rb
    #
    #!! Careful: If you declare two fields that correspond to the same xml node without any qualifiers to differentiate them, 
    #you will end up replicating the values in the underlying datastream, resulting in mysterious dubling, quadrupling, etc. 
    #whenever you edit the field's values.
    def field(name, datatype=nil, opts={})
      fields ||= {}
      @fields[name.to_s.to_sym]={:type=>datatype, :values=>[]}.merge(opts)
      # add term to template
      self.class.class_fields << name.to_s
      # add term to terminology
      unless self.class.terminology.has_term?(name.to_sym)
        term = OM::XML::Term.new(name.to_sym, {:type=>datatype}, self.class.terminology)
        self.class.terminology.add_term(term)
        term.generate_xpath_queries!
      end
      
    end
    
    def update_indexed_attributes(params={}, opts={})
      # if the params are just keys, not an array, make then into an array.
      new_params = {}
      params.each do |key, val|
        if key.is_a? Array
          new_params[key] = val
        else
          new_params[[key.to_sym]] = val
        end
      end
      super(new_params, opts)
    end
    

    def self.xml_template
       Nokogiri::XML::Document.parse("<fields/>")
    end

    def to_solr(solr_doc = Hash.new) # :nodoc:
      @fields.each do |field_key, field_info|
        next if field_key == :location ## FIXME HYDRA-825
        things = send(field_key)
        next if things.nil?
        things.val.each do |val|
          next if val.nil?
          SolrService.solr_names_and_values(field_key, val, field_info[:type]).each do |field_name, field_value|
            (solr_doc[field_name] ||= []) << field_value.join(" ")
          end
        end
      end
      return solr_doc
    end

  end
end
