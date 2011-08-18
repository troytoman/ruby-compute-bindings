module OpenStack
module Compute

  class AbstractMetadata

    def initialize(connection, server_id)
      @connection = connection
      @server_id  = server_id
    end

    def get_item(key)
      response = @connection.req('GET', "#{@base_url}/#{key}")
      return JSON.parse(response.body)[key]
    end

    def set_item(key, value)
      json = JSON.generate(key => value)
      @connection.req('PUT', "#{@base_url}/#{key}",:data => json)
    end

    def delete_item(key)
      @connection.req('DELETE', "#{@base_url}/#{key}")
    end

    def get_data()
      response = @connection.req('GET', @base_url)
      return JSON.parse(response.body)['metadata']
    end

    def set_data(data = {})
      json = JSON.generate(:metadata => data)
      @connection.req('POST', @base_url, :data => json)
    end

  end

  class ServerMetadata < AbstractMetadata
    def initialize(connection, server_id)
      super(connection, server_id)
      @base_url = "/servers/#{@server_id}/meta"
    end
  end

  class ImageMetadata < AbstractMetadata
    def initialize(connection, server_id)
      super(connection, server_id)
      @base_url = "/images/#{@server_id}/meta"
    end
  end

end
end
