# #1428 (tema 6, parte 2) — a conferência e a UMA correção do turno de AJUSTE no piloto, depois que a primeira escrita
# venceu. Incluído no Builder junto com AjusteConferido e DesfechoDoAjuste; fora do piloto nada daqui roda.
#
# Só corrige item NÃO atendido (conflito sem falta vira pergunta). A correção não roda passado LIMITE_PARA_CORRIGIR_S
# desde o último toque na thread, nem quando o agente mudou por outro caminho desde a escrita (conferido de novo sob a
# trava da escrita da correção). Antes de corrigir, a thread é tocada; a correção que vence fica no state, e um re-run
# do mesmo token só confere e fecha. A 2ª conferência é pulada se o teto passou. Nenhuma falha da correção derruba o
# turno: o que entrou já está no agente.
module Autonomia::Agents::Builder::FechamentoDoAjuste
  # Erros da correção que não podem virar "falhou" depois de a primeira escrita ter vencido.
  FALHAS_DA_CORRECAO = [Crm::Ai::ResponsesClient::Error, ActiveRecord::ActiveRecordError,
                        Autonomia::Agents::Agent::ModoManual].freeze
  TIMEOUT_DA_CORRECAO_S = 90
  TENTATIVAS_DA_CORRECAO = 0
  LIMITE_PARA_CORRIGIR_S = 200

  private

  def conferir_e_fechar(token, dados)
    dados, conferencia, desfecho = conferir_e_corrigir(token, dados)
    return if desfecho == :token_perdido

    conferencia = com_descartes(conferencia, dados)
    fechar_ajuste!(token, dados, desfazer_o_que_nao_foi_pedido(token, dados, conferencia), desfecho)
  end

  # Os itens da correção que saíram por texto de pedido fora da lista (CorrecaoDoAjuste) ficam na conferência: nunca
  # somem em silêncio, e a prova não sai completa (ProvaDoAjuste). Num re-run, vêm da correção gravada.
  def com_descartes(conferencia, dados)
    descartados = [@itens_descartados.to_i, dados.to_h.dig('correcao', 'itens_descartados').to_i].max
    descartados.positive? ? conferencia.merge('itens_descartados' => descartados) : conferencia
  end

  # -> [dados, conferência final, desfecho da correção]
  def conferir_e_corrigir(token, dados)
    return conferir_a_correcao(dados) if dados['correcao']

    conferencia = conferir(dados['mudancas'], dados, dados['versao_id']).merge('correcao' => false)
    desfecho = corrigir_se_faltou(token, dados, conferencia)
    return [dados, conferencia, desfecho] unless desfecho.is_a?(Hash)

    dados = registrar_correcao!(token, dados, desfecho)
    return [nil, conferencia, :token_perdido] unless dados

    conferir_a_correcao(dados)
  end

  # A correção venceu (agora ou num turno anterior com o mesmo token): uma versão por aplicação e a 2ª conferência.
  def conferir_a_correcao(dados)
    correcao = dados['correcao']
    @thread.agent.marcar_correcao!(dados['versao_id'], correcao['versao_id'])
    todas = dados['mudancas'] + correcao['mudancas']
    return [dados, { 'itens' => todas, 'falta' => false, 'conflito' => false, 'correcao' => true }, :nao_conferido] if passou_do_teto?

    [dados, conferir(todas, dados, correcao['versao_id']).merge('correcao' => true), :aplicou]
  end

  # Só corrige item NÃO atendido, e só quando o próprio modelo não está perguntando (a pergunta dele é a do turno).
  def corrigir_se_faltou(token, dados, conferencia)
    return unless conferencia['falta'] && pergunta_do_modelo(dados['resposta']).nil?
    return :tempo if passou_do_teto?
    return :agente_mudou if agente_mudou?(dados)
    return :token_perdido unless guardar_ajuste!(token, dados)

    corrigir(token, conferencia, dados['resposta'], dados['agente_updated_at'])
  end

  def passou_do_teto?
    Time.current - @ultimo_toque > LIMITE_PARA_CORRIGIR_S
  end

  # O agente mudou por outro caminho desde a escrita do Construtor (uma volta de versão, uma edição).
  def agente_mudou?(dados)
    atual = Autonomia::Agents::Agent.where(id: @thread.autonomia_agent_id).pick(:updated_at)
    atual&.iso8601(6) != dados['agente_updated_at']
  end

  # A correção que venceu vai para o state, com o updated_at novo do agente: o re-run não a refaz nem a lê como
  # "agente mudou". O teto da 2ª conferência segue contando do toque de antes da correção.
  def registrar_correcao!(token, dados, desfecho)
    novos = dados.merge('correcao' => desfecho.transform_keys(&:to_s),
                        'agente_updated_at' => Autonomia::Agents::Agent.where(id: @thread.autonomia_agent_id)
                                                                       .pick(:updated_at).iso8601(6))
    novos if guardar_ajuste!(token, novos, marcar_toque: false)
  end

  # Conferência de UMA aplicação, anotada na versão que ela gravou. A versão guarda a fala do dono; a conferência lê
  # também a mensagem anterior do Construtor, para entender um "sim" ou "o segundo". O agente de antes vem da versão de
  # antes (o state não guarda a instrução crua).
  def conferir(mudancas, dados, versao_id)
    fala = Autonomia::Agents::ConferenciaDoAjuste.pedido(ultima_fala_do_dono)
    conferencia = Autonomia::Agents::ConferenciaDoAjuste.new(account: @account, credential: credential).conferir(
      pedido: Autonomia::Agents::ConferenciaDoAjuste.pedido_com_contexto(fala, mensagem_anterior), mudancas: mudancas,
      valores_antes: valores_antes_do_nao_pedido,
      antes: retrato_de_antes(dados), depois: regras_do_ajuste.retrato(@thread.agent)
    )
    @conferencias_ms << conferencia['duracao_ms']
    anotar_versao(versao_id, fala, mudancas, conferencia)
    conferencia
  end

  def retrato_de_antes(dados)
    versao = @thread.agent.instruction_versions.find_by(id: dados['versao_antes_id'])
    versao ? retrato_da_versao(versao) : {}
  end

  # O mesmo retrato, lido de uma versão (a de antes do ajuste): o state da thread não guarda a instrução crua.
  def retrato_da_versao(versao)
    agente = versao.metadata.to_h['agente'].to_h
    config = agente['config'].to_h
    agente.slice('name', 'tone', 'greeting', 'fallback_message', 'handoff_rule', 'human_card')
          .merge('instruction' => versao.instruction.to_s, 'starter_questions' => Array(agente['starter_questions']),
                 'guardrails' => Array(config['guardrails']), 'voice' => config['voice'])
  end

  # A anotação é rastro para a tela; falhar nela não desfaz o que já entrou no agente.
  def anotar_versao(versao_id, fala, mudancas, conferencia)
    @thread.agent.anotar_versao!(versao_id, 'pedido' => fala, 'mudancas' => mudancas, 'conferencia' => conferencia)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][builder] anotacao da versao falhou thread=#{@thread.id} #{e.class}")
  end

  # UMA tentativa: chamada completa do Construtor, com a configuração já aplicada no contexto e o que faltou como dado.
  # -> { mudancas:, versao_id:, resposta: } quando aplicou e mudou algo; senão um símbolo do desfecho.
  def corrigir(token, conferencia, resposta, esperado)
    @built_input = nil
    parsed = parse_output(call_model(full_phase, Autonomia::Agents::Config::BUILDER_REASONING_EFFORT_FINAL,
                                     aviso: Autonomia::Agents::Builder::CorrecaoDoAjuste.itens(conferencia), correcao: true))
    return :nada if parsed.nil?

    lidas = regras_do_ajuste.mudancas(parsed)
    mudancas, @itens_descartados = Autonomia::Agents::Builder::CorrecaoDoAjuste.conferir_pedidos(lidas, conferencia)
    return explicacao_da_correcao(parsed) if motivo_para_nao_aplicar(parsed, mudancas)

    aplicar_a_correcao(token, parsed, mudancas, resposta, esperado)
  rescue *FALHAS_DA_CORRECAO => e
    Rails.logger.warn("[autonomia][builder] correcao indisponivel thread=#{@thread.id} #{e.class}")
    e.is_a?(Autonomia::Agents::Agent::ModoManual) ? :manual : :nada
  end

  # A escrita da correção: o agente mudou sob a trava, perdida (por quê), sem mudança (não conta) ou aplicada.
  def aplicar_a_correcao(token, parsed, mudancas, resposta, esperado)
    antes = regras_do_ajuste.comparavel(@thread.agent)
    venceu = aplicar_lista(token, parsed, mudancas, esperado: esperado)
    return :agente_mudou if venceu == :agente_mudou
    return motivo_da_escrita_perdida(token) unless venceu
    return :nada if regras_do_ajuste.comparavel(@thread.agent) == antes

    { mudancas: mudancas, versao_id: @thread.agent.versao_do_construtor&.id, itens_descartados: @itens_descartados,
      resposta: resposta.merge(parsed.slice('needs_more_info', 'next_question', 'opcoes_de_resposta'),
                               parsed.slice('resposta_ao_dono').compact_blank) }
  end

  # A correção não aplicou: a explicação dela (texto do Construtor) entra na pergunta ao dono, com as opções dela.
  def explicacao_da_correcao(parsed)
    if parsed['needs_more_info'] == true
      @explicacao_da_correcao = parsed['next_question'].to_s.strip.presence
      @opcoes_da_correcao = opcoes_do_modelo(parsed)
    end
    :nada
  end

  def cliente_da_correcao
    @cliente_da_correcao ||= Crm::Ai::ResponsesClient.new(
      credential: credential, feature: self.class::USAGE_FEATURES.fetch(:ajuste), account: @account,
      cache_key: "agente_builder:#{@account.id}", max_retries: TENTATIVAS_DA_CORRECAO
    )
  end
end
