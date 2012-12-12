require "loggable"

module ActiveFedora::FieldMapper
  
  # Maps Term names and values to Solr fields, based on the Term's data type and any index_as options.
  #
  # The basic structure of a mapper is:
  #
  # == Mapping on Index Type
  #
  # To define a custom mapper:
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     index_as :searchable, :suffix => '_search'
  #     index_as :edible,     :suffix => '_food'
  #   end
  #
  #   #   t.dish_name   :index_as => [:searchable]            -maps to->   dish_name_search
  #   #   t.ingredients :index_as => [:searchable, :edible]   -maps to->   ingredients_search, ingredients_food
  #
  # (See Solrizer::XML::TerminologyBasedSolrizer for instructions on applying a custom mapping once you have defined it.)
  #
  # == Default Index Types
  #
  # You can mark a particular index type as a default. It will then always be included unless terms explicity
  # exclude it with the "not_" prefix:
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     index_as :searchable, :suffix => '_search', :default => true
  #     index_as :edible,     :suffix => '_food'
  #   end
  #
  #   #   t.dish_name                                                   -maps to->   dish_name_search
  #   #   t.ingredients :index_as => [:edible]                          -maps to->   ingredients_search, ingredients_food
  #   #   t.secret_ingredients :index_as => [:not_searchable, :edible]  -maps to->   secret_ingredients_food
  #
  # == Mapping on Data Type
  #
  # A mapper can apply different suffixes based on a term's data type:
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     index_as :searchable, :suffix => '_search' do |type|
  #       type.date    :suffix => '_date'
  #       type.integer :suffix => '_numeric'
  #       type.float   :suffix => '_numeric'
  #     end
  #     index_as :edible, :suffix => '_food'
  #   end
  #
  #   #   t.published   :type => :date, :index_as => [:searchable]     -maps to->   published_date
  #   #   t.votes       :type => :integer, :index_as => [:searchable]  -maps to->   votes_numeric
  #
  # If a specific data type doesn't appear in the list, the mapper falls back to the index_as:
  #
  #   #   t.description :type => :text, :index_as => [:searchable]     -maps to->   description_search
  #
  # == Custom Value Converters
  #
  # All of the above applies to the generation of Solr names. Mappers can also provide custom conversion logic for the 
  # generation of Solr values by attaching a custom value converter block to a data type:
  #
  #   require 'time'
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     index_as :searchable, :suffix => '_search' do |type|
  #       type.date do |value|
  #         Time.parse(value).utc.to_i
  #       end
  #     end
  #   end
  #
  # Note that the nesting order is always:
  #
  #   FieldMapper definition
  #     index_as
  #       data type
  #         value converter
  #
  # You can use the special data type "default" to apply custom value conversion to any data type:
  #
  #   require 'time'
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     index_as :searchable do |type|
  #       type.date :suffix => '_date' do |value|
  #         Time.parse(value).utc.to_i
  #       end
  #       type.default :suffix => '_search' do |value|
  #         value.to_s.strip
  #       end
  #     end
  #   end
  #
  # This example converts searchable dates to milliseconds, and strips extra whitespace from all other searchable data types.
  #
  # Note that the :suffix option may appear on the data types and the index_as. The search order for the suffix on a field
  # of type foo is:
  # 1. type.foo
  # 2. type.default
  # 3. index_as
  # The suffix is optional in all three places.
  #
  # Note that a single Term with multiple index types can translate into multiple Solr fields, because we may want Solr to
  # index a single field in multiple ways. However, if two different mappings generate both the same solr field name
  # _and_ the same value, the mapper will only emit a single field.
  #
  # == ID Field
  #
  # In addition to the normal field mappings, special treatment is given to an ID field. If you want that
  # logic (and you probably do), specify a name for this field:
  #
  #   class CustomMapper < ActiveFedora::FieldMapper
  #     id_field 'id' 
  #   end
  #
  # == Extending the Default
  #
  # The default mapper is ActiveFedora::FieldMapper::Default. You can customize the default mapping by subclassing it.
  # For example, to override the ID field name and the default suffix for sortable, and inherit everything else:
  #
  #   class CustomMapperBasedOnDefault < ActiveFedora::FieldMapper::Default
  #     id_field 'guid'
  #     index_as :sortable, :suffix => '_xsort'
  #   end
  
    # ------ Class methods ------
    module ClassMethods    

    attr_accessor :id_field_name, :default_index_types, :mappings
    
    def id_field(field_name)
      @id_field_name = field_name
    end

    def index_as(index_type, opts = {}, &block)
	@mappings ||= {}
        mapping = (@mappings[index_type] ||= IndexTypeMapping.new)
        mapping.opts.merge! opts
        yield DataTypeMappingBuilder.new(mapping) if block_given?
        (@default_index_types ||= []) << index_type if opts[:default]
    end
    
    # Given a specific field name, data type, and index type, returns the corresponding solr name.
    
    def solr_name(field_name, field_type, index_type = :searchable)
      name, mapping, data_type_mapping = solr_name_and_mappings(field_name, field_type, index_type)
      name
    end

    # Given a field name-value pair, a data type, and an array of index types, returns a hash of
    # mapped names and values. The values in the hash are _arrays_, and may contain multiple values.
    
    def solr_names_and_values(field_name, field_value, field_type, index_types)
      # Determine the set of index types, adding defaults and removing not_xyz
      
      index_types ||= []
      index_types += default_index_types
      index_types.uniq!
      index_types.dup.each do |index_type|
        if index_type.to_s =~ /^not_(.*)/
          index_types.delete index_type # not_foo
          index_types.delete $1.to_sym  # foo
        end
      end
      
      # Map names and values
      
      results = {}
      
      index_types.each do |index_type|
        # Get mapping for field
        name, mapping, data_type_mapping = solr_name_and_mappings(field_name, field_type, index_type)
        next unless name
        
        # Is there a custom converter?
        value = if data_type_mapping && data_type_mapping.converter
          converter = data_type_mapping.converter
          if converter.arity == 1
            converter.call(field_value)
          else
            converter.call(field_value, field_name)
          end
        else
          field_value
        end
        
        # Add mapped name & value, unless it's a duplicate
        values = (results[name] ||= [])
        values << value unless value.nil? || values.include?(value)
      end
      
      results
    end
    
  private

    def solr_name_and_mappings(field_name, field_type, index_type)
      field_name = field_name.to_s
      mapping = @mappings[index_type]
      unless mapping
        logger.debug "Unknown index type '#{index_type}' for field #{field_name}"
        return nil
      end
      
      data_type_mapping = mapping.data_types[field_type] || mapping.data_types[:default]
      
      suffix = data_type_mapping.opts[:suffix] if data_type_mapping
      suffix ||= mapping.opts[:suffix]
      name = field_name + suffix
      
      [name, mapping, data_type_mapping]
    end

   end  
  
  def self.included(klass)
    klass.extend(ClassMethods)
    klass.send(:include, Loggable)
  end
    
    class IndexTypeMapping
      attr_accessor :opts, :data_types
      
      def initialize
        @opts = {}
        @data_types = {}
      end
    end
    
    class DataTypeMapping
      attr_accessor :opts, :converter
      
      def initialize
        @opts = {}
      end
    end
    
    class DataTypeMappingBuilder
      def initialize(index_type_mapping)
        @index_type_mapping = index_type_mapping
      end
      
      def method_missing(method, *args, &block)
        data_type_mapping = (@index_type_mapping.data_types[method] ||= DataTypeMapping.new)
        data_type_mapping.opts.merge! args[0] if args.length > 0
        data_type_mapping.converter = block if block_given?
      end
    end
    
    # ------ Default mapper ------
  
  public

    class Default
      include ActiveFedora::FieldMapper

      id_field 'id'
      index_as :searchable, :default => true do |t|
        t.default :suffix => '_t'
        t.date :suffix => '_dt' do |value|
          if value.is_a?(Date) 
            DateTime.parse(value.to_s).to_time.utc.iso8601 
          elsif !value.empty?
            DateTime.parse(value).to_time.utc.iso8601
          end
        end
        t.string  :suffix => '_t'
        t.text    :suffix => '_t'
        t.symbol  :suffix => '_s'
        t.integer :suffix => '_i'
        t.long    :suffix => '_l'
        t.boolean :suffix => '_b'
        t.float   :suffix => '_f'
        t.double  :suffix => '_d'
      end
      index_as :displayable,          :suffix => '_display'
      index_as :facetable,            :suffix => '_facet'
      index_as :sortable,             :suffix => '_sort'
      index_as :unstemmed_searchable, :suffix => '_unstem_search'
    end
    
end
