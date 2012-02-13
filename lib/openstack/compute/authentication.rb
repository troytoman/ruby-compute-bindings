module OpenStack
module Compute

  class Authentication

    # Performs an authentication to the OpenStack auth server.
    # If it succeeds, it sets the svrmgmthost, svrmgtpath, svrmgmtport,
    # svrmgmtscheme, authtoken, and authok variables on the connection.
    # If it fails, it raises an exception.
    def self.init(conn)
      if conn.auth_path =~ /.*v2.0\/?$/
        AuthV20.new(conn)
      else
        AuthV10.new(conn)
      end
    end

  end

  private
  class AuthV20
    
    # @param connection [Object]
    def initialize(connection)
      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host, connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        server.start
      rescue
        raise OpenStack::Compute::Exception::Connection, "Unable to connect to #{server}"
      end

      creds = "RAX-KSKEY:apiKeyCredentials"
      keyphrase = "apiKey"
      auth_data = JSON.generate({ "auth" =>  { creds => { "username" => connection.authuser, keyphrase => connection.authkey }}})
      response = server.post(connection.auth_path.chomp("/")+"/tokens", auth_data, {'Content-Type' => 'application/json'})
      if (response.code =~ /^40./)
        creds = "passwordCredentials"
        keyphrase = "password"
        auth_data = JSON.generate({ "auth" =>  { "passwordCredentials" => { "username" => connection.authuser, "password" => connection.authkey }, "tenantName" => connection.authtenant}})
        response = server.post(connection.auth_path.chomp("/")+"/tokens", auth_data, {'Content-Type' => 'application/json'})
      end

      if (response.code =~ /^20./)
        resp_data=JSON.parse(response.body)
        connection.authtoken = resp_data['access']['token']['id']
        uri = String.new
        resp_data['access']['serviceCatalog'].each do |service|
          if service['type'] == connection.service_type and service['name'] and service['name'] == connection.service_name
            endpoints = service["endpoints"]
            if connection.region
              endpoints.each do |ep|
                #puts "ENDPOINT: " + ep.inspect
                if ep["region"] and ep["region"].upcase == connection.region.upcase
                  uri = URI.parse(ep["publicURL"])
                  #puts "URI: " + uri.inspect
                end
              end
            else
              uri = URI.parse(endpoints[0]["publicURL"])
            end
          else
            connection.authok = false
          end
        end
        if uri == ''
          raise OpenStack::Compute::Exception::Authentication, "No API endpoint for region #{connection.region}"
        else
          connection.svrmgmthost = uri.host
          connection.svrmgmtpath = uri.path
          connection.svrmgmtport = uri.port
          connection.svrmgmtscheme = uri.scheme
          connection.authok = true
        end
      else
        connection.authtoken = false
        raise OpenStack::Compute::Exception::Authentication, "Authentication failed with response code #{response.code}"
      end
      server.finish
    end
  end

  class AuthV10
    
    def initialize(connection)
      hdrhash = { "X-Auth-User" => connection.authuser, "X-Auth-Key" => connection.authkey }
      # puts "AUTH1.0: " + connection.inspect
      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host, connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        server.start
      rescue
        raise OpenStack::Compute::Exception::Connection, "Unable to connect to #{server}"
      end
      response = server.get(connection.auth_path, hdrhash)
      if (response.code =~ /^20./)
        connection.authtoken = response["x-auth-token"]
        uri = URI.parse(response["x-server-management-url"])
        connection.svrmgmthost = uri.host
        connection.svrmgmtpath = uri.path
        # Force the path into the v1.1 URL space
        #connection.svrmgmtpath.sub!(/\/.*\/?/, '/v1.1/')
        #connection.svrmgmtpath += connection.authtenant
        connection.svrmgmtport = uri.port
        connection.svrmgmtscheme = uri.scheme
        connection.authok = true
      else
        connection.authtoken = false
        raise OpenStack::Compute::Exception::Authentication, "Authentication failed with response code #{response.code}"
      end
      server.finish
    end
  end

end
end
