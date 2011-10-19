module OpenStack
module Compute
  class Server
    
    require 'compute/metadata'

    attr_reader   :id
    attr_reader   :name
    attr_reader   :status
    attr_reader   :progress
    attr_reader   :accessipv4
    attr_reader   :accessipv6
    attr_reader   :addresses
    attr_reader   :hostId
    attr_reader   :image
    attr_reader   :flavor
    attr_reader   :metadata
    attr_accessor :adminPass
    
    # This class is the representation of a single Server object.  The constructor finds the server identified by the specified
    # ID number, accesses the API via the populate method to get information about that server, and returns the object.
    #
    # Will be called via the get_server or create_server methods on the OpenStack::Compute::Connection object, and will likely not be called directly.
    #
    #   >> server = cs.get_server(110917)
    #   => #<OpenStack::Compute::Server:0x1014e5438 ....>
    #   >> server.name
    #   => "RenamedRubyTest"
    def initialize(connection,id)
      @connection    = connection
      @id            = id
      @svrmgmthost   = connection.svrmgmthost
      @svrmgmtpath   = connection.svrmgmtpath
      @svrmgmtport   = connection.svrmgmtport
      @svrmgmtscheme = connection.svrmgmtscheme
      populate
      return self
    end
    
    # Makes the actual API call to get information about the given server object.  If you are attempting to track the status or project of
    # a server object (for example, when rebuilding, creating, or resizing a server), you will likely call this method within a loop until 
    # the status becomes "ACTIVE" or other conditions are met.
    #
    # Returns true if the API call succeeds.
    #
    #  >> server.refresh
    #  => true
    def populate
      response = @connection.csreq("GET",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(@id.to_s)}",@svrmgmtport,@svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      data = JSON.parse(response.body)["server"]
      @id        = data["id"]
      @name      = data["name"]
      @status    = data["status"]
      @progress  = data["progress"]
      @addresses = get_addresses(data["addresses"])
      @metadata  = OpenStack::Compute::ServerMetadata.new(@connection, @id)
      @hostId    = data["hostId"]
      @image   = data["image"]
      @flavor  = data["flavor"]
      true
    end
    alias :refresh :populate
    
    # Sends an API request to reboot this server.  Takes an optional argument for the type of reboot, which can be "SOFT" (graceful shutdown)
    # or "HARD" (power cycle).  The hard reboot is also triggered by server.reboot!, so that may be a better way to call it.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.reboot
    #   => true
    def reboot(type="SOFT")
      data = JSON.generate(:reboot => {:type => type})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    
    # Sends an API request to hard-reboot (power cycle) the server.  See the reboot method for more information.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.reboot!
    #   => true
    def reboot!
      self.reboot("HARD")
    end
    
    # Updates various parameters about the server.  Currently, the only operations supported are changing the server name (not the actual hostname
    # on the server, but simply the label in the Servers API) and the administrator password (note: changing the admin password will trigger
    # a reboot of the server).  Other options are ignored.  One or both key/value pairs may be provided.  Keys are case-sensitive.
    #
    # Input hash key values are :name and :adminPass.  Returns true if the API call succeeds.
    #
    #   >> server.update(:name => "MyServer", :adminPass => "12345")
    #   => true
    #   >> server.name
    #   => "MyServer"
    def update(options)
      data = JSON.generate(:server => options)
      response = @connection.csreq("PUT",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      # If we rename the instance, repopulate the object
      self.populate if options[:name]
      true
    end
    
    # Deletes the server from Openstack Compute.  The server will be shut down, data deleted, and billing stopped.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.delete!
    #   => true
    def delete!
      response = @connection.csreq("DELETE",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}",@svrmgmtport,@svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      true
    end
    
    # The rebuild function removes all data on the server and replaces it with
    # the specified image. The serverRef and all IP addresses will remain the
    # same. If name and metadata are specified, they will replace existing
    # values, otherwise they will not change. A rebuild operation always
    # removes data injected into the file system via server personality. You
    # may reinsert data into the filesystem during the rebuild.
    #
    # This method expects a hash of the form:
    # {
    #   :imageRef => "https://foo.com/v1.1/images/2",
    #   :name => "newName",
    #   :metadata => { :values => { :foo : "bar" } },
    #   :personality => [
    #     {
    #       :path => "/etc/banner.txt",
    #       :contents => : "ICAgpY2hhcmQgQmFjaA=="
    #     }
    #   ]
    # }
    #
    # This will wipe and rebuild the server, but keep the server ID number,
    # name, and IP addresses the same.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.rebuild!
    #   => true
    def rebuild!(options)
      json = JSON.generate(:rebuild => options)
      @connection.req('POST', "/servers/#{@id}/action", :data => json)
      self.populate
      true
    end
    
    # Takes a snapshot of the server and creates a server image from it.  That image can then be used to build new servers.  The
    # snapshot is saved asynchronously.  Check the image status to make sure that it is ACTIVE before attempting to perform operations
    # on it.
    # 
    # A name string for the saved image must be provided.  A new OpenStack::Compute::Image object for the saved image is returned.
    #
    # The image is saved as a backup, of which there are only three available slots.  If there are no backup slots available, 
    # A OpenStack::Compute::Exception::OpenStackComputeFault will be raised.
    #
    #   >> image = server.create_image("My Rails Server")
    #   => 
    def create_image(name)
      data = JSON.generate(:createImage => {:name => name})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      image_id = response["Location"].scan(/.*\/(.*)/).flatten
      OpenStack::Compute::Image.new(@connection, image_id)
    end
    
    # Resizes the server to the size contained in the server flavor found at ID flavorRef.  The server name, ID number, and IP addresses 
    # will remain the same.  After the resize is done, the server.status will be set to "VERIFY_RESIZE" until the resize is confirmed or reverted.
    #
    # Refreshes the OpenStack::Compute::Server object, and returns true if the API call succeeds.
    # 
    #   >> server.resize!(1)
    #   => true
    def resize!(flavorRef)
      data = JSON.generate(:resize => {:flavorRef => flavorRef})
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # After a server resize is complete, calling this method will confirm the resize with the Openstack API, and discard the fallback/original image.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.confirm_resize!
    #   => true
    def confirm_resize!
      # If the resize bug gets figured out, should put a check here to make sure that it's in the proper state for this.
      data = JSON.generate(:confirmResize => nil)
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # After a server resize is complete, calling this method will reject the resized server with the Openstack API, destroying
    # the new image and replacing it with the pre-resize fallback image.
    #
    # Returns true if the API call succeeds.
    #
    #   >> server.confirm_resize!
    #   => true
    def revert_resize!
      # If the resize bug gets figured out, should put a check here to make sure that it's in the proper state for this.
      data = JSON.generate(:revertResize => nil)
      response = @connection.csreq("POST",@svrmgmthost,"#{@svrmgmtpath}/servers/#{URI.encode(self.id.to_s)}/action",@svrmgmtport,@svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      self.populate
      true
    end
    
    # Changes the admin password.
    # Returns the password if it succeeds.
    def change_password!(password)
      json = JSON.generate(:changePassword => { :adminPass => password })
      @connection.req('POST', "/servers/#{@id}/action", :data => json)
      @adminPass = password
    end

    def get_addresses(address_info)
      address_list = OpenStack::Compute::AddressList.new
      address_info.each do |label, addr|
        addr.each do |address|
          address_list << OpenStack::Compute::Address.new(label,address)
          if address_list.last.version == 4 && (!@accessipv4 || accessipv4 == "") then
            @accessipv4 = address_list.last.address
          end
        end
      end
      address_list
    end

  end
end
end
