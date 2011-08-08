require 'rubygems'
require "bundler/setup"

Bundler.require(:default)

gem 'solr-ruby'
require "loggable"

$: << 'lib'
require 'active_fedora/solr_service.rb'
require "solrizer"

require 'ruby-fedora'
require 'active_fedora/base.rb'
require 'active_fedora/content_model.rb'
require 'active_fedora/datastream.rb'
require 'active_fedora/fedora_object.rb'
require 'active_fedora/metadata_datastream_helper.rb'
require 'active_fedora/metadata_datastream.rb'
require 'active_fedora/nokogiri_datastream'
require 'active_fedora/model.rb'
require 'active_fedora/property.rb'
require 'active_fedora/qualified_dublin_core_datastream.rb'
require 'active_fedora/relationship.rb'
require 'active_fedora/rels_ext_datastream.rb'
require 'active_fedora/semantic_node.rb'
require 'active_fedora/version.rb'

require 'active_fedora/railtie' if defined?(Rails) && Rails.version >= "3.0"

SOLR_DOCUMENT_ID = ActiveFedora::SolrService.id_field unless defined?(SOLR_DOCUMENT_ID)
ENABLE_SOLR_UPDATES = true unless defined?(ENABLE_SOLR_UPDATES)

module ActiveFedora #:nodoc:
  
  include Loggable
  
  class << self
    attr_accessor :solr_config, :fedora_config, :config_env, :fedora_config_path, :solr_config_path
    attr_reader :config_options
  end
  
  # The configuration hash that gets used by RSolr.connect
  @solr_config ||= {}
  @fedora_config ||= {}

  # Initializes ActiveFedora's connection to Fedora and Solr based on the info in fedora.yml and solr.yml
  # NOTE: this deprecates the use of a solr url in the fedora.yml
  #
  # 
  # If Rails.env is set, it will use that environment.  Defaults to "development".
  # @param [Hash] options (optional) a list of options for the configuration of active_fedora
  # @option options [String] :environment The environment within which to run
  # @option options [String] :fedora_config_path The full path to the fedora.yml config file.
  # @option options [String] :solr_config_path The full path to the solr.yml config file.
  # 
  # If :environment is not set, order of preference is Rails.env, ENV['environment'], RAILS_ENV
  # If :fedora_config_path is not set, it will look in {Rails.root}/config, {current working directory}/config, fedora.yml shipped with gem
  # If :solr_config_path is not set, it will look in config_options[:fedora_config_path]
  #    If it finds a solr.yml there, it will use it
  #    If it finds no solr.yml and the fedora.yml contains a solr url, it will raise an configuration error 
  #    If it finds no solr.yml and teh fedora.yml does not contain a solr url, it will look in: {Rails.root}/config, {current working directory}/config, solr.yml shipped with gem
  def self.init( options={} )
    logger.level = Logger::ERROR
    # Make config_options into a Hash if nil is passed in as the value
    options = {} if options.nil?

    # For backwards compatibility, handle cases where config_path (a String) is passed in as the argument rather than a config_options hash
    # In all other cases, set config_path to config_options[:config_path], which is ok if it's nil
    if options.is_a? String
      logger.warn "DEPRECATION WARNING: Calling ActiveFedora.init with a path as an argument is deprecated.  Use ActiveFedora.init(:config_path=>#{options})"
      @config_options = {:fedora_config_path=>options}
    else
      @config_options = options
    end

    @config_env = environment
    @fedora_config_path = get_config_path(:fedora)
    load_config(:fedora)

    @solr_config_path = get_config_path(:solr)
    load_config(:solr)

    register_fedora_and_solr

    # Retrieve the valid path for the predicate mappings config file
    @predicate_config_path = build_predicate_config_path(File.dirname(fedora_config_path))

  end

  def self.load_configs
    load_config(:fedora)
    load_config(:solr)
  end

  def self.load_config(config_type)
    config_type = config_type.to_s
    config_path = self.send("#{config_type}_config_path".to_sym)

    logger.info("#{config_type.upcase}: loading ActiveFedora.#{config_type}_config from #{File.expand_path(config_path)}")
    config = YAML::load(File.open(config_path))
    raise "The #{@config_env.to_s} environment settings were not found in the #{config_type}.yml config.  If you already have a #{config_type}.yml file defined, make sure it defines settings for the #{@config_env} environment" unless config[@config_env]
    
    config[:url] = determine_url(config_type,config)

    self.instance_variable_set("@#{config_type}_config", config)
    config
  end

  # Determines and sets the fedora_config[:url] or solr_config[:url]
  # @param [String] config_type Either 'fedora' or 'solr'
  # @param [Hash] config The config hash 
  # @return [String] the solr or fedora url
  def self.determine_url(config_type,config)  
    if config_type == "fedora"
      # support old-style config
      if config[environment].fetch("fedora",nil)
        return config[environment]["fedora"]["url"] if config[environment].fetch("fedora",nil)
      else
        return config[environment]["url"]
      end
    else
      return get_solr_url(config[environment]) if config_type == "solr"
    end
  end

  # Given the solr_config that's been loaded for this environment, 
  # determine which solr url to use
  def self.get_solr_url(solr_config)
    if @index_full_text == true && solr_config.has_key?('fulltext') && solr_config['fulltext'].has_key?('url')
      return solr_config['fulltext']['url']
    elsif solr_config.has_key?('default') && solr_config['default'].has_key?('url')
      return solr_config['default']['url']
    elsif solr_config.has_key?('url')
      return solr_config['url']
    elsif solr_config.has_key?(:url)
      return solr_config[:url]
    else
      raise URI::InvalidURIError
    end
  end

  def self.register_fedora_and_solr
    # Register Solr
    logger.info("FEDORA: initializing ActiveFedora::SolrService with solr_config: #{ActiveFedora.solr_config.inspect}")
    ActiveFedora::SolrService.register(ActiveFedora.solr_config[:url])
    logger.info("FEDORA: initialized Solr with ActiveFedora.solr_config: #{ActiveFedora::SolrService.instance.inspect}")
        
    logger.info("FEDORA: initializing Fedora with fedora_config: #{ActiveFedora.fedora_config.inspect}")
    Fedora::Repository.register(ActiveFedora.fedora_config[:url])
    logger.info("FEDORA: initialized Fedora as: #{Fedora::Repository.instance.inspect}")    
    
  end

  # Determine what environment we're running in. Order of preference is:
  # 1. config_options[:environment]
  # 2. Rails.env
  # 3. ENV['environment']
  # 4. ENV['RAILS_ENV']
  # 5. raises an exception if none of these is set
  # @return [String]
  # @example 
  #  ActiveFedora.init(:environment=>"test")
  #  ActiveFedora.environment => "test"
  def self.environment
    if config_options.fetch(:environment,nil)
      return config_options[:environment]
    elsif defined?(Rails.env) and !Rails.env.nil?
      return Rails.env.to_s
    elsif defined?(ENV['environment']) and !(ENV['environment'].nil?)
      return ENV['environment']
    elsif defined?(ENV['RAILS_ENV']) and !(ENV['RAILS_ENV'].nil?)
      logger.warn("You're depending on RAILS_ENV for setting your environment. This is deprecated in Rails3. Please use ENV['environment'] for non-rails environment setting: 'rake foo:bar environment=test'")
      ENV['environment'] = ENV['RAILS_ENV']
      return ENV['environment']
    else
      raise "Can't determine what environment to run in!"
    end
  end
  
  # Determine the fedora config file to use. Order of preference is:
  # 1. Use the config_options[:config_path] if it exists
  # 2. Look in Rails.root/config/fedora.yml
  # 3. Look in the current working directory config/fedora.yml
  # 4. Load the default config that ships with this gem
  # @return [String]
  def self.get_config_path(config_type)
    config_type = config_type.to_s
    if (config_path = config_options.fetch("#{config_type}_config_path".to_sym,nil) )
      raise ActiveFedoraConfigurationException unless File.file? config_path
      return config_path
    end
    
    # if solr, attempt to use path where fedora.yml is first
    if config_type == "solr" && (config_path = check_fedora_path_for_solr)
      return config_path
    elsif config_type == "solr" && fedora_config[environment].fetch("solr",nil)
      logger.warn("DEPRECATION WARNING: You appear to be using a deprecated format for your fedora.yml file.  The solr url should be stored in a separate solr.yml file in the same directory as the fedora.yml")
      raise ActiveFedoraConfigurationException
    end

    if defined?(Rails.root)
      config_path = "#{Rails.root}/config/#{config_type}.yml"
      return config_path if File.file? config_path
    end
    
    if File.file? "#{Dir.getwd}/config/#{config_type}.yml"  
      return "#{Dir.getwd}/config/#{config_type}.yml"
    end
    
    # Last choice, check for the default config file
    config_path = File.expand_path(File.join(File.dirname(__FILE__), "..", "config", "#{config_type}.yml"))
    logger.warn "Using the default #{config_type}.yml that comes with active-fedora.  If you want to override this, pass the path to #{config_type}.yml to ActiveFedora - ie. ActiveFedora.init(:#{config_type} => '/path/to/#{config_type}.yml) - or set Rails.root and put #{config_type}.yml into \#{Rails.root}/config."
    return config_path if File.file? config_path
    raise ActiveFedoraConfigurationException "Couldn't load #{config_type} config file!"
  end
  
  # Checks the existing fedora_config_path to see if there is a solr.yml there
  def self.check_fedora_path_for_solr
    path = fedora_config_path.split('/')[0..-2].join('/') + "/solr.yml"
    if File.file? path
      return path
    else
      return nil
    end
  end

  def self.solr
    ActiveFedora::SolrService.instance
  end
  
  def self.fedora
    Fedora::Repository.instance
  end

  def self.predicate_config
    @predicate_config_path ||= build_predicate_config_path
  end

  def self.version
    ActiveFedora::VERSION
  end

  protected

  def self.build_predicate_config_path(config_path=nil)
    pred_config_paths = [File.expand_path(File.join(File.dirname(__FILE__),"..","config"))]
    pred_config_paths.unshift config_path if config_path
    pred_config_paths.each do |path|
      testfile = File.join(path,"predicate_mappings.yml")
      if File.exist?(testfile) && valid_predicate_mapping?(testfile)
        return testfile
      end
    end
    raise PredicateMappingsNotFoundError #"Could not find predicate_mappings.yml in these locations: #{pred_config_paths.join("; ")}." unless @predicate_config_path
  end

  def self.valid_predicate_mapping?(testfile)
    mapping = YAML::load(File.open(testfile))
    return false unless mapping.has_key?(:default_namespace) && mapping[:default_namespace].is_a?(String)
    return false unless mapping.has_key?(:predicate_mapping) && mapping[:predicate_mapping].is_a?(Hash)
    true
  end
    

end





# if ![].respond_to?(:count)
#   class Array
#     puts "active_fedora is Adding count method to Array"
#       def count(&action)
#         count = 0
#          self.each { |v| count = count + 1}
#   #      self.each { |v| count = count + 1 if action.call(v) }
#         return count
#       end
#   end
# end

module ActiveFedora
  class ServerError < Fedora::ServerError; end # :nodoc:
  class ObjectNotFoundError < RuntimeError; end # :nodoc:
  class PredicateMappingsNotFoundError < RuntimeError; end # :nodoc:
end

