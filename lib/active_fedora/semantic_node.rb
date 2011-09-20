module ActiveFedora
  module SemanticNode 
    extend ActiveSupport::Concern
    included do
      class_inheritable_accessor  :class_relationships, :internal_uri, :class_named_relationships_desc
      self.class_relationships = {}
      self.class_named_relationships_desc = {}
    end
    attr_accessor :internal_uri, :named_relationship_desc, :relationships_are_dirty, :load_from_solr
    #TODO I think we can remove named_relationship_desc from attr_accessor  - jcoyne

    def assert_kind_of(n, o,t)
      raise "Assertion failure: #{n}: #{o} is not of type #{t}" unless o.kind_of?(t)
    end
    
    def add_relationship(relationship)
      # Only accept ActiveFedora::Relationships as input arguments
      assert_kind_of 'relationship',  relationship, ActiveFedora::Relationship
      self.relationships_are_dirty = true
      register_triple(relationship.subject, relationship.predicate, relationship.object)
    end
    
    def register_triple(subject, predicate, object)
      register_subject(subject)
      register_predicate(subject, predicate)
      relationships[subject][predicate] << object
    end
    
    def register_subject(subject)
      if !relationships.has_key?(subject) 
          relationships[subject] = {} 
      end
    end
  
    def register_predicate(subject, predicate)
      register_subject(subject)
      if !relationships[subject].has_key?(predicate) 
        relationships[subject][predicate] = []
      end
    end

    # ** EXPERIMENTAL **
    # 
    # Remove the given ActiveFedora::Relationship from this object
    def remove_relationship(relationship)
      @relationships_are_dirty = true
      unregister_triple(relationship.subject, relationship.predicate, relationship.object)
    end

    # ** EXPERIMENTAL **
    # 
    # Remove the subject, predicate, and object triple from the relationships hash
    def unregister_triple(subject, predicate, object)
      if relationship_exists?(subject, predicate, object)
        relationships[subject][predicate].delete_if {|curObj| curObj == object}
        relationships[subject].delete(predicate) if relationships[subject][predicate].nil? || relationships[subject][predicate].empty? 
      else
        return false
      end     
    end
    
    # ** EXPERIMENTAL **
    # 
    # Returns true if a relationship exists for the given subject, predicate, and object triple
    def relationship_exists?(subject, predicate, object)
      outbound_only = (subject != :inbound)
      #cache the call in case it is retrieving inbound as well, don't want to hit solr too many times
      cached_relationships = relationships(outbound_only)
      cached_relationships.has_key?(subject)&&cached_relationships[subject].has_key?(predicate)&&cached_relationships[subject][predicate].include?(object)
    end

    def inbound_relationships(response_format=:uri)
      rel_values = {}
      inbound_relationship_predicates.each_pair do |name,predicate|
        objects = self.send("#{name}",{:response_format=>response_format})
        items = []
        objects.each do |object|
          if (response_format == :uri)    
            #create a Relationship object so that it generates the appropriate uri
            #inbound relationships are always object properties
            r = ActiveFedora::Relationship.new(:subject=>:self, :predicate=>predicate, :object=>object)
            items.push(r.object)
          else
            items.push(object)
          end
        end
        unless items.empty?
          rel_values.merge!({predicate=>items})
        end
      end
      return rel_values  
    end
    
    def outbound_relationships()
      if !internal_uri.nil? && !relationships[internal_uri].nil?
        return relationships[:self].merge(relationships[internal_uri]) 
      else
        return relationships[:self]
      end
    end
    
    # If outbound_only is false, inbound relationships will be included.
    def relationships(outbound_only=true)
      @relationships ||= relationships_from_class
      outbound_only ? @relationships : @relationships.merge(:inbound=>inbound_relationships)
    end
    
    def relationships_from_class
      rels = {}
      self.class.relationships.each_pair do |subj, pred|
        rels[subj] = {}
        pred.each_key do |pred_key|
          rels[subj][pred_key] = []
        end
      end
      return rels
    end
    
    # Creates a RELS-EXT datastream for insertion into a Fedora Object
    # @param [String] pid
    # @param [Hash] relationships (optional) @default self.relationships
    # Note: This method is implemented on SemanticNode instead of RelsExtDatastream because SemanticNode contains the relationships array
    def to_rels_ext(pid, relationships=self.relationships)
      starter_xml = <<-EOL
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="info:fedora/#{pid}">
        </rdf:Description>
      </rdf:RDF>
      EOL
      xml = REXML::Document.new(starter_xml)
    
      # Iterate through the hash of predicates, adding an element to the RELS-EXT for each "object" in the predicate's corresponding array.
      self.outbound_relationships.each do |predicate, targets_array|
        targets_array.each do |target|
          xmlns=String.new
          case predicate
          when :has_model, "hasModel", :hasModel
            xmlns="info:fedora/fedora-system:def/model#"
            begin
              rel_predicate = self.class.predicate_lookup(predicate,xmlns)
            rescue UnregisteredPredicateError
              xmlns = nil
              rel_predicate = nil
            end
          else
            xmlns="info:fedora/fedora-system:def/relations-external#"
            begin
              rel_predicate = self.class.predicate_lookup(predicate,xmlns)
            rescue UnregisteredPredicateError
              xmlns = nil
              rel_predicate = nil
            end
          end
          
          unless xmlns && rel_predicate
            rel_predicate, xmlns = self.class.find_predicate(predicate)
          end
          literal = URI.parse(target).scheme.nil?
          if literal
            xml.root.elements["rdf:Description"].add_element(rel_predicate, {"xmlns" => "#{xmlns}"}).add_text(target)
          else
            xml.root.elements["rdf:Description"].add_element(rel_predicate, {"xmlns" => "#{xmlns}", "rdf:resource"=>target})
          end
        end
      end
      xml.to_s
    end

    def load_inbound_relationship(name, predicate, opts={})
      load_fedora_properties if !loaded_fedora_properties
      opts = {:rows=>25}.merge(opts)
      query = self.class.inbound_relationship_query(self.pid,"#{name}")
      return [] if query.empty?
      solr_result = SolrService.instance.conn.query(query, :rows=>opts[:rows])
      if opts[:response_format] == :solr
        return solr_result
      else
        if opts[:response_format] == :id_array
          id_array = []
          solr_result.hits.each do |hit|
            id_array << hit[SOLR_DOCUMENT_ID]
          end
          return id_array
        elsif opts[:response_format] == :load_from_solr || self.load_from_solr
          return ActiveFedora::SolrService.reify_solr_results(solr_result,{:load_from_solr=>true})
        else
          return ActiveFedora::SolrService.reify_solr_results(solr_result)
        end
      end
    end

    def load_outbound_relationship(name, predicate, opts={})
      load_fedora_properties if !loaded_fedora_properties && !new_object?
      id_array = []
      if !outbound_relationships[predicate].nil? 
        outbound_relationships[predicate].each do |rel|
          id_array << rel.gsub("info:fedora/", "")
        end
      end
      if opts[:response_format] == :id_array  && !self.class.relationship_has_solr_filter_query?(:self,"#{name}")
        return id_array
      else
        query = self.class.outbound_relationship_query("#{name}",id_array)
        solr_result = SolrService.instance.conn.query(query)
        if opts[:response_format] == :solr
          return solr_result
        elsif opts[:response_format] == :id_array
          id_array = []
          solr_result.hits.each do |hit|
            id_array << hit[SOLR_DOCUMENT_ID]
          end
          return id_array
        elsif opts[:response_format] == :load_from_solr || self.load_from_solr
          return ActiveFedora::SolrService.reify_solr_results(solr_result,{:load_from_solr=>true})
        else
          return ActiveFedora::SolrService.reify_solr_results(solr_result)
        end
      end
    end
    
    module ClassMethods
      #include ActiveFedora::RelationshipsHelper::ClassMethods

      # Allows for a relationship to be treated like any other attribute of a model class. You define
      # relationships in your model class using this method.  You then have access to several
      # helper methods to list, append, and remove objects from the list of relationships. 
      # ====Examples to define two relationships 
      #  class AudioRecord < ActiveFedora::Base
      #
      #   has_relationship "oral_history", :has_part, :inbound=>true, :type=>OralHistory
      #   # returns all similar audio
      #   has_relationship "similar_audio", :has_part, :type=>AudioRecord
      #   #returns only similar audio with format wav
      #   has_relationship "similar_audio_wav", :has_part, :solr_fq=>"format_t:wav"
      #
      # The first two parameters are required:
      #   name: relationship name
      #   predicate: predicate for the relationship
      #   opts:
      #     possible parameters  
      #       :inbound => if true loads an external relationship via Solr (defaults to false)
      #       :type => The type of model to use when instantiated an object from the pid in this relationship (defaults to ActiveFedora::Base)
      #       :solr_fq => Define a solr query here if you want to filter out some objects in your relationship (must be a properly formatted solr query)
      #
      # If inbound is true it expects the relationship to be defined by another object's RELS-EXT
      # and to load that relationship from Solr.  Otherwise, if inbound is true the relationship is stored in
      # this object's RELS-EXT datastream
      #
      # Word of caution - The same predicate may not be used twice for two inbound or two outbound relationships.  However, it may be used twice if one is inbound
      # and one is outbound as shown in the example above.  A full list of possible predicates are defined by predicate_mappings
      #
      # For the oral_history relationship in the example above the following helper methods are created:
      #  oral_history: returns array of OralHistory objects that have this AudioRecord with predicate :has_part 
      #  oral_history_ids: Return array of pids for OralHistory objects that have this AudioRecord with predicate :has_part
      #  oral_history_query: Return solr query that can be used to retrieve related objects as solr documents
      # 
      # For the outbound relationship "similar_audio" there are two additional methods to append and remove objects from that relationship
      # since it is managed internally:
      #  similar_audio: Return array of AudioRecord objects that have been added to similar_audio relationship
      #  similar_audio_ids:  Return array of AudioRecord object pids that have been added to similar_audio relationship
      #  similar_audio_query: Return solr query that can be used to retrieve related objects as solr documents
      #  similar_audio_append: Add an AudioRecord object to the similar_audio relationship
      #  similar_audio_remove: Remove an AudioRecord from the similar_audio relationship
      def has_relationship(name, predicate, opts = {})
        opts = {:singular => nil, :inbound => false}.merge(opts)
        if opts[:inbound] == true
          #raise "Duplicate use of predicate for inbound relationship name not allowed" if predicate_exists_with_different_relationship_name?(:inbound,name,predicate)
          register_relationship_desc(:inbound, name, predicate, opts)
          register_predicate(:inbound, predicate)
          create_inbound_relationship_finders(name, predicate, opts)
        else
          #raise "Duplicate use of predicate for named outbound relationship \"#{predicate.inspect}\" not allowed" if named_predicate_exists_with_different_name?(:self,name,predicate)
          register_relationship_desc(:self, name, predicate, opts)
          register_predicate(:self, predicate)
          create_relationship_name_methods(name)
          create_outbound_relationship_finders(name, predicate, opts)
        end
      end
      
      # Generates relationship finders for predicates that point in both directions
      #
      # @param [String] name of the relationship method(s) to create
      # @param [Symbol] outbound_predicate Predicate used in outbound relationships
      # @param [Symbol] inbound_predicate Predicate used in inbound relationships
      # @param [Hash] opts
      #
      # Example:
      #  has_bidirectional_relationship("parts", :has_part, :is_part_of)
      #
      # will create three instance methods: parts_outbound, and parts_inbound and parts
      # the inbound and outbound methods are the same that would result from calling 
      # create_inbound_relationship_finders and create_outbound_relationship_finders
      # The third method combines the results of both and handles generating appropriate 
      # solr queries where necessary.
      def has_bidirectional_relationship(name, outbound_predicate, inbound_predicate, opts={})
        create_bidirectional_relationship_finders(name, outbound_predicate, inbound_predicate, opts)
      end
      
      # ** EXPERIMENTAL **
      # 
      # Check to make sure a subject,name, and predicate triple does not already exist
      # with the same subject but different name.
      # This method is used to ensure conflicting has_relationship calls are not made because
      # predicates cannot be reused across relationship names.  Otherwise, the mapping of relationship name
      # to predicate in RELS-EXT would be broken.
      def named_predicate_exists_with_different_name?(subject,name,predicate)
        if named_relationships_desc.has_key?(subject)
          named_relationships_desc[subject].each_pair do |existing_name, args|
            return true if !args[:predicate].nil? && args[:predicate] == predicate && existing_name != name 
          end
        end
        return false
      end
      
      # ** EXPERIMENTAL **
      #  
      # Return hash that stores named relationship metadata defined by has_relationship calls
      # ====Example
      # For the following relationship
      #
      #  has_relationship "audio_records", :has_part, :type=>AudioRecord
      # Results in the following returned by named_relationships_desc
      #  {:self=>{"audio_records"=>{:type=>AudioRecord, :singular=>nil, :predicate=>:has_part, :inbound=>false}}}
      def named_relationships_desc
        @class_named_relationships_desc ||= Hash[:self => {}]
        #class_named_relationships_desc
      end
      
      # ** EXPERIMENTAL **
      #   
      # Internal method that ensures a relationship subject such as :self and :inbound
      # exist within the named_relationships_desc hash tracking named relationships metadata. 
      def register_named_subject(subject)
        unless named_relationships_desc.has_key?(subject) 
          named_relationships_desc[subject] = {} 
        end
      end
  
      # ** EXPERIMENTAL **
      # 
      # Internal method that adds relationship name and predicate pair to either an outbound (:self)
      # or inbound (:inbound) relationship types.
      def register_named_relationship(subject, name, predicate, opts)
        register_named_subject(subject)
        opts.merge!({:predicate=>predicate})
        named_relationships_desc[subject][name] = opts
      end
      
      # ** EXPERIMENTAL **
      #   
      # Used in has_relationship call to create dynamic helper methods to 
      # append and remove objects to and from a named relationship
      # ====Example
      # For the following relationship
      #
      #  has_relationship "audio_records", :has_part, :type=>AudioRecord
      #
      # Methods audio_records_append and audio_records_remove are created.
      # Boths methods take an object that is kind_of? ActiveFedora::Base as a parameter
      def create_named_relationship_methods(name)
        append_method_name = "#{name.to_s.downcase}_append"
        remove_method_name = "#{name.to_s.downcase}_remove"
        self.send(:define_method,:"#{append_method_name}") {|object| add_named_relationship(name,object)}
        self.send(:define_method,:"#{remove_method_name}") {|object| remove_named_relationship(name,object)}
      end 

      #  ** EXPERIMENTAL **
      #  Similar to +create_named_relationship_methods+ except we are merely creating an alias for outbound portion of bidirectional
      #
      #  ====Example
      #    has_bidirectional_relationship "members", :has_collection_member, :is_member_of_collection
      #    
      #    Method members_outbound_append and members_outbound_remove added
      #    This method will create members_append which does same thing as members_outbound_append
      #    and will create members_remove which does same thing as members_outbound_remove
      def create_bidirectional_named_relationship_methods(name,outbound_name)
        append_method_name = "#{name.to_s.downcase}_append"
        remove_method_name = "#{name.to_s.downcase}_remove"
        self.send(:define_method,:"#{append_method_name}") {|object| add_named_relationship(outbound_name,object)}
        self.send(:define_method,:"#{remove_method_name}") {|object| remove_named_relationship(outbound_name,object)}
      end

    
      def create_inbound_relationship_finders(name, predicate, opts = {})
        class_eval <<-END
        def #{name}(opts={})
          load_inbound_relationship('#{name}', '#{predicate}', opts)
        end
        def #{name}_ids
          #{name}(:response_format => :id_array)
        end
        def #{name}_from_solr
          #{name}(:response_format => :load_from_solr)
        end
        def #{name}_query
          relationship_query("#{name}")
        end
        END
      end
    
      def create_outbound_relationship_finders(name, predicate, opts = {})
        class_eval <<-END
        def #{name}(opts={})
          load_outbound_relationship(#{name.inspect}, #{predicate.inspect}, opts)
        end
        def #{name}_ids
          #{name}(:response_format => :id_array)
        end
        def #{name}_from_solr
          #{name}(:response_format => :load_from_solr)
        end
        def #{name}_query
          relationship_query("#{name}")
        end
        END
      end
      
      # Generates relationship finders for predicates that point in both directions
      # and registers predicate relationships for each direction.
      #
      # @param [String] name Name of the relationship method(s) to create
      # @param [Symbol] outbound_predicate Predicate used in outbound relationships
      # @param [Symbol] inbound_predicate Predicate used in inbound relationships
      # @param [Hash] opts (optional)
      def create_bidirectional_relationship_finders(name, outbound_predicate, inbound_predicate, opts={})
        inbound_method_name = name.to_s+"_inbound"
        outbound_method_name = name.to_s+"_outbound"
        has_relationship(outbound_method_name, outbound_predicate, opts)
        has_relationship(inbound_method_name, inbound_predicate, opts.merge!(:inbound=>true))

        #create methods that mirror the outbound append and remove with our bidirectional name, assume just add and remove locally        
        create_bidirectional_relationship_name_methods(name,outbound_method_name)

        class_eval <<-END
        def #{name}(opts={})
          opts = {:rows=>25}.merge(opts)
          if opts[:response_format] == :solr || opts[:response_format] == :load_from_solr
            outbound_id_array = []
            predicate = outbound_relationship_predicates["#{name}_outbound"]
            if !outbound_relationships[predicate].nil? 
              outbound_relationships[predicate].each do |rel|
                outbound_id_array << rel.gsub("info:fedora/", "")
              end
            end
            #outbound_id_array = #{outbound_method_name}(:response_format=>:id_array)
            query = self.class.bidirectional_relationship_query(self.pid,"#{name}",outbound_id_array)
            solr_result = SolrService.instance.conn.query(query, :rows=>opts[:rows])
            
            if opts[:response_format] == :solr
              return solr_result
            elsif opts[:response_format] == :load_from_solr || self.load_from_solr
              return ActiveFedora::SolrService.reify_solr_results(solr_result,{:load_from_solr=>true})
            else
              return ActiveFedora::SolrService.reify_solr_results(solr_result)
            end
          else
            ary = #{inbound_method_name}(opts) + #{outbound_method_name}(opts)
            return ary.uniq
          end
        end
        def #{name}_ids
          #{name}(:response_format => :id_array)
        end
        def #{name}_from_solr
          #{name}(:response_format => :load_from_solr)
        end
        def #{name}_query
          relationship_query("#{name}")
        end
        END
      end
    
      # relationships are tracked as a hash of structure 
      # @example
      #   ds.relationships # => {:self=>{:has_model=>["afmodel:SimpleThing"],:has_part=>["demo:20"]},:inbound=>{:is_part_of=>["demo:6"]} 
      def relationships
        @class_relationships ||= Hash[:self => {}]
        #class_relationships
      end
    
    
      def register_subject(subject)
        if !relationships.has_key?(subject) 
            relationships[subject] = {} 
        end
      end
    
      def register_predicate(subject, predicate)
        register_subject(subject)
        if !relationships[subject].has_key?(predicate) 
          relationships[subject][predicate] = []
        end
      end

      # If predicate is a symbol, looks up the predicate in the predicate_mappings
      # If predicate is not a Symbol, returns the predicate untouched
      # @raise UnregisteredPredicateError if the predicate is a symbol but is not found in the predicate_mappings
      def predicate_lookup(predicate,namespace="info:fedora/fedora-system:def/relations-external#")
        if predicate.class == Symbol 
          if predicate_mappings[namespace].has_key?(predicate)
            return predicate_mappings[namespace][predicate]
          else
            raise ActiveFedora::UnregisteredPredicateError
          end
        end
        return predicate
      end

      def predicate_config
        @@predicate_config ||= YAML::load(File.open(ActiveFedora.predicate_config)) if File.exist?(ActiveFedora.predicate_config)
      end

      def predicate_mappings
        predicate_config[:predicate_mapping]
      end

      def default_predicate_namespace
        predicate_config[:default_namespace]
      end

      def find_predicate(predicate)
        predicate_mappings.each do |namespace,predicates|
          if predicates.fetch(predicate,nil)
            return predicates[predicate], namespace
          end
        end
        raise ActiveFedora::UnregisteredPredicateError, "Unregistered predicate: #{predicate.inspect}"
      end

      
    end
  end

  class UnregisteredPredicateError < RuntimeError; end

end
