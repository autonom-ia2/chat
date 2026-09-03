# Namespace do transporte chat2you -> máquina de adapters (repo autonomia-adapters).
# `client` escolhe a implementação pela ENV; hoje só `mock` (contrato sem AGGER).
module Autonomia::Insurance::Connector
  def self.client
    mode = ENV.fetch('INSURANCE_CONNECTOR_MODE', 'mock')
    return Mock.new if mode == 'mock'

    raise ::Autonomia::Insurance::Connector::Error.new(:validation, "INSURANCE_CONNECTOR_MODE=#{mode} não suportado")
  end
end
