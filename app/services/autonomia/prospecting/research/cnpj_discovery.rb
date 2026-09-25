# ESBOÇO DO CONTRATO (#679): a frente A entrega a descoberta do CNPJ pela BigDataCorp. Este arquivo só existe para a
# frente C programar contra a assinatura; a integração troca pelo arquivo da frente A.
class Autonomia::Prospecting::Research::CnpjDiscovery
  # status: :found, :not_found, :ambiguous, :not_configured ou :failed. cnpj: 14 dígitos ou nil. confidence: 0..1.
  Result = Struct.new(:status, :cnpj, :confidence, :evidence, :candidates, :error_code, keyword_init: true)

  def initialize(lead:)
    @lead = lead
  end

  def perform
    raise NotImplementedError, 'frente A (#679)'
  end
end
