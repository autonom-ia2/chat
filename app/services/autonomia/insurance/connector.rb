# Namespace do transporte chat2you -> máquina de adapters (repo autonomia-adapters).
# `http`: fala com o serviço real, que fala com o AGGER. `mock`: contrato sem sair da rede.
# Default é `mock` de propósito — só vira `http` no ambiente que tem INSURANCE_CONNECTOR_URL.
module Autonomia::Insurance::Connector
  MODES = %w[mock http].freeze

  def self.client
    case ENV.fetch('INSURANCE_CONNECTOR_MODE', 'mock')
    when 'http' then Http.new
    when 'mock' then Mock.new
    else
      raise ::Autonomia::Insurance::Connector::Error.new(
        :config, "INSURANCE_CONNECTOR_MODE inválido (use: #{MODES.join(', ')})"
      )
    end
  end
end
