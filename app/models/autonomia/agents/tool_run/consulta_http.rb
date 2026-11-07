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
  # diferentes da mesma ferramenta correm juntas; a mesma, pedida numa mensagem nova, se pendura na antiga que já chamou
  # o sistema de fora, ou a troca quando ela ainda não chamou.
  FAIXA_DA_CONSULTA = 'consulta_http'.freeze

  # Marcas do handle. A CHAVE é a Idempotency-Key calculada no turno (`ChaveDeIdempotencia.para`): o job não tem turno,
  # e a passada reenfileirada pelo varredor manda a mesma. O TEMPO é o da ferramenta na abertura: o job usa este, e não
  # o cadastro de agora.
  CHAVE_DA_CONSULTA = 'autonomia_idempotency_key'.freeze
  TEMPO_DA_CONSULTA = 'autonomia_tempo'.freeze
  # A chamada saiu (ou ia sair): gravada por compare-and-set ANTES de chamar, como o `SUBMITTED_KEY` da Lia. Ninguém a
  # tira: a linha com ela e sem resultado nunca chama de novo, e fecha como incerta (`INCERTA`). A `PASSADA` é o job
  # que a gravou: o mesmo job de volta (o Sidekiq devolve o job interrompido no desligamento) sabe que morreu no meio.
  CHAMADA_FEITA = 'autonomia_chamada_feita'.freeze
  PASSADA = 'autonomia_passada'.freeze
  # O texto que o modelo leria no síncrono (a resposta higienizada, ou a saída de recusa), gravado uma vez só. `OK` diz
  # se foi 2xx; `CODIGO` é o desfecho da linha quando não foi.
  RESULTADO_DA_CONSULTA = 'autonomia_resultado'.freeze
  RESULTADO_OK = 'autonomia_resultado_ok'.freeze
  CODIGO_DA_CONSULTA = 'autonomia_codigo'.freeze
  # Os desfechos com motivo próprio no evento (`Tools::Evento`): a chamada saiu e a resposta se perdeu (o pedido pode
  # estar registrado lá), e o operador puxou o freio depois de o turno desistir.
  INCERTA = 'consulta_incerta'.freeze
  BLOQUEADA = 'bloqueada'.freeze
  # Quem fechou sem a resposta do sistema de fora. A resposta 2xx que chega depois disso vira aviso ao atendente.
  FECHADAS_SEM_RESPOSTA = [INCERTA, 'execucao_abandonada'].freeze
  # QUEM ENTREGA O RESULTADO: o turno, se ele chegou na janela, ou o evento, se o turno desistiu. Uma marca só, por
  # compare-and-set, e a desistência só vale sem resultado gravado: na corrida, a entrega acontece uma vez.
  ENTREGA = 'autonomia_entrega'.freeze
  ENTREGUE_NO_TURNO = 'entregue_no_turno'.freeze
  DESISTIU_DO_TURNO = 'desistiu_do_turno'.freeze
  # O varredor já reenfileirou esta consulta uma vez (o job começou e morreu antes de chamar). Na segunda, ela fecha
  # como falha. O job que nunca começou não gasta esta chance.
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
    # As consultas vivas, pelo índice parcial das ativas (poucas linhas, ao contrário do histórico inteiro).
    scope :consultas_vivas, -> { where(status: 'running').where.not(autonomia_agent_tool_id: nil) }
  end

  class_methods do
    # A EQUIDADE DO CAPSULE (`HttpAssincronaJob#ceder_a_vez?`). Em voo: o job começou (`FILA_MS`) e a resposta não
    # chegou. Esperando: o job ainda não começou (na fila ou cedendo a vez).
    def consultas_em_voo(account_id)
      consultas_vivas.where(account_id: account_id).where('(handle->>?) IS NOT NULL', FILA_MS)
                     .where('(handle->>?) IS NULL', RESULTADO_DA_CONSULTA).count
    end

    def consulta_esperando_de_outra_conta?(account_id)
      consultas_vivas.where.not(account_id: account_id).exists?(['(handle->>?) IS NULL', FILA_MS])
    end
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

  def chamada_feita?
    handle.to_h[CHAMADA_FEITA].present?
  end

  # O job começou alguma vez (anotou a espera na fila).
  def comecou?
    handle.to_h.key?(FILA_MS)
  end

  # O começo do job: renova o prazo com o tempo gravado na abertura e anota a espera na fila. Só em linha viva que nunca
  # chamou: a reentrada depois da chamada não renova o prazo de ninguém.
  def reivindicar!(expires_at:, fila_ms:)
    escrever(sem_chave(vivas, CHAMADA_FEITA), { FILA_MS => fila_ms }, expires_at: expires_at)
  end

  # O job cedeu a vez a outra conta (`HttpAssincronaJob#ceder_a_vez?`): só o prazo é renovado, para o varredor não
  # tomar a espera por morte. Não anota começo.
  def adiar_comeco!(expires_at:)
    escrever(sem_chave(vivas, CHAMADA_FEITA), {}, expires_at: expires_at)
  end

  # A chamada vai sair: só se a linha ainda roda, nunca chamou e não tem resultado. -> true quando ESTA passada chama.
  def marcar_chamada!(passada:)
    escrever(sem_chave(sem_chave(vivas, CHAMADA_FEITA), RESULTADO_DA_CONSULTA), { CHAMADA_FEITA => true, PASSADA => passada })
  end

  # O mesmo pedido chegou numa mensagem nova: esta execução é trocada pela nova, só se ainda não chamou. -> true quando
  # trocou; false quando ela já chamou (ou acabou), e o turno novo se pendura nela.
  def superar_sem_chamada!
    updated = sem_chave(vivas, CHAMADA_FEITA).update_all(status: 'superseded', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    updated.positive?
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

  # AS ESCRITAS DO VARREDOR (`ReapStaleRunsJob#fechar_consulta`) conferem o prazo vencido no mesmo comando: o job que
  # começou entre a seleção e a escrita renovou o prazo e ganha.

  # A única segunda chance do job que começou e morreu antes de chamar: marca e renova o prazo, só se a linha nunca
  # chamou e nunca foi reenfileirada. -> true quando ESTA chamada ganhou a vez.
  def reenfileirar_consulta!(expires_at:, vencida_antes_de:)
    escrever(sem_chave(sem_chave(vencida(vencida_antes_de), REENFILEIRADA), CHAMADA_FEITA), { REENFILEIRADA => true },
             expires_at: expires_at)
  end

  # O job que nunca começou (perdido na fila): só renova o prazo. Não houve chamada, e a segunda chance fica.
  def reenfileirar_sem_comecar!(expires_at:, vencida_antes_de:)
    escrever(sem_chave(sem_chave(vencida(vencida_antes_de), FILA_MS), CHAMADA_FEITA), {}, expires_at: expires_at)
  end

  # O job começou duas vezes e morreu antes de chamar: fecha o resultado como abandonado, sem chamada feita.
  def abandonar_consulta!(texto, vencida_antes_de:)
    escopo = sem_chave(sem_chave(vencida(vencida_antes_de), CHAMADA_FEITA), RESULTADO_DA_CONSULTA)
    escrever(escopo.where('(handle->>?) IS NOT NULL', REENFILEIRADA),
             { RESULTADO_DA_CONSULTA => texto.to_s, RESULTADO_OK => false, CODIGO_DA_CONSULTA => 'execucao_abandonada' })
  end

  # A CHAMADA SAIU E A RESPOSTA SE PERDEU (o worker morreu no meio): não se chama de novo. O resultado é a incerteza, e a
  # linha entra em `possivelmente_duplicadas`, como a cotação. `vencida_antes_de`: só o varredor; a reentrada do mesmo
  # job decide na hora.
  def fechar_incerta!(texto, vencida_antes_de: nil)
    escopo = sem_chave(vencida_antes_de ? vencida(vencida_antes_de) : vivas, RESULTADO_DA_CONSULTA)
    escrever(escopo.where('(handle->>?) IS NOT NULL', CHAMADA_FEITA),
             { RESULTADO_DA_CONSULTA => texto.to_s, RESULTADO_OK => false, CODIGO_DA_CONSULTA => INCERTA,
               ::Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA => true })
  end

  private

  def vencida(limite)
    vivas.where(expires_at: ...limite)
  end

  def escrever(scope, adicionar, expires_at: nil)
    sets = ['handle = handle || ?::jsonb', 'updated_at = ?']
    valores = [adicionar.to_json, Time.current]
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
