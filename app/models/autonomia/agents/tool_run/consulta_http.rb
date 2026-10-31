# A EXECUÇÃO DE UMA FERRAMENTA HTTP ASSÍNCRONA (#1430) — a ferramenta cadastrada com tempo acima de
# `Tool::LIMIAR_ASSINCRONO`. A linha aponta para ela (`autonomia_agent_tool_id`), e é por esse id que o job, o varredor e
# o evento a resolvem: o slug pode ser igual ao de uma nativa (`cotar_seguro`), e pelo catálogo a consulta cairia na Lia.
#
# Separado de `ToolRun` pelo mesmo motivo de `ListasDeEntrega`: é outro assunto, e a classe estava no teto de linhas.
module Autonomia::Agents::ToolRun::ConsultaHttp
  extend ActiveSupport::Concern

  # Marcas do handle. A CHAVE é a Idempotency-Key calculada no aceite, com o turno (`ChaveDeIdempotencia.para`): o job
  # não tem turno, e a passada reenfileirada pelo varredor manda a mesma, para o sistema de fora reconhecer o pedido.
  CHAVE_DA_CONSULTA = 'autonomia_idempotency_key'.freeze
  # O texto que o modelo leria no síncrono (a resposta com o teto de saída, ou a saída de recusa). Fica gravado também
  # na consulta supersedida, para auditoria: só não é falado.
  RESULTADO_DA_CONSULTA = 'autonomia_resultado'.freeze
  # O varredor já reenfileirou esta consulta uma vez (o worker morreu num deploy). Na segunda, ela fecha como falha.
  REENFILEIRADA = 'autonomia_reenfileirada'.freeze
  # A faixa de toda consulta HTTP: separa a linha da execução de uma nativa com o mesmo slug (o índice único, o
  # supersede e o "este turno já abriu" são por conversa, slug e faixa). Duas ferramentas não têm o mesmo slug no agente.
  FAIXA_DA_CONSULTA = 'consulta_http'.freeze

  included do
    belongs_to :ferramenta, class_name: 'Autonomia::Agents::Tool', foreign_key: :autonomia_agent_tool_id,
                            optional: true, inverse_of: false

    # As execuções das ferramentas nativas: quem lê a cotação pelo slug não pode levar uma consulta HTTP homônima.
    scope :nativas, -> { where(autonomia_agent_tool_id: nil) }
  end

  def consulta_http?
    autonomia_agent_tool_id.present?
  end

  def resultado_da_consulta
    handle.to_h[RESULTADO_DA_CONSULTA]
  end

  # Grava o resultado SEM olhar o status: a consulta supersedida no meio também guarda o que o sistema de fora respondeu.
  # Mescla no banco, como as outras escritas do handle. -> true quando gravou.
  def gravar_resultado!(texto)
    updated = self.class.where(id: id).update_all(['handle = handle || ?::jsonb, updated_at = ?', # rubocop:disable Rails/SkipsModelValidations
                                                   { RESULTADO_DA_CONSULTA => texto.to_s }.to_json, Time.current])
    return false if updated.zero?

    reload
    true
  end

  # A única segunda chance do varredor: marca e renova o prazo no mesmo comando, só se a linha ainda roda e nunca foi
  # reenfileirada. -> true quando ESTA chamada ganhou a vez.
  def reenfileirar_consulta!(expires_at:)
    updated = self.class.where(id: id, status: 'running').where('(handle->>?) IS NULL', REENFILEIRADA)
                  .update_all(['handle = handle || ?::jsonb, expires_at = ?, updated_at = ?', # rubocop:disable Rails/SkipsModelValidations
                               { REENFILEIRADA => true }.to_json, expires_at, Time.current])
    return false if updated.zero?

    reload
    true
  end
end
