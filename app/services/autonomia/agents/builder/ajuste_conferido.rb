# #1428 (tema 6, parte 2) — o turno de AJUSTE no piloto (Fase 2): pergunta não é pedido, só o que foi pedido é
# gravado, e um segundo modelo confere. Incluído no Builder; fora do piloto nada daqui roda.
#
#   1. so_pergunta=true ou lista vazia (com ou sem pergunta do modelo): NÃO aplica. O turno vira resposta
#      (needs_more_info=true). Nunca "Pronto" falso: a escrita que não muda nada também não fecha como aplicada.
#   2. Aplica só os campos listados (AjustePorLista.so_os_pedidos). O resto do agente fica idêntico. Pedido claro e
#      pergunta no mesmo turno: o claro entra e a resposta (`resposta_ao_dono`) vai junto, sem virar pendência.
#   3. Confere (ConferenciaDoAjuste, só índices). Item não atendido: UMA correção e uma nova conferência; ainda
#      faltando, vira pergunta ao dono, e o que entrou fica aplicado. Conflito sem falta vira pergunta, sem correção.
#   4. O resultado vai no state da thread (`conferencia`) e na versão builder_adjust (`pedido`, `mudancas`,
#      `conferencia`). Com correção, a versão da primeira escrita sai da lista e a da correção leva `correcao_de`.
#
# A PENDÊNCIA de verdade fica em `pergunta_pendente`: a resposta a uma pergunta do dono e os avisos fixos nunca são
# pendência, e a pendência anterior sobrevive a eles.
#
# IDEMPOTÊNCIA E TEMPO: depois que a primeira escrita vence, o state guarda `ajuste_em_curso` (o token, a lista, o
# agente antes). Um re-run do mesmo token pula o Construtor e vai conferir e fechar. A conferência e a correção têm teto
# menor, e a correção não roda depois de LIMITE_PARA_CORRIGIR_S: o job é síncrono e a thread presa vira stale em 5 min.
# Depois que a primeira escrita venceu, nenhuma falha da correção derruba o turno.
module Autonomia::Agents::Builder::AjusteConferido
  private

  def ajuste_da_fase2?
    adjust_mode? && Autonomia::Agents::Fase2.ligada?(@account)
  end

  def builder_schema
    ajuste_da_fase2? ? regras_do_ajuste::SCHEMA : self.class::BUILDER_SCHEMA
  end

  def regras_do_ajuste
    Autonomia::Agents::Builder::AjustePorLista
  end

  def texto_do_ajuste(chave, **)
    Autonomia::Agents::Builder::TextosDoAjuste.texto(chave, @account, **)
  end

  # Começo do turno: zera o estado do turno, resolve a credencial uma vez e diz se é a retomada de um turno que já
  # gravou (mesmo token).
  def preparar_ajuste!(token)
    @credential = nil
    credential
    @inicio_do_ajuste = Time.current
    @conferencias_ms = []
    @campos_truncados = []
    @explicacao_da_correcao = nil
    @pendencia_anterior = pending_question
    ajuste_em_curso(token) ? :retomar : :seguir
  end

  def ajuste_em_curso(token)
    dados = @thread.state.to_h['ajuste_em_curso']
    dados if dados.is_a?(Hash) && dados['token'] == token
  end

  def retomar_ajuste!(token)
    dados = ajuste_em_curso(token)
    @inicio_do_ajuste = Time.zone.parse(dados['inicio'].to_s) || Time.current
    Rails.logger.info("[autonomia][builder] ajuste retomado thread=#{@thread.id}")
    conferir_e_fechar(token, dados)
  end

  def ajustar_pela_lista(token, parsed)
    mudancas = regras_do_ajuste.mudancas(parsed)
    motivo = motivo_para_nao_aplicar(parsed, mudancas)
    return responder_sem_aplicar(token, parsed, motivo) if motivo

    antes = regras_do_ajuste.retrato(@thread.agent)
    antes_comparavel = regras_do_ajuste.comparavel(@thread.agent)
    declare_gaps!(parsed)
    return escrita_perdida!(token, parsed) unless aplicar_lista(token, parsed, mudancas)
    return sem_mudanca!(token, parsed) if regras_do_ajuste.comparavel(@thread.agent) == antes_comparavel

    dados = registrar_aplicacao!(token, parsed, mudancas, antes)
    conferir_e_fechar(token, dados) if dados
  end

  # Por que este turno não aplica nada (nil = aplica). Quem leu a fala foi o modelo, nos campos do schema.
  def motivo_para_nao_aplicar(parsed, mudancas)
    return :pergunta if parsed['so_pergunta'] == true
    return (parsed['needs_more_info'] == true ? :esclarecimento : :sem_pedido) if mudancas.empty?

    :incompleto if regras_do_ajuste.essencial_em_branco?(parsed, mudancas)
  end

  # A pergunta do modelo é a pendência nova; a resposta a uma pergunta do dono e os textos fixos mantêm a anterior.
  def responder_sem_aplicar(token, parsed, motivo)
    texto = case motivo
            when :pergunta then parsed['next_question'].to_s.strip.presence || resposta_ao_dono(parsed)
            when :esclarecimento then parsed['next_question'].to_s.strip.presence
            end
    texto ||= texto_do_ajuste(motivo == :incompleto ? :incompleto : :sem_pedido)
    pendencia = motivo == :esclarecimento ? texto : @pendencia_anterior
    perguntar!(token, parsed, texto, 'so_pergunta' => motivo == :pergunta, 'pergunta_pendente' => pendencia)
  end

  # A escrita gravou e nada mudou (o modelo listou o que já estava assim): não fecha como aplicado.
  def sem_mudanca!(token, parsed)
    pergunta = pergunta_do_modelo(parsed)
    texto = resposta_ao_dono(parsed) || pergunta || texto_do_ajuste(:sem_mudanca)
    perguntar!(token, parsed, texto, 'so_pergunta' => false, 'pergunta_pendente' => pergunta || @pendencia_anterior)
  end

  # A primeira escrita não venceu. Token perdido: outra geração desta thread é dona do turno, nada a marcar.
  def escrita_perdida!(token, parsed)
    motivo = motivo_da_escrita_perdida(token)
    return if motivo == :token_perdido

    texto = texto_do_ajuste(motivo == :apagado ? :agente_apagado : :superado)
    perguntar!(token, parsed, texto, 'so_pergunta' => false, 'pergunta_pendente' => @pendencia_anterior)
  end

  def motivo_da_escrita_perdida(token)
    viva = Autonomia::Agents::BuildThread.exists?(id: @thread.id, build_token: token,
                                                  status: Autonomia::Agents::BuildThread.statuses[:processing])
    return :token_perdido unless viva
    return :apagado if Autonomia::Agents::Agent.where(id: @thread.autonomia_agent_id).where.not(deleted_at: nil).exists?

    :superado
  end

  def perguntar!(token, parsed, texto, extra)
    @closed = false
    estado = estado_do_ajuste(parsed.merge('needs_more_info' => true, 'next_question' => texto))
             .merge('applied' => false, 'conferencia' => nil, 'ajuste_em_curso' => nil).merge(extra)
    persist_assistant_turn!(texto) if @thread.mark_ready!(token, state: estado)
  end

  def aplicar_lista(token, parsed, mudancas)
    agent = ensure_agent(token)
    return false if agent.nil?

    attrs = regras_do_ajuste.so_os_pedidos(build_attributes(parsed), mudancas)
    @truncated_fields &= attrs.keys.map(&:to_s)
    @campos_truncados |= @truncated_fields
    log_truncation
    agent.apply_builder_config!(token, attrs)
  end

  # A primeira escrita venceu: o state guarda o que um re-run precisa para só conferir e fechar (e o updated_at da
  # thread é tocado). nil quando o token já não é o ativo.
  def registrar_aplicacao!(token, parsed, mudancas, antes)
    @closed = true
    agent = @thread.agent
    versao_id = agent.versao_do_construtor&.id
    dados = { 'token' => token, 'inicio' => @inicio_do_ajuste.iso8601(3), 'mudancas' => mudancas, 'antes' => antes,
              'resposta' => parsed.slice('needs_more_info', 'next_question', 'resposta_ao_dono'), 'versao_id' => versao_id,
              'agente_updated_at' => agent.reload.updated_at.iso8601(6), 'campos_truncados' => @campos_truncados }
    dados if @thread.guardar_no_estado!(token, 'ajuste_em_curso' => dados, 'aplicado_em_token' => token)
  end

  # O state do turno, com o rascunho lido do AGENTE (o que de fato está gravado).
  def estado_do_ajuste(parsed)
    self.class.state_for(parsed.merge(regras_do_ajuste.rascunho_do_agente(@thread.agent)))
  end

  # A última fala do dono, mesmo vazia (turno só com imagem).
  def ultima_fala_do_dono
    Array(@thread.messages).reverse.find { |m| m['role'] == 'user' }.to_h['content'].to_s
  end

  # A mensagem do Construtor logo antes da última fala do dono, ou a pergunta herdada da sessão anterior.
  def mensagem_anterior
    mensagens = Array(@thread.messages)
    indice = mensagens.rindex { |m| m['role'] == 'user' }
    anterior = indice&.positive? ? mensagens[indice - 1] : nil
    return anterior['content'].to_s if anterior && anterior['role'] == 'assistant' && anterior['content'].present?

    @thread.state.to_h['pending_question'].to_s
  end
end
