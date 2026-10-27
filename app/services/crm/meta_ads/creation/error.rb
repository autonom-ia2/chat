# Erro do Gerenciador simples (#2198). `code` vai para a tela; `nothing_created` diz se a Meta ficou como estava (a tela
# só diz "Nada foi criado" quando é verdade). Recusa antes de chamar a Meta: nada criado.
class Crm::MetaAds::Creation::Error < StandardError
  attr_reader :code, :nothing_created, :details

  # `details`: o que ficou mudado na Meta quando uma mudança parou no meio (para a Auditoria).
  def initialize(code, nothing_created: true, details: nil)
    @code = code
    @nothing_created = nothing_created
    @details = details
    super(code)
  end

  # Falha de uma chamada à Meta: passageira (rede, 5xx, limite) ou recusa.
  def self.from_result(result, nothing_created: true)
    new(result.transient? ? 'meta_unavailable' : 'meta_refused', nothing_created: nothing_created)
  end
end
