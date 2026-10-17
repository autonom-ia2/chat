# #1428 (tema 6, parte 2) — o fim do turno de AJUSTE no piloto, depois que a primeira escrita venceu: a conferência,
# a UMA correção e o fechamento (o que vai ao dono, a pendência, as versões e o log). Incluído no Builder junto com
# AjusteConferido; fora do piloto nada daqui roda.
#
# Só corrige item NÃO atendido (conflito sem falta vira pergunta). A correção não roda passado LIMITE_PARA_CORRIGIR_S
# nem quando o agente mudou por outro caminho desde a primeira escrita. Depois que a primeira escrita venceu, nenhuma
# falha da correção derruba o turno. O texto ao dono é montado aqui, com o pedido e o resumo que o Construtor escreveu.
module Autonomia::Agents::Builder::FechamentoDoAjuste
  # Erros da correção que não podem virar "falhou" depois de a primeira escrita ter vencido.
  FALHAS_DA_CORRECAO = [Crm::Ai::ResponsesClient::Error, ActiveRecord::ActiveRecordError,
                        Autonomia::Agents::Agent::ModoManual].freeze
  TIMEOUT_DA_CORRECAO_S = 90
  TENTATIVAS_DA_CORRECAO = 1
  LIMITE_PARA_CORRIGIR_S = 200
  # Desfechos da correção que só avisam o dono (nada a perguntar).
  AVISOS_DO_DESFECHO = { superado: :correcao_superada, apagado: :agente_apagado, agente_mudou: :agente_mudou }.freeze

  private

  def conferir_e_fechar(token, dados)
    conferencia = conferir(dados['mudancas'], dados, dados['versao_id']).merge('correcao' => false)
    desfecho = corrigir_se_faltou(token, dados, conferencia)
    if desfecho.is_a?(Hash)
      dados = dados.merge('mudancas' => dados['mudancas'] + desfecho[:mudancas], 'resposta' => desfecho[:resposta])
      conferencia = conferir(dados['mudancas'], dados, desfecho[:versao_id]).merge('correcao' => true)
      @thread.agent.marcar_correcao!(dados['versao_id'], desfecho[:versao_id])
    end
    fechar_ajuste!(token, dados, conferencia, desfecho)
  end

  # Só corrige item NÃO atendido, e só quando o próprio modelo não está perguntando (a pergunta dele é a do turno).
  def corrigir_se_faltou(token, dados, conferencia)
    return unless conferencia['falta'] && pergunta_do_modelo(dados['resposta']).nil?
    return :tempo if Time.current - @inicio_do_ajuste > LIMITE_PARA_CORRIGIR_S
    return :agente_mudou if agente_mudou?(dados)

    corrigir(token, conferencia, dados['resposta'])
  end

  # O agente mudou por outro caminho desde a primeira escrita (uma volta de versão, uma edição): não corrige por cima.
  def agente_mudou?(dados)
    atual = Autonomia::Agents::Agent.where(id: @thread.autonomia_agent_id).pick(:updated_at)
    atual&.iso8601(6) != dados['agente_updated_at']
  end

  # Conferência de UMA aplicação, anotada na versão que ela gravou. A versão guarda a fala do dono; a conferência lê
  # também a mensagem anterior do Construtor, para entender um "sim" ou "o segundo".
  def conferir(mudancas, dados, versao_id)
    fala = regras_do_ajuste.pedido(ultima_fala_do_dono)
    conferencia = Autonomia::Agents::ConferenciaDoAjuste.new(account: @account, credential: credential).conferir(
      pedido: regras_do_ajuste.pedido_com_contexto(fala, mensagem_anterior), mudancas: mudancas,
      antes: dados['antes'], depois: regras_do_ajuste.retrato(@thread.agent)
    )
    @conferencias_ms << conferencia['duracao_ms']
    anotar_versao(versao_id, fala, mudancas, conferencia)
    conferencia
  end

  # A anotação é rastro para a tela; falhar nela não desfaz o que já entrou no agente.
  def anotar_versao(versao_id, fala, mudancas, conferencia)
    @thread.agent.anotar_versao!(versao_id, 'pedido' => fala, 'mudancas' => mudancas, 'conferencia' => conferencia)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][builder] anotacao da versao falhou thread=#{@thread.id} #{e.class}")
  end

  # UMA tentativa: chamada completa do Construtor, com a configuração já aplicada no contexto e o que faltou como dado.
  # -> { mudancas:, versao_id:, resposta: } quando aplicou e mudou algo; senão um símbolo do desfecho.
  def corrigir(token, conferencia, resposta)
    @built_input = nil
    parsed = parse_output(call_model(full_phase, Autonomia::Agents::Config::BUILDER_REASONING_EFFORT_FINAL,
                                     aviso: regras_do_ajuste.itens_de_correcao(conferencia), correcao: true))
    return :nada if parsed.nil?

    mudancas = regras_do_ajuste.mudancas(parsed)
    return explicacao_da_correcao(parsed) if motivo_para_nao_aplicar(parsed, mudancas)

    aplicar_a_correcao(token, parsed, mudancas, resposta)
  rescue *FALHAS_DA_CORRECAO => e
    Rails.logger.warn("[autonomia][builder] correcao indisponivel thread=#{@thread.id} #{e.class}")
    e.is_a?(Autonomia::Agents::Agent::ModoManual) ? :manual : :nada
  end

  # A escrita da correção: perdida (por quê), sem mudança (não conta) ou aplicada.
  def aplicar_a_correcao(token, parsed, mudancas, resposta)
    antes = regras_do_ajuste.comparavel(@thread.agent)
    return motivo_da_escrita_perdida(token) unless aplicar_lista(token, parsed, mudancas)
    return :nada if regras_do_ajuste.comparavel(@thread.agent) == antes

    { mudancas: mudancas, versao_id: @thread.agent.versao_do_construtor&.id,
      resposta: resposta.merge(parsed.slice('needs_more_info', 'next_question')) }
  end

  # A correção não aplicou: a explicação dela (texto do Construtor) entra na pergunta ao dono.
  def explicacao_da_correcao(parsed)
    @explicacao_da_correcao = parsed['next_question'].to_s.strip.presence if parsed['needs_more_info'] == true
    :nada
  end

  def cliente_da_correcao
    @cliente_da_correcao ||= Crm::Ai::ResponsesClient.new(
      credential: credential, feature: self.class::USAGE_FEATURES.fetch(:ajuste), account: @account,
      cache_key: "agente_builder:#{@account.id}", max_retries: TENTATIVAS_DA_CORRECAO
    )
  end

  # Fecha como aplicado. Ao dono vão, nesta ordem: a resposta à pergunta dele, o aviso do desfecho e a pendência.
  def fechar_ajuste!(token, dados, conferencia, desfecho)
    return if desfecho == :token_perdido

    resposta = dados['resposta'].to_h
    pendencia = pergunta_do_modelo(resposta) || pendencia_da_conferencia(conferencia, desfecho, dados['mudancas'])
    aviso = AVISOS_DO_DESFECHO[desfecho] && texto_do_ajuste(AVISOS_DO_DESFECHO[desfecho])
    mensagens = [resposta_ao_dono(resposta), aviso, pendencia].compact_blank
    estado = estado_do_ajuste(resposta.merge('needs_more_info' => pendencia.present?, 'next_question' => mensagens.last.to_s))
             .merge('applied' => true, 'truncated_fields' => Array(dados['campos_truncados']) | @campos_truncados,
                    'so_pergunta' => false, 'conferencia' => conferencia, 'pergunta_pendente' => pendencia.to_s,
                    'ajuste_em_curso' => nil)
    mensagens.each { |mensagem| persist_assistant_turn!(mensagem) } if @thread.mark_ready!(token, state: estado)
    log_do_ajuste(conferencia, desfecho)
  end

  def pendencia_da_conferencia(conferencia, desfecho, mudancas)
    return if %i[manual superado apagado agente_mudou].include?(desfecho)

    textos = Autonomia::Agents::Builder::TextosDoAjuste
    return textos.pergunta_do_que_faltou(conferencia, @account, explicacao: @explicacao_da_correcao) if conferencia['falta']

    textos.pergunta_do_conflito(mudancas, @account) if conferencia['conflito']
  end

  # A pergunta que o próprio Construtor fez sobre o que ficou vago.
  def pergunta_do_modelo(resposta)
    return unless resposta.to_h['needs_more_info'] == true

    resposta['next_question'].to_s.strip.presence
  end

  # A resposta à pergunta do dono que veio junto com o pedido: o campo próprio ou, sem pergunta pendente do modelo, o
  # next_question que ele usou para isso.
  def resposta_ao_dono(resposta)
    resposta = resposta.to_h
    resposta['resposta_ao_dono'].to_s.strip.presence ||
      (resposta['next_question'].to_s.strip.presence unless resposta['needs_more_info'] == true)
  end

  # Só metadados: quantas chamadas e conferências, quanto duraram e o desfecho da correção. Nunca conteúdo.
  def log_do_ajuste(conferencia, desfecho)
    Rails.logger.info(
      "[autonomia][builder] ajuste thread=#{@thread.id} calls=#{@calls.size} conferencias=#{@conferencias_ms.size} " \
      "conferencias_ms=#{@conferencias_ms.join(',')} correcao=#{conferencia['correcao'] == true} " \
      "desfecho=#{desfecho.is_a?(Hash) ? 'aplicou' : desfecho || '-'} conferencia=#{conferencia['erro'] || 'ok'} " \
      "falta=#{conferencia['falta'] == true} conflito=#{conferencia['conflito'] == true}"
    )
  end
end
