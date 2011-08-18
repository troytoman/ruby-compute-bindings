require File.dirname(__FILE__) + '/test_helper'

class AuthenticationTest < Test::Unit::TestCase
 
  def test_good_authentication
    response = {'x-server-management-url' => 'http://server-manage.example.com/path', 'x-auth-token' => 'dummy_token'}
    response.stubs(:code).returns('204')
    server = mock(:use_ssl= => true, :verify_mode= => true, :start => true, :finish => true)
    server.stubs(:get).returns(response)
    Net::HTTP.stubs(:new).returns(server)
    connection = stub(:authuser => 'bad_user', :authkey => 'bad_key', :api_host => "a.b.c", :api_port => "443", :api_scheme => "https", :authok= => true, :authtoken= => true, :svrmgmthost= => "", :svrmgmtpath= => "", :svrmgmtpath => "", :svrmgmtport= => "", :svrmgmtscheme= => "", :proxy_host => nil, :proxy_port => nil, :api_path => '/foo')
    result = OpenStack::Compute::Authentication.new(connection)
    assert_equal result.class, OpenStack::Compute::Authentication
  end
  
  def test_bad_authentication
    response = mock()
    response.stubs(:code).returns('499')
    server = mock(:use_ssl= => true, :verify_mode= => true, :start => true)
    server.stubs(:get).returns(response)
    Net::HTTP.stubs(:new).returns(server)
    connection = stub(:authuser => 'bad_user', :authkey => 'bad_key', :api_host => "a.b.c", :api_port => "443", :api_scheme => "https", :authok= => true, :authtoken= => true, :proxy_host => nil, :proxy_port => nil, :api_path => '/foo')
    assert_raises(OpenStack::Compute::Exception::Authentication) do
      result = OpenStack::Compute::Authentication.new(connection)
    end
  end
    
  def test_bad_hostname
    Net::HTTP.stubs(:new).raises(OpenStack::Compute::Exception::Connection)
    connection = stub(:authuser => 'bad_user', :authkey => 'bad_key', :api_host => "a.b.c", :api_port => "443", :api_scheme => "https", :authok= => true, :authtoken= => true, :proxy_host => nil, :proxy_port => nil, :api_path => '/foo')
    assert_raises(OpenStack::Compute::Exception::Connection) do
      result = OpenStack::Compute::Authentication.new(connection)
    end
  end
    
end
