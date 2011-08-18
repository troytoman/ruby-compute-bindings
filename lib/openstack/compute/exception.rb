module OpenStack
module Compute
  class Exception

    class ComputeError < StandardError

      attr_reader :response_body
      attr_reader :response_code

      def initialize(message, code, response_body)
        @response_code=code
        @response_body=response_body
        super(message)
      end

    end
    
    class ComputeFault           < ComputeError # :nodoc:
    end
    class ServiceUnavailable          < ComputeError # :nodoc:
    end
    class Unauthorized                < ComputeError # :nodoc:
    end
    class BadRequest                  < ComputeError # :nodoc:
    end
    class OverLimit                   < ComputeError # :nodoc:
    end
    class BadMediaType                < ComputeError # :nodoc:
    end
    class BadMethod                   < ComputeError # :nodoc:
    end
    class ItemNotFound                < ComputeError # :nodoc:
    end
    class BuildInProgress             < ComputeError # :nodoc:
    end
    class ServerCapacityUnavailable   < ComputeError # :nodoc:
    end
    class BackupOrResizeInProgress    < ComputeError # :nodoc:
    end
    class ResizeNotAllowed            < ComputeError # :nodoc:
    end
    class NotImplemented              < ComputeError # :nodoc:
    end
    class Other                       < ComputeError # :nodoc:
    end
    
    # Plus some others that we define here
    
    class ExpiredAuthToken            < StandardError # :nodoc:
    end
    class MissingArgument             < StandardError # :nodoc:
    end
    class InvalidArgument             < StandardError # :nodoc:
    end
    class TooManyPersonalityItems     < StandardError # :nodoc:
    end
    class PersonalityFilePathTooLong  < StandardError # :nodoc:
    end
    class PersonalityFileTooLarge     < StandardError # :nodoc:
    end
    class Authentication              < StandardError # :nodoc:
    end
    class Connection                  < StandardError # :nodoc:
    end
        
    # In the event of a non-200 HTTP status code, this method takes the HTTP response, parses
    # the JSON from the body to get more information about the exception, then raises the
    # proper error.  Note that all exceptions are scoped in the OpenStack::Compute::Exception namespace.
    def self.raise_exception(response)
      return if response.code =~ /^20.$/
      begin
        fault = nil
        info = nil
        JSON.parse(response.body).each_pair do |key, val|
			fault=key
			info=val
		end
        exception_class = self.const_get(fault[0,1].capitalize+fault[1,fault.length])
        raise exception_class.new(info["message"], response.code, response.body)
      rescue NameError
        raise OpenStack::Compute::Exception::Other.new("The server returned status #{response.code}", response.code, response.body)
      end
    end
    
  end
end
end
