module ActiveFedora
  class FixtureLoader
    attr_accessor :path

    def initialize(path)
      self.path = path
    end 

    def filename_for_pid(pid)
      File.join(path, "#{pid.gsub(":","_")}.foxml.xml")
    end

    def self.delete(pid)
      begin
        ActiveFedora::Base.load_instance(pid).delete
        1
      rescue ActiveFedora::ObjectNotFoundError
        logger.debug "The object #{pid} has already been deleted (or was never created)."
        0
      rescue Errno::ECONNREFUSED => e
        logger.debug "Can't connect to Fedora! Are you sure jetty is running?"
       0
      end
    end

    def reload(pid)
      self.class.delete(pid)
      import_and_index(pid)
    end

    def import_and_index(pid)
      body = self.class.import_to_fedora(filename_for_pid(pid))
      self.class.index(pid)
      body
    end

    def self.index(pid)
        solrizer = Solrizer::Fedora::Solrizer.new 
        solrizer.solrize(pid) 
    end

    def self.import_to_fedora(filename)
      file = File.new(filename, "r")
      result = ActiveFedora::RubydoraConnection.instance.connection.ingest(:file=>file.read)
      raise "Failed to ingest the fixture." unless result
      result.body
    end
  end
end
