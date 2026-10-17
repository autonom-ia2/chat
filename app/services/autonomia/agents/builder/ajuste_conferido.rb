# #1428 (tema 6, parte 2) — o turno de AJUSTE no piloto (Fase 2): pergunta não é pedido, só o que foi pedido é
# gravado, e um segundo modelo confere. Incluído no Builder; fora do piloto nada daqui roda.
#
#   1. so_pergunta=true, lista vazia ou pergunta do próprio modelo: NÃO aplica. O turno vira resposta
#      (needs_more_info=true, next_question = a resposta ou o esclarecimento). Nunca "Pronto" falso.
#   2. Aplica só os campos listados (AjustePorLista.so_os_pedidos). O resto do agente fica idêntico.
#   3. Confere (ConferenciaDoAjuste). Faltou algo: UMA correção (chamada completa do Construtor com o aviso do que
#      faltou) e uma nova conferência. Ainda faltando: vira pergunta ao dono; o que entrou fica aplicado.
#   4. O resultado vai no state da thread (`conferencia`) e na versão builder_adjust gravada (`pedido`, `mudancas`,
#      `conferencia`), para a tela da parte 3.
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

  def ajustar_pela_lista(token, parsed)
    @campos_truncados = []
    mudancas = regras_do_ajuste.mudancas(parsed)
    motivo = motivo_para_nao_aplicar(parsed, mudancas)
    return responder_sem_aplicar(token, parsed, motivo) if motivo

    @closed = true
    antes = regras_do_ajuste.retrato(@thread.agent)
    declare_gaps!(parsed)
    return marcar_sem_aplicar(token, parsed) unless aplicar_lista(token, parsed, mudancas)

    @parsed_final = parsed
    fechar_ajuste!(token, conferir_e_corrigir(token, antes, mudancas))
  end

  # Por que este turno não aplica nada (nil = aplica). Quem leu a fala foi o modelo, nos campos do schema.
  def motivo_para_nao_aplicar(parsed, mudancas)
    return :pergunta if parsed['so_pergunta'] == true
    return :esclarecimento if parsed['needs_more_info'] == true
    return :sem_pedido if mudancas.empty?

    :incompleto if regras_do_ajuste.essencial_em_branco?(parsed, mudancas)
  end

  def responder_sem_aplicar(token, parsed, motivo)
    @closed = false
    texto = parsed['next_question'].to_s.strip.presence if %i[pergunta esclarecimento].include?(motivo)
    texto ||= motivo == :incompleto ? regras_do_ajuste::INCOMPLETO : regras_do_ajuste::SEM_PEDIDO
    estado = estado_do_ajuste(parsed.merge('needs_more_info' => true, 'next_question' => texto))
             .merge('so_pergunta' => motivo == :pergunta, 'conferencia' => nil)
    persist_assistant_turn!(texto) if @thread.mark_ready!(token, state: estado)
  end

  # A escrita não venceu (um ajuste mais novo do agente): tira a thread de `processing` sem dizer que aplicou.
  def marcar_sem_aplicar(token, parsed)
    @thread.mark_ready!(token, state: estado_do_ajuste(parsed).merge('so_pergunta' => false, 'conferencia' => nil))
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

  def conferir_e_corrigir(token, antes, mudancas)
    conferencia = conferir(antes, mudancas)
    return conferencia.merge('correcao' => false) if conferencia['pendencias'].blank? || conferencia['erro']

    correcao = corrigir(token, conferencia)
    return conferencia.merge('correcao' => false) if correcao.nil?

    conferir(antes, mudancas + correcao).merge('correcao' => true)
  end

  # Conferência de UMA aplicação, anotada na versão que ela gravou.
  def conferir(antes, mudancas)
    pedido = regras_do_ajuste.pedido(ultima_fala_do_dono)
    conferencia = Autonomia::Agents::ConferenciaDoAjuste.new(account: @account, credential: credential)
                                                        .conferir(pedido: pedido, mudancas: mudancas, antes: antes,
                                                                  depois: regras_do_ajuste.retrato(@thread.agent))
    @thread.agent.anotar_versao_do_construtor!('pedido' => pedido, 'mudancas' => mudancas, 'conferencia' => conferencia)
    conferencia
  end

  # UMA tentativa: chamada completa do Construtor, com a configuração já aplicada no contexto e o aviso do que faltou.
  # -> a lista que a correção aplicou, ou nil quando ela não aplicou nada.
  def corrigir(token, conferencia)
    @built_input = nil
    parsed = parse_output(call_model(full_phase, Autonomia::Agents::Config::BUILDER_REASONING_EFFORT_FINAL,
                                     aviso: regras_do_ajuste.item_de_correcao(conferencia)))
    return nil if parsed.nil?

    mudancas = regras_do_ajuste.mudancas(parsed)
    return nil if motivo_para_nao_aplicar(parsed, mudancas)
    return nil unless aplicar_lista(token, parsed, mudancas)

    @parsed_final = parsed
    mudancas
  end

  # O que ainda falta vira PERGUNTA ao dono; o que entrou fica aplicado.
  def fechar_ajuste!(token, conferencia)
    parsed = @parsed_final
    pendente = conferencia['pendencias'].present?
    parsed = parsed.merge('needs_more_info' => true, 'next_question' => regras_do_ajuste.pergunta_do_que_faltou(conferencia)) if pendente
    estado = estado_do_ajuste(parsed).merge('applied' => true, 'truncated_fields' => @campos_truncados,
                                            'so_pergunta' => false, 'conferencia' => conferencia)
    marcou = @thread.mark_ready!(token, state: estado)
    persist_assistant_turn!(parsed['next_question']) if marcou && pendente
  end

  # O state do turno, com o rascunho lido do AGENTE (o que de fato está gravado).
  def estado_do_ajuste(parsed)
    self.class.state_for(parsed.merge(regras_do_ajuste.rascunho_do_agente(@thread.agent)))
  end

  def ultima_fala_do_dono
    Array(@thread.messages).reverse.find { |m| m['role'] == 'user' && m['content'].to_s.present? }.to_h['content']
  end
end
