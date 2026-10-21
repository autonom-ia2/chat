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
# pendência, e a pendência anterior sobrevive a eles (PendenciaDoAjuste, com o teto).
#
# IDEMPOTÊNCIA E TEMPO: depois que a primeira escrita vence, o state guarda `ajuste_em_curso` (o token, a lista, o id
# da versão de antes, nunca a instrução crua). Um re-run do mesmo token pula o Construtor e vai conferir e fechar. A
# conferência e a correção têm teto menor, sem nova tentativa, e a correção não roda depois de LIMITE_PARA_CORRIGIR_S
# desde o último toque na thread: o job é síncrono e a thread presa vira stale em 5 min.
# Depois que a primeira escrita venceu, nenhuma falha da correção derruba o turno.
module Autonomia::Agents::Builder::AjusteConferido
  private

  # Decidido uma vez por turno (run! zera): o turno não muda de caminho no meio.
  def ajuste_da_fase2?
    return @ajuste_da_fase2 unless @ajuste_da_fase2.nil?

    @ajuste_da_fase2 = adjust_mode? && Autonomia::Agents::Fase2.ligada?(@account)
  end

  def builder_schema
    ajuste_da_fase2? ? regras_do_ajuste::SCHEMA : self.class::BUILDER_SCHEMA
  end

  def regras_do_ajuste
    Autonomia::Agents::Builder::AjustePorLista
  end

  # #1428 (entrega C) — as respostas prontas que o modelo escreveu para a pergunta dele (OpcoesDeResposta).
  def opcoes_do_modelo(parsed)
    Autonomia::Agents::Builder::OpcoesDeResposta.filtrar(parsed)
  end

  def texto_do_ajuste(chave, **)
    Autonomia::Agents::Builder::TextosDoAjuste.texto(chave, idioma_do_ajuste, **)
  end

  # O idioma de quem conversa (a pessoa que abriu a conversa) e, sem ele, o da conta.
  def idioma_do_ajuste
    @idioma_do_ajuste ||= Autonomia::Agents::Builder::TextosDoAjuste.idioma(@thread.created_by, @account)
  end

  # Começo do turno: zera o estado do turno, resolve a credencial uma vez e diz se é a retomada de um turno que já
  # gravou (mesmo token).
  def preparar_ajuste!(token)
    @credential = nil
    credential
    @ultimo_toque = Time.current
    @conferencias_ms = []
    @campos_truncados = []
    @explicacao_da_correcao = nil
    @opcoes_da_correcao = []
    @itens_descartados = 0
    @pendencia_anterior = pending_question
    @turnos_da_pendencia = @thread.state.to_h['pendencia_turnos'].to_i
    # O "tira isso" só vai enquanto o Desfazer do último ajuste ainda vale, decidido no começo do turno, antes da escrita
    # dele (a retomada do mesmo token já passou por aqui antes de escrever).
    @nao_pedido_vale = ajuste_em_curso(token).present? || @thread.agent&.conversa_desfazivel&.id == @thread.id
    ajuste_em_curso(token) ? :retomar : :seguir
  end

  def ajuste_em_curso(token)
    dados = @thread.state.to_h['ajuste_em_curso']
    dados if dados.is_a?(Hash) && dados['token'] == token
  end

  def retomar_ajuste!(token)
    dados = ajuste_em_curso(token)
    @ultimo_toque = @thread.updated_at
    Rails.logger.info("[autonomia][builder] ajuste retomado thread=#{@thread.id}")
    conferir_e_fechar(token, dados)
  end

  def ajustar_pela_lista(token, parsed)
    mudancas = regras_do_ajuste.mudancas(parsed)
    motivo = motivo_para_nao_aplicar(parsed, mudancas)
    return responder_sem_aplicar(token, parsed, motivo) if motivo

    antes_comparavel = regras_do_ajuste.comparavel(@thread.agent)
    declare_gaps!(parsed)
    return escrita_perdida!(token, parsed) unless aplicar_lista(token, parsed, mudancas)
    return sem_mudanca!(token, parsed) if regras_do_ajuste.comparavel(@thread.agent) == antes_comparavel

    dados = registrar_aplicacao!(token, parsed, mudancas)
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
            when :pergunta then parsed['next_question'].to_s.strip.presence || texto_do_ajuste(:sem_resposta)
            when :esclarecimento then parsed['next_question'].to_s.strip.presence
            end
    texto ||= texto_do_ajuste(motivo == :incompleto ? :incompleto : :sem_pedido)
    pendencia = if motivo == :esclarecimento
                  pendencia_no_estado(texto, parsed, origem: :modelo, laco: true)
                else
                  pendencia_no_estado(pendencia_mantida(parsed), parsed, origem: :mantida, laco: false)
                end
    perguntar!(token, parsed, [texto], { 'so_pergunta' => motivo == :pergunta }.merge(pendencia, opcoes_da_pergunta(parsed, motivo)))
  end

  # Só a pergunta do próprio modelo leva as opções dele (o esclarecimento sem texto cai no texto fixo, sem opções);
  # perguntar! zera as de qualquer outro fim de turno.
  def opcoes_da_pergunta(parsed, motivo)
    return {} unless motivo == :esclarecimento && pergunta_do_modelo(parsed)

    { 'opcoes_de_resposta' => opcoes_do_modelo(parsed) }
  end

  # A escrita gravou e nada mudou (o modelo listou o que já estava assim): não fecha como aplicado. Ao dono, só o texto
  # fixo e, se o modelo pediu esclarecimento, a pergunta dele: nunca um texto do modelo que afirme ter aplicado.
  def sem_mudanca!(token, parsed, extra = {}, texto: nil)
    pergunta = pergunta_do_modelo(parsed)
    pendencia = if pergunta
                  pendencia_no_estado(pergunta, parsed, origem: :modelo, laco: true).merge('opcoes_de_resposta' => opcoes_do_modelo(parsed))
                else
                  pendencia_no_estado(pendencia_mantida(parsed), parsed, origem: :mantida, laco: false)
                end
    perguntar!(token, parsed, [texto || texto_do_ajuste(:sem_mudanca), pergunta].compact,
               { 'so_pergunta' => false }.merge(pendencia, extra))
  end

  # A primeira escrita não venceu. Token perdido: outra geração desta thread é dona do turno, nada a marcar.
  def escrita_perdida!(token, parsed)
    motivo = motivo_da_escrita_perdida(token)
    return if motivo == :token_perdido

    texto = texto_do_ajuste(motivo == :apagado ? :agente_apagado : :superado)
    perguntar!(token, parsed, [texto], { 'so_pergunta' => false }
                                      .merge(pendencia_no_estado(@pendencia_anterior, {}, origem: :mantida, laco: false)))
  end

  def motivo_da_escrita_perdida(token)
    viva = Autonomia::Agents::BuildThread.exists?(id: @thread.id, build_token: token,
                                                  status: Autonomia::Agents::BuildThread.statuses[:processing])
    return :token_perdido unless viva
    return :apagado if Autonomia::Agents::Agent.where(id: @thread.autonomia_agent_id).where.not(deleted_at: nil).exists?

    :superado
  end

  # O turno termina sem nada aplicado: needs_more_info, as mensagens ao dono (a última é o next_question) e a pendência
  # (que vem pronta em `extra`).
  def perguntar!(token, parsed, mensagens, extra)
    @closed = false
    # O Desfazer (`ultimo_ajuste`) e o "tira isso" (`nao_pedido_anterior`) sobrevivem ao turno sem mudança: duram até o
    # próximo ajuste aplicado ou o Desfazer (#1428, parte 3).
    estado = estado_do_ajuste(parsed.merge('needs_more_info' => true, 'next_question' => mensagens.last.to_s))
             .merge('applied' => false, 'conferencia' => nil, 'ajuste_em_curso' => nil, 'parcial' => false,
                    'opcoes_de_resposta' => [], 'pergunta_na_tela' => nil)
             .merge(extra)
    mensagens.each { |mensagem| persist_assistant_turn!(mensagem) } if @thread.mark_ready!(token, state: estado)
  end

  # `esperado` (só na correção): o updated_at do agente conferido sob a trava da escrita.
  def aplicar_lista(token, parsed, mudancas, esperado: nil)
    agent = ensure_agent(token)
    return false if agent.nil?

    attrs = regras_do_ajuste.so_os_pedidos(build_attributes(parsed), mudancas)
    @truncated_fields &= attrs.keys.map(&:to_s)
    @campos_truncados |= @truncated_fields
    log_truncation
    agent.apply_builder_config!(token, attrs, esperado: esperado)
  end

  # A primeira escrita venceu: o state guarda o que um re-run precisa para só conferir e fechar (e o updated_at da
  # thread é tocado). nil quando o token já não é o ativo.
  def registrar_aplicacao!(token, parsed, mudancas)
    @closed = true
    agent = @thread.agent
    dados = { 'token' => token, 'mudancas' => mudancas, 'versao_id' => agent.versao_do_construtor&.id,
              'versao_antes_id' => agent.versao_antes_do_construtor&.id,
              'resposta' => parsed.slice('needs_more_info', 'next_question', 'resposta_ao_dono', 'pendencia_resolvida',
                                         'opcoes_de_resposta'),
              'agente_updated_at' => agent.reload.updated_at.iso8601(6), 'campos_truncados' => @campos_truncados,
              'perguntas_de_prova' => Autonomia::Agents::ProvaDoAjuste.perguntas(parsed) }
    dados if guardar_ajuste!(token, dados, { 'aplicado_em_token' => token })
  end

  # Grava o ajuste em curso no state (guardado pelo token) e marca o toque: o teto de tempo conta a partir dele.
  def guardar_ajuste!(token, dados, extra = {}, marcar_toque: true)
    return false unless @thread.guardar_no_estado!(token, { 'ajuste_em_curso' => dados }.merge(extra))

    @ultimo_toque = Time.current if marcar_toque
    true
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
