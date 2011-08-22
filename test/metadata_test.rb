require File.dirname(__FILE__) + '/test_helper'

class MetadataTest < Test::Unit::TestCase

  include TestConnection

  def setup
    @conn=get_test_connection
  end
  
  def test_get_item
    test_data = { 'meta' => { 'foo' => 'bar', 'poo' => 'pah' } }
    test_json = JSON.generate(test_data)
    response = mock()
    response.stubs(:code => "200", :body => test_json)
    @conn.stubs(:req).returns(response)
    meta = OpenStack::Compute::ServerMetadata.new(@conn, 1)

    assert_equal 'bar', meta.get_item('foo')
  end

  def test_get_data
    test_data = { :metadata => { 'foo' => 'bar', 'poo' => 'pah' } }
    response = mock()
    response.stubs(:code => "200", :body => JSON.generate(test_data))
    @conn.stubs(:req).returns(response)
    meta = OpenStack::Compute::ServerMetadata.new(@conn, 1)

    assert_equal(test_data[:metadata], meta.get_data)
  end

end
