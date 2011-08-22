module OpenStack
module Compute
  class Authentication
    
    # Performs an authentication to the OpenStack authorization servers.  Opens a new HTTP connection to the API server,
    # sends the credentials, and looks for a successful authentication.  If it succeeds, it sets the svrmgmthost,
    # svrmgtpath, svrmgmtport, svrmgmtscheme, authtoken, and authok variables on the connection.  If it fails, it raises
    # an exception.
    #
    # Should probably never be called directly.
    def initialize(connection)
      path = connection.api_path
      hdrhash = { "X-Auth-User" => connection.authuser, "X-Auth-Key" => connection.authkey }
      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.api_host, connection.api_port)
        if connection.api_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        server.start
      rescue
        raise OpenStack::Compute::Exception::Connection, "Unable to connect to #{server}"
      end
      response = server.get(path,hdrhash)
      if (response.code =~ /^20./)
        connection.authtoken = response["x-auth-token"]
        connection.svrmgmthost = URI.parse(response["x-server-management-url"]).host
        connection.svrmgmtpath = URI.parse(response["x-server-management-url"]).path
        # Force the path into the v1.0 URL space
        connection.svrmgmtport = URI.parse(response["x-server-management-url"]).port
        connection.svrmgmtscheme = URI.parse(response["x-server-management-url"]).scheme
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
