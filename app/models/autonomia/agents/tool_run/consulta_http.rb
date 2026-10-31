# A EXECUÇÃO DE UMA CONSULTA HTTP EM SEGUNDO PLANO (#1430, desenho D): a ferramenta cadastrada, com a flag
# `agente_ferramenta_em_segundo_plano`, numa conversa. A linha aponta para a ferramenta (`autonomia_agent_tool_id`), e
# é por esse id que o job e o varredor a resolvem: quem lê as nativas pelo slug usa `nativas`.
#
# As escritas são compare-and-set no banco, como as do motor da Lia: o turno que espera e o job que chama disputam a
# mesma linha, e o Sidekiq pode reentrar no job.
#
# Separado de `ToolRun` pelo mesmo motivo de `ListasDeEntrega`: é outro assunto, e a classe estava no teto de linhas.
module Autonomia::Agents::ToolRun::ConsultaHttp
  extend ActiveSupport::Concern

  # A FAIXA de toda consulta HTTP começa assim; o resto é o resumo do pedido (`ConsultaNoTurno#faixa`). Duas consultas
  # diferentes da mesma ferramenta correm juntas; a mesma, pedida numa mensagem nova, supersede a antiga.
  FAIXA_DA_CONSULTA = 'consulta_http'.freeze

  # Marcas do handle. A CHAVE é a Idempotency-Key calculada no turno (`ChaveDeIdempotencia.para`): o job não tem turno,
  # e a passada reenfileirada pelo varredor manda a mesma. O TEMPO é o da ferramenta na abertura: o job usa este, e não
  # o cadastro de agora.
  CHAVE_DA_CONSULTA = 'autonomia_idempotency_key'.freeze
  TEMPO_DA_CONSULTA = 'autonomia_tempo'.freeze
  # A chamada saiu (ou ia sair): gravada por compare-and-set ANTES de chamar, como o `SUBMITTED_KEY` da Lia. A
  # reentrada com ela não chama de novo; só o varredor a tira, na segunda chance com a mesma chave.
  CHAMADA_FEITA = 'autonomia_chamada_feita'.freeze
  # O texto que o modelo leria no síncrono (a resposta higienizada, ou a saída de recusa), gravado uma vez só. `OK` diz
  # se foi 2xx; `CODIGO` é o desfecho da linha quando não foi.
  RESULTADO_DA_CONSULTA = 'autonomia_resultado'.freeze
  RESULTADO_OK = 'autonomia_resultado_ok'.freeze
  CODIGO_DA_CONSULTA = 'autonomia_codigo'.freeze
  # QUEM ENTREGA O RESULTADO: o turno, se ele chegou na janela, ou o evento, se o turno desistiu. Uma marca só, por
  # compare-and-set, e a desistência só vale sem resultado gravado: na corrida, a entrega acontece uma vez.
  ENTREGA = 'autonomia_entrega'.freeze
  ENTREGUE_NO_TURNO = 'entregue_no_turno'.freeze
  DESISTIU_DO_TURNO = 'desistiu_do_turno'.freeze
  # O varredor já reenfileirou esta consulta uma vez (o worker morreu num deploy). Na segunda, ela fecha como falha.
  REENFILEIRADA = 'autonomia_reenfileirada'.freeze
  # Telemetria: quando abriu, quanto esperou na fila até o job começar, quanto a API levou, e a desistência do turno.
  ABERTA_EM = 'autonomia_aberta_em'.freeze
  FILA_MS = 'autonomia_fila_ms'.freeze
  API_MS = 'autonomia_api_ms'.freeze
  TURNO_DESISTIU = 'autonomia_turno_desistiu'.freeze

  included do
    belongs_to :ferramenta, class_name: 'Autonomia::Agents::Tool', foreign_key: :autonomia_agent_tool_id,
                            optional: true, inverse_of: false

    # As execuções das ferramentas nativas: quem lê a cotação pelo slug não pode levar uma consulta HTTP.
    scope :nativas, -> { where(autonomia_agent_tool_id: nil) }
  end

  def consulta_http?
    autonomia_agent_tool_id.present?
  end

  def resultado_da_consulta
    handle.to_h[RESULTADO_DA_CONSULTA]
  end

  def resultado_gravado?
    handle.to_h.key?(RESULTADO_DA_CONSULTA)
  end

  def resultado_ok?
    handle.to_h[RESULTADO_OK] == true
  end

  def entrega
    handle.to_h[ENTREGA]
  end

  # O começo do job: renova o prazo com o tempo gravado na abertura e anota a espera na fila. Só em linha viva.
  def reivindicar!(expires_at:, fila_ms:)
    escrever(vivas, { FILA_MS => fila_ms }, expires_at: expires_at)
  end

  # A chamada vai sair: só se a linha ainda roda, nunca chamou e não tem resultado. -> true quando ESTA passada chama.
  def marcar_chamada!
    escrever(sem_chave(sem_chave(vivas, CHAMADA_FEITA), RESULTADO_DA_CONSULTA), { CHAMADA_FEITA => true })
  end

  # Uma vez só, em qualquer status: a consulta superada também guarda o que o sistema de fora respondeu.
  def gravar_resultado!(texto, sucesso:, codigo:, api_ms:)
    marcas = { RESULTADO_DA_CONSULTA => texto.to_s, RESULTADO_OK => sucesso, CODIGO_DA_CONSULTA => codigo, API_MS => api_ms }
    escrever(sem_chave(self.class.where(id: id), RESULTADO_DA_CONSULTA), marcas.compact)
  end

  # O turno entrega: só se ninguém marcou antes. -> true quando ESTA chamada ficou com a entrega.
  def marcar_entregue!
    escrever(sem_chave(self.class.where(id: id), ENTREGA), { ENTREGA => ENTREGUE_NO_TURNO })
  end

  # O turno desiste: só se ninguém marcou E o resultado ainda não está gravado. Gravado, quem entrega é o turno.
  def marcar_desistencia!(espera_ms:)
    escopo = sem_chave(sem_chave(self.class.where(id: id), ENTREGA), RESULTADO_DA_CONSULTA)
    escrever(escopo, { ENTREGA => DESISTIU_DO_TURNO, TURNO_DESISTIU => { 'espera_ms' => espera_ms } })
  end

  # A única segunda chance do varredor: marca, renova o prazo e libera a chamada, no mesmo comando, só se a linha ainda
  # roda e nunca foi reenfileirada. -> true quando ESTA chamada ganhou a vez.
  def reenfileirar_consulta!(expires_at:)
    escrever(sem_chave(vivas, REENFILEIRADA), { REENFILEIRADA => true }, remover: CHAMADA_FEITA, expires_at: expires_at)
  end

  private

  def escrever(scope, adicionar, remover: nil, expires_at: nil)
    sets = ['handle = (handle || ?::jsonb) - ?::text', 'updated_at = ?']
    valores = [adicionar.to_json, remover.to_s, Time.current]
    if expires_at
      sets << 'expires_at = ?'
      valores << expires_at
    end
    updated = scope.update_all([sets.join(', '), *valores]) # rubocop:disable Rails/SkipsModelValidations
    return false if updated.zero?

    reload
    true
  end
end
