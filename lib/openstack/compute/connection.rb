module OpenStack
module Compute
  class Connection
    
    attr_reader   :authuser
    attr_reader   :authtenant
    attr_reader   :authkey
    attr_accessor :authtoken
    attr_accessor :authok
    attr_accessor :svrmgmthost
    attr_accessor :svrmgmtpath
    attr_accessor :svrmgmtport
    attr_accessor :svrmgmtscheme
    attr_reader   :auth_host
    attr_reader   :auth_port
    attr_reader   :auth_scheme
    attr_reader   :auth_path
    attr_accessor :service_name
    attr_accessor :service_type
    attr_reader   :proxy_host
    attr_reader   :proxy_port
    attr_reader   :region
    
    # Creates a new OpenStack::Compute::Connection object.  Uses OpenStack::Compute::Authentication to perform the login for the connection.
    #
    # The constructor takes a hash of options, including:
    #
    #   :username - Your Openstack username *required*
    #   :tenant - Your Openstack tenant *required*. Defaults to username.
    #   :api_key - Your Openstack API key *required*
    #   :auth_url - Configurable auth_url endpoint.
    #   :service_name - (Optional for v2.0 auth only). The name of the compute service to use. Defaults to 'compute'.
    #   :region - (Optional for v2.0 auth only). The specific service region to use. Defaults to first returned region.
    #   :retry_auth - Whether to retry if your auth token expires (defaults to true)
    #   :proxy_host - If you need to connect through a proxy, supply the hostname here
    #   :proxy_port - If you need to connect through a proxy, supply the port here
    #
    #   cs = OpenStack::Compute::Connection.new(:username => 'USERNAME', :api_key => 'API_KEY', :auth_url => 'AUTH_URL')
    def initialize(options = {:retry_auth => true})
      @authuser = options[:username] || (raise Exception::MissingArgument, "Must supply a :username")
      @authkey = options[:api_key] || (raise Exception::MissingArgument, "Must supply an :api_key")
      @auth_url = options[:auth_url] || (raise Exception::MissingArgument, "Must supply an :auth_url")
      @authtenant = options[:authtenant] || @authuser
      @service_name = options[:service_name] || nil
      @service_type = options[:service_type] || "compute"
      @region = options[:region] || @region = nil
      @is_debug = options[:is_debug]

      auth_uri=nil
      begin
        auth_uri=URI.parse(@auth_url)
      rescue Exception => e
        raise Exception::InvalidArgument, "Invalid :auth_url parameter: #{e.message}"
      end
      raise Exception::InvalidArgument, "Invalid :auth_url parameter." if auth_uri.nil? or auth_uri.host.nil?
      @auth_host = auth_uri.host
      @auth_port = auth_uri.port
      @auth_scheme = auth_uri.scheme
      @auth_path = auth_uri.path
      @retry_auth = options[:retry_auth]
      @proxy_host = options[:proxy_host]
      @proxy_port = options[:proxy_port]
      @authok = false
      @http = {}
      OpenStack::Compute::Authentication.init(self)
    end
    
    # Returns true if the authentication was successful and returns false otherwise.
    #
    #   cs.authok?
    #   => true
    def authok?
      @authok
    end

    # This method actually makes the HTTP REST calls out to the server
    def csreq(method,server,path,port,scheme,headers = {},data = nil,attempts = 0) # :nodoc:
      start = Time.now
      hdrhash = headerprep(headers)
      #puts "Server: " + server.inspect + " Path: " + path.inspect + " Port: " + port.inspect  + " Header: " + hdrhash.inspect
      start_http(server,path,port,scheme,hdrhash)
      request = Net::HTTP.const_get(method.to_s.capitalize).new(path,hdrhash)
      request.body = data
      response = @http[server].request(request)
      if @is_debug
          puts "REQUEST: #{method} => #{path}"
          puts data if data
          puts "RESPONSE: #{response.body}"
          puts '----------------------------------------'
      end
      raise OpenStack::Compute::Exception::ExpiredAuthToken if response.code == "401"
      raise OpenStack::Compute::Exception::OverLimit if response.code == "413"
      response
    rescue Errno::EPIPE, Timeout::Error, Errno::EINVAL, EOFError
      # Server closed the connection, retry
      raise OpenStack::Compute::Exception::Connection, "Unable to reconnect to #{server} after #{attempts} attempts" if attempts >= 5
      attempts += 1
      @http[server].finish if @http[server].started?
      start_http(server,path,port,scheme,headers)
      retry
    rescue OpenStack::Compute::Exception::ExpiredAuthToken
      raise OpenStack::Compute::Exception::Connection, "Authentication token expired and you have requested not to retry" if @retry_auth == false
      OpenStack::Compute::Authentication.init(self)
      retry
    end

    # This is a much more sane way to make a http request to the api.
    # Example: res = conn.req('GET', "/servers/#{id}")
    def req(method, path, options = {})
      server   = options[:server]   || @svrmgmthost
      port     = options[:port]     || @svrmgmtport
      scheme   = options[:scheme]   || @svrmgmtscheme
      headers  = options[:headers]  || {'content-type' => 'application/json'}
      data     = options[:data]
      attempts = options[:attempts] || 0
      path = @svrmgmtpath + path
      res = csreq(method,server,path,port,scheme,headers,data,attempts)
      if not res.code.match(/^20.$/)
        OpenStack::Compute::Exception.raise_exception(res)
      end
      return res
    end;

    # Returns the OpenStack::Compute::Server object identified by the given id.
    #
    #   >> server = cs.get_server(110917)
    #   => #<OpenStack::Compute::Server:0x101407ae8 ...>
    #   >> server.name
    #   => "MyServer"
    def get_server(id)
      OpenStack::Compute::Server.new(self,id)
    end
    alias :server :get_server
    
    # Returns an array of hashes, one for each server that exists under this account.  The hash keys are :name and :id.
    #
    # You can also provide :limit and :offset parameters to handle pagination.
    #
    #   >> cs.list_servers
    #   => [{:name=>"MyServer", :id=>110917}]
    #
    #   >> cs.list_servers(:limit => 2, :offset => 3)
    #   => [{:name=>"demo-standingcloud-lts", :id=>168867}, 
    #       {:name=>"demo-aicache1", :id=>187853}]
    def list_servers(options = {})
      anti_cache_param="cacheid=#{Time.now.to_i}"
      path = OpenStack::Compute.paginate(options).empty? ? "#{svrmgmtpath}/servers?#{anti_cache_param}" : "#{svrmgmtpath}/servers?#{OpenStack::Compute.paginate(options)}&#{anti_cache_param}"
      response = csreq("GET",svrmgmthost,path,svrmgmtport,svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      begin
        OpenStack::Compute.symbolize_keys(JSON.parse(response.body)["servers"])
      rescue Exception
        if response.body
          puts "Error in JSON: " + response.body.inspect
          puts "RESPONSE: " + response.inspect
        else
          puts "Nothing returned in call."
        end
      end
    end
    alias :servers :list_servers
    
    # Returns an array of hashes with more details about each server that exists under this account.  Additional information
    # includes public and private IP addresses, status, hostID, and more.  All hash keys are symbols except for the metadata
    # hash, which are verbatim strings.
    #
    # You can also provide :limit and :offset parameters to handle pagination.
    #   >> cs.list_servers_detail
    #   => [{:name=>"MyServer", :addresses=>{:public=>["67.23.42.37"], :private=>["10.176.241.237"]}, :metadata=>{"MyData" => "Valid"}, :imageRef=>10, :progress=>100, :hostId=>"36143b12e9e48998c2aef79b50e144d2", :flavorRef=>1, :id=>110917, :status=>"ACTIVE"}]
    #
    #   >> cs.list_servers_detail(:limit => 2, :offset => 3)
    #   => [{:status=>"ACTIVE", :imageRef=>10, :progress=>100, :metadata=>{}, :addresses=>{:public=>["x.x.x.x"], :private=>["x.x.x.x"]}, :name=>"demo-standingcloud-lts", :id=>168867, :flavorRef=>1, :hostId=>"xxxxxx"}, 
    #       {:status=>"ACTIVE", :imageRef=>8, :progress=>100, :metadata=>{}, :addresses=>{:public=>["x.x.x.x"], :private=>["x.x.x.x"]}, :name=>"demo-aicache1", :id=>187853, :flavorRef=>3, :hostId=>"xxxxxx"}]
    def list_servers_detail(options = {})
      anti_cache_param="cacheid=#{Time.now.to_i}"
      path = OpenStack::Compute.paginate(options).empty? ? "#{svrmgmtpath}/servers/detail?#{anti_cache_param}" : "#{svrmgmtpath}/servers/detail?#{OpenStack::Compute.paginate(options)}"
      response = csreq("GET",svrmgmthost,path,svrmgmtport,svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      begin
        OpenStack::Compute.symbolize_keys(JSON.parse(response.body)["servers"])
      rescue Exception
        if response.body
          puts "Error in JSON: " + response.body.inspect
          puts "RESPONSE: " + response.inspect
        else
          puts "Nothing returned in call."
        end
      end
    end
    alias :servers_detail :list_servers_detail
    
    # Creates a new server instance on OpenStack Compute
    # 
    # The argument is a hash of options.  The keys :name, :flavorRef,
    # and :imageRef are required; :metadata and :personality are optional.
    #
    # :flavorRef and :imageRef are href strings identifying a particular
    # server flavor and image to use when building the server.  The :imageRef
    # can either be a stock image, or one of your own created with the
    # server.create_image method.
    #
    # The :metadata argument should be a hash of key/value pairs.  This
    # metadata will be applied to the server at the OpenStack Compute API level.
    #
    # The "Personality" option allows you to include up to five files, # of
    # 10Kb or less in size, that will be placed on the created server.
    # For :personality, pass a hash of the form {'local_path' => 'server_path'}.
    # The file located at local_path will be base64-encoded and placed at the
    # location identified by server_path on the new server.
    #
    # Returns a OpenStack::Compute::Server object.  The root password is
    # available in the adminPass instance method.
    #
    #   >> server = cs.create_server(
    #        :name        => 'NewServer',
    #        :imageRef    => 'http://172.19.0.3/v1.1/images/3',
    #        :flavorRef   => 'http://172.19.0.3/v1.1/flavors/1',
    #        :metadata    => {'Racker' => 'Fanatical'},
    #        :personality => {'/home/bob/wedding.jpg' => '/root/wedding.jpg'})
    #   => #<OpenStack::Compute::Server:0x101229eb0 ...>
    #   >> server.name
    #   => "NewServer"
    #   >> server.status
    #   => "BUILD"
    #   >> server.adminPass
    #   => "NewServerSHMGpvI"
    def create_server(options)
      raise OpenStack::Compute::Exception::MissingArgument, "Server name, flavorRef, and imageRef, must be supplied" unless (options[:name] && (options[:flavorId] || options[:flavorRef]) && (options[:imageId]) || options[:imageRef])
      options[:personality] = get_personality(options[:personality])
      data = JSON.generate(:server => options)
      response = csreq("POST",svrmgmthost,"#{svrmgmtpath}/servers",svrmgmtport,svrmgmtscheme,{'content-type' => 'application/json'},data)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      server_info = JSON.parse(response.body)['server']
      server = OpenStack::Compute::Server.new(self,server_info['id'])
      server.adminPass = server_info['adminPass']
      return server
    end
    
    # Returns an array of hashes listing available server images that you have access too, including stock OpenStack Compute images and 
    # any that you have created.  The "id" key in the hash can be used where imageRef is required.
    #
    # You can also provide :limit and :offset parameters to handle pagination.
    #
    #   >> cs.list_images
    #   => [{:name=>"CentOS 5.2", :id=>2, :updated=>"2009-07-20T09:16:57-05:00", :status=>"ACTIVE", :created=>"2009-07-20T09:16:57-05:00"}, 
    #       {:name=>"Gentoo 2008.0", :id=>3, :updated=>"2009-07-20T09:16:57-05:00", :status=>"ACTIVE", :created=>"2009-07-20T09:16:57-05:00"},...
    #
    #   >> cs.list_images(:limit => 3, :offset => 2) 
    #   => [{:status=>"ACTIVE", :name=>"Fedora 11 (Leonidas)", :updated=>"2009-12-08T13:50:45-06:00", :id=>13}, 
    #       {:status=>"ACTIVE", :name=>"CentOS 5.3", :updated=>"2009-08-26T14:59:52-05:00", :id=>7}, 
    #       {:status=>"ACTIVE", :name=>"CentOS 5.4", :updated=>"2009-12-16T01:02:17-06:00", :id=>187811}]
    def list_images(options = {})
      path = OpenStack::Compute.paginate(options).empty? ? "#{svrmgmtpath}/images/detail" : "#{svrmgmtpath}/images/detail?#{OpenStack::Compute.paginate(options)}"
      response = csreq("GET",svrmgmthost,path,svrmgmtport,svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      OpenStack::Compute.symbolize_keys(JSON.parse(response.body)['images'])
    end
    alias :images :list_images
    
    # Returns a OpenStack::Compute::Image object for the image identified by the provided id.
    #
    #   >> image = cs.get_image(8)
    #   => #<OpenStack::Compute::Image:0x101659698 ...>
    def get_image(id)
      OpenStack::Compute::Image.new(self,id)
    end
    alias :image :get_image
    
    # Returns an array of hashes listing all available server flavors.  The :id key in the hash can be used when flavorRef is required.
    #
    # You can also provide :limit and :offset parameters to handle pagination.
    #
    #   >> cs.list_flavors
    #   => [{:name=>"256 server", :id=>1, :ram=>256, :disk=>10}, 
    #       {:name=>"512 server", :id=>2, :ram=>512, :disk=>20},...
    #
    #   >> cs.list_flavors(:limit => 3, :offset => 2)
    #   => [{:ram=>1024, :disk=>40, :name=>"1GB server", :id=>3}, 
    #       {:ram=>2048, :disk=>80, :name=>"2GB server", :id=>4}, 
    #       {:ram=>4096, :disk=>160, :name=>"4GB server", :id=>5}]       
    def list_flavors(options = {})
      path = OpenStack::Compute.paginate(options).empty? ? "#{svrmgmtpath}/flavors/detail" : "#{svrmgmtpath}/flavors/detail?#{OpenStack::Compute.paginate(options)}"
      response = csreq("GET",svrmgmthost,path,svrmgmtport,svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      OpenStack::Compute.symbolize_keys(JSON.parse(response.body)['flavors'])
    end
    alias :flavors :list_flavors
    
    # Returns a OpenStack::Compute::Flavor object for the flavor identified by the provided ID.
    #
    #   >> flavor = cs.flavor(1)
    #   => #<OpenStack::Compute::Flavor:0x10156dcc0 @name="256 server", @disk=10, @id=1, @ram=256>
    def get_flavor(id)
      OpenStack::Compute::Flavor.new(self,id)
    end
    alias :flavor :get_flavor
    
    # Returns the current state of the programatic API limits.  Each account has certain limits on the number of resources
    # allowed in the account, and a rate of API operations.
    #
    # The operation returns a hash.  The :absolute hash key reveals the account resource limits, including the maxmimum 
    # amount of total RAM that can be allocated (combined among all servers), the maximum members of an IP group, and the 
    # maximum number of IP groups that can be created.
    #
    # The :rate hash key returns an array of hashes indicating the limits on the number of operations that can be performed in a 
    # given amount of time.  An entry in this array looks like:
    #
    #   {:regex=>"^/servers", :value=>50, :verb=>"POST", :remaining=>50, :unit=>"DAY", :resetTime=>1272399820, :URI=>"/servers*"}
    #
    # This indicates that you can only run 50 POST operations against URLs in the /servers URI space per day, we have not run
    # any operations today (50 remaining), and gives the Unix time that the limits reset.
    #
    # Another example is:
    # 
    #   {:regex=>".*", :value=>10, :verb=>"PUT", :remaining=>10, :unit=>"MINUTE", :resetTime=>1272399820, :URI=>"*"}
    #
    # This says that you can run 10 PUT operations on all possible URLs per minute, and also gives the number remaining and the
    # time that the limit resets.
    #
    # Use this information as you're building your applications to put in relevant pauses if you approach your API limitations.
    def limits
      response = csreq("GET",svrmgmthost,"#{svrmgmtpath}/limits",svrmgmtport,svrmgmtscheme)
      OpenStack::Compute::Exception.raise_exception(response) unless response.code.match(/^20.$/)
      OpenStack::Compute.symbolize_keys(JSON.parse(response.body)['limits'])
    end
    
    private
    
    # Sets up standard HTTP headers
    def headerprep(headers = {}) # :nodoc:
      default_headers = {}
      default_headers["X-Auth-Token"] = @authtoken if (authok? && @account.nil?)
      default_headers["X-Storage-Token"] = @authtoken if (authok? && !@account.nil?)
      default_headers["Connection"] = "Keep-Alive"
      default_headers["User-Agent"] = "OpenStack::Compute Ruby API #{VERSION}"
      default_headers["Accept"] = "application/json"
      default_headers.merge(headers)
    end
    
    # Starts (or restarts) the HTTP connection
    def start_http(server,path,port,scheme,headers) # :nodoc:
      if (@http[server].nil?)
        begin
          @http[server] = Net::HTTP::Proxy(self.proxy_host, self.proxy_port).new(server,port)
          if scheme == "https"
            @http[server].use_ssl = true
            @http[server].verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          @http[server].start
        rescue
          raise OpenStack::Compute::Exception::Connection, "Unable to connect to #{server}"
        end
      end
    end
    
    # Handles parsing the Personality hash to load it up with Base64-encoded data.
    def get_personality(options)
      return if options.nil?
      require 'base64'
      data = []
      itemcount = 0
      options.each do |localpath,svrpath|
        raise OpenStack::Compute::Exception::TooManyPersonalityItems, "Personality files are limited to a total of #{MAX_PERSONALITY_ITEMS} items" if itemcount >= MAX_PERSONALITY_ITEMS
        raise OpenStack::Compute::Exception::PersonalityFilePathTooLong, "Server-side path of #{svrpath} exceeds the maximum length of #{MAX_SERVER_PATH_LENGTH} characters" if svrpath.size > MAX_SERVER_PATH_LENGTH
        raise OpenStack::Compute::Exception::PersonalityFileTooLarge, "Local file #{localpath} exceeds the maximum size of #{MAX_PERSONALITY_FILE_SIZE} bytes" if File.size(localpath) > MAX_PERSONALITY_FILE_SIZE
        b64 = Base64.encode64(IO.read(localpath))
        data.push({:path => svrpath, :contents => b64})
        itemcount += 1
      end
      data
    end
        
  end
end
end
