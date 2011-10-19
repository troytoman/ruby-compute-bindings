#!/usr/bin/env ruby
# 
# == Ruby OpenStack Compute API
#
# See COPYING for license information.
# ----
# 
# === Documentation & Examples
# To begin reviewing the available methods and examples, view the README.rdoc file, or begin by looking at documentation for the OpenStack::Compute::Connection class.
#
# Example:
# OpenStack::Compute::Connection.new(:username => USERNAME, :api_key => API_KEY, :auth_url => API_URL) method.
module OpenStack
module Compute

  VERSION = IO.read(File.dirname(__FILE__) + '/../../VERSION')
  require 'net/http'
  require 'net/https'
  require 'uri'
  require 'rubygems'
  require 'json'
  require 'date'

  unless "".respond_to? :each_char
    require "jcode"
    $KCODE = 'u'
  end

  $:.unshift(File.dirname(__FILE__))
  require 'compute/authentication'
  require 'compute/connection'
  require 'compute/server'
  require 'compute/image'
  require 'compute/flavor'
  require 'compute/exception'
  require 'compute/address'
  
  # Constants that set limits on server creation
  MAX_PERSONALITY_ITEMS = 5
  MAX_PERSONALITY_FILE_SIZE = 10240
  MAX_SERVER_PATH_LENGTH = 255
  
  # Helper method to recursively symbolize hash keys.
  def self.symbolize_keys(obj)
    case obj
    when Array
      obj.inject([]){|res, val|
        res << case val
        when Hash, Array
          symbolize_keys(val)
        else
          val
        end
        res
      }
    when Hash
      obj.inject({}){|res, (key, val)|
        nkey = case key
        when String
          key.to_sym
        else
          key
        end
        nval = case val
        when Hash, Array
          symbolize_keys(val)
        else
          val
        end
        res[nkey] = nval
        res
      }
    else
      obj
    end
  end
  
  def self.paginate(options = {})
    path_args = []
    path_args.push(URI.encode("limit=#{options[:limit]}")) if options[:limit]
    path_args.push(URI.encode("offset=#{options[:offset]}")) if options[:offset]
    path_args.join("&")
  end

end
end
