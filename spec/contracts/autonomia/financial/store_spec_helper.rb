# These protocol specs also run without booting Rails or a database.
require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'
require 'webmock/rspec'

module Autonomia; end
module Autonomia::Financial; end

require_relative '../../../../app/services/autonomia/financial/client'
require_relative '../../../../app/services/autonomia/financial/store_contract_error'
require_relative '../../../../app/services/autonomia/financial/store_contract'
require_relative '../../../../app/services/autonomia/financial/store_client_error'
require_relative '../../../../app/services/autonomia/financial/store_client'

WebMock.disable_net_connect!(allow_localhost: true)
