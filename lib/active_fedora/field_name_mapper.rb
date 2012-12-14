# Re-Introduced for backwards compatibility
module ActiveFedora::FieldNameMapper
    
  # Class Methods -- These methods will be available on classes that include this Module 
 
  module ClassMethods
    attr_accessor :field_mapper

    def id_field
      return self.field_mapper.id_field_name
    end

    # Re-loads solr mappings for the default field mapper's class 
    # and re-sets the default field mapper to an FieldMapper instance with those mappings.
    def load_mappings( config_path=nil)
      self.field_mapper = load_mappings_from_file(config_path)
    end
    
    def solr_name(field_name, field_type, index_type = :searchable)
      self.field_mapper.solr_name(field_name, field_type, index_type)
    end

    def solr_names_and_values(field_name, field_value, field_type, index_type = :searchable)
      self.field_mapper.solr_names_and_values(field_name, field_value, field_type, index_type)
    end
    
    def field_mapper
      @field_mapper ||= ActiveFedora::FieldMapper::Default
    end

    private

    # Loads solr mappings from yml file.
    # Assumes that string values are solr field name suffixes.
    # This is meant as a simple entry point for working with solr mappings.  For more powerful control over solr mappings, create your own subclasses of FieldMapper instead of using a yml file.
    # @param [String] config_path This is the path to the directory where your mappings file is stored. Defaults to "Rails.root/config/solr_mappings.yml"
    def load_mappings_from_file( config_path=nil )

      if config_path.nil?
        if defined?(Rails.root) && !Rails.root.nil?
          config_path = File.join(Rails.root, "config", "solr_mappings.yml")
        end
        # Default to using the config file within the gem
        if !File.exist?(config_path.to_s)
          config_path = File.join(File.dirname(__FILE__), "..", "..", "config", "solr_mappings.yml")
        end
      end

      logger.debug("Loading field name mappings from #{File.expand_path(config_path)}")
      mappings_from_file = YAML::load(File.open(config_path))

      klass = Class.new do
        include ActiveFedora::FieldMapper
      end

      # Set id_field from file if it is available
      id_field_from_file = mappings_from_file.delete("id")
      if id_field_from_file.nil?
        klass.id_field "id"
      else
	klass.id_field id_field_from_file
      end

      default_index_type = mappings_from_file.delete("default")
      mappings_from_file.each_pair do |index_type, type_settings|
        if type_settings.kind_of?(Hash)
          klass.index_as index_type.to_sym, :default => index_type == default_index_type do |t|
            type_settings.each_pair do |field_type, suffix|
              eval("t.#{field_type} :suffix=>\"#{suffix}\"")
            end
          end
        else
          klass.index_as index_type.to_sym, :default => index_type == default_index_type, :suffix=>type_settings
        end
      end
      klass
    end

  end
  
  # Instance Methods -- These methods will be available on instances of classes that include this module
  
  attr_accessor :ox_namespaces
  
  def self.included(klass)
    klass.extend(ClassMethods)
  end
  
end
