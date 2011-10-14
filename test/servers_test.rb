require File.dirname(__FILE__) + '/test_helper'

class ServersTest < Test::Unit::TestCase

  include TestConnection

  def setup
    @conn=get_test_connection
  end
  
  def test_list_servers

    json_response = %{{
      "servers" : [
        {
          "id" : 1234,
          "name" : "sample-server",
          "image" : { "id": "2" },
          "flavor" : { "id" : "1" },
          "hostId" : "e4d909c290d0fb1ca068ffaddf22cbd0",
          "status" : "BUILD",
          "progress" : 60,
          "addresses" : {
              "public" : [
                  { "version" : 4, "addr" : "67.23.10.132" },
                  { "version" : 4, "addr" : "67.23.10.131" }
              ],
              "private" : [
                  { "version" : 4, "addr" : "10.176.42.16" }
              ]
          },
          "metadata" : {
              "Server Label" : "Web Head 1",
              "Image Version" : "2.1"
          }
        },
        {
          "id" : 5678,
          "name" : "sample-server2",
          "image" : { "id": "2" },
          "flavor" : { "id" : "1" },
          "hostId" : "9e107d9d372bb6826bd81d3542a419d6",
          "status" : "ACTIVE",
          "addresses" : {
              "public" : [
                  { "version" : 4, "addr" : "67.23.10.133" }
              ],
              "private" : [
                  { "version" : 4, "addr" : "10.176.42.17" }
              ]
          },
          "metadata" : {
              "Server Label" : "DB 1"
          }
        }
      ]
    }}
    response = mock()
    response.stubs(:code => "200", :body => json_response)

    @conn.stubs(:csreq).returns(response)
    servers=@conn.list_servers

    assert_equal 2, servers.size
    assert_equal 1234, servers[0][:id]
    assert_equal "sample-server", servers[0][:name]

  end

  def test_get_server

    server=get_test_server
    assert_equal "sample-server", server.name
    assert_equal "2", server.image['id']
    assert_equal "1", server.flavor['id']
    assert_equal "e4d909c290d0fb1ca068ffaddf22cbd0", server.hostId
    assert_equal "BUILD", server.status
    assert_equal 60, server.progress
    assert_equal "67.23.10.132", server.addresses[:public][0][:addr]
    assert_equal "67.23.10.131", server.addresses[:public][1][:addr]
    assert_equal "10.176.42.16", server.addresses[:private][0][:addr]

  end

private
  def get_test_server

    json_response = %{{
      "server" : {
          "id" : 1234,
          "name" : "sample-server",
          "image" : { "id": "2" },
          "flavor" : { "id" : "1" },
          "hostId" : "e4d909c290d0fb1ca068ffaddf22cbd0",
          "status" : "BUILD",
          "progress" : 60,
          "addresses" : {
              "public" : [
                  { "version" : 4, "addr" : "67.23.10.132" },
                  { "version" : 4, "addr" : "67.23.10.131" }
              ],
              "private" : [
                  { "version" : 4, "addr" : "10.176.42.16" }
              ]
          },
          "metadata" : {
              "Server Label" : "Web Head 1",
              "Image Version" : "2.1"
          }
      }
    }}

    response = mock()
    response.stubs(:code => "200", :body => json_response)

    @conn=get_test_connection

    @conn.stubs(:csreq).returns(response)
    return @conn.server(1234) 

  end

end
