# Vários assuntos numa mensagem (#1693): a parte do Crm::Subjects::Applier que aplica a lista de assuntos de uma
# mensagem. Usa o que o Applier já tem (aplicar, decidir, a trava, o respeito à pessoa, criar e dar nome).
module Crm::Subjects::VariosAssuntos
  # Vários assuntos numa mensagem (#1693). Os outros primeiro e o principal por último, que é quem a decisão registra:
  # o foco termina nele. Assunto aberto só entra na lista (a IA do CRM avalia); pedido novo cria o card só na
  # Automática e sem pessoa a respeitar (Sugerir e o respeito à pessoa valem para cada um). Devolve os atributos da
  # decisão e `tocados`: os cards que a mensagem tocou, o principal primeiro. "Nenhum assunto" toca o card em foco
  # (#1918): a mensagem sem pedido novo ("já fechei com outra", "obrigado") é sobre ele, e quem decide se ele fica ou
  # muda é a IA de etapa. Vencida por uma mais nova no meio, só os cards que ela já criou. Principal em dúvida (nil): os
  # outros seguem, e o resultado é `duvida` (os atributos da decisão em dúvida).
  #
  # Erro depois de um card já gravado (um pedido novo criado, ou o principal aplicado): a decisão fica como falha, com
  # esses cards, e não é desfeita (o retry do job criaria o card de novo). O foco fica no principal aplicado, ou volta
  # ao assunto de antes se ainda está num card criado. Erro antes disso sobe, e o Identifier desfaz a reserva.
  def aplicar_varios(principal, outros, duvida: nil)
    criados = []
    @principal_aplicado = nil
    @resultado_principal = nil
    aplicar_todos(principal, outros, duvida, criados)
  rescue StandardError => e
    salvos = [@principal_aplicado, *criados].compact.uniq(&:id)
    raise if salvos.empty?

    falha_depois_de_gravar(e, criados, salvos)
  end

  private

  # O foco é melhor esforço: uma segunda falha não pode levar o Identifier a desfazer a decisão (e duplicar o card).
  def falha_depois_de_gravar(erro, criados, salvos)
    ChatwootExceptionTracker.new(erro).capture_exception
    Rails.logger.error("[crm][assunto] vários assuntos falhou depois de gravar decisao=#{@decisao.id} erro=#{erro.class}")
    # O principal já aplicado fica na linha da decisão (ação, card, nome) e no aviso em tempo real (o evento do card).
    aplicado = @resultado_principal.to_h.slice(:action, :card, :title, :pipeline, :evento)
    falha = { action: 'none', **aplicado, state: 'failed', reason: erro.class.name.first(120) }
    begin
      devolver_foco(@principal_aplicado ? @resultado_principal : falha, criados)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e).capture_exception
    end
    falha.merge(tocados: salvos)
  end

  def aplicar_todos(principal, outros, duvida, criados)
    tocados = outros.filter_map { |escolha| tocar(escolha, criados) }
    resultado = aplicar_principal(principal, duvida)
    devolver_foco(resultado, criados) if criados.any?
    return resultado.merge(tocados: criados) if resultado[:state] == 'superseded'

    do_principal = card_do_principal(principal&.opcao, resultado)
    resultado.merge(tocados: [do_principal, *tocados].compact.uniq(&:id))
  end

  # O principal, ou a dúvida dele (que pode virar sugestão, #2162). Aplicado, o card dele já está gravado (conta para a
  # falha depois de gravar).
  def aplicar_principal(principal, em_duvida)
    return duvida(em_duvida) unless principal

    aplicar(principal.opcao, principal.titulo, principal.etapa, generico: principal.generico == true).tap do |resultado|
      next unless resultado[:state] == 'applied'

      @principal_aplicado = resultado[:card]
      @resultado_principal = resultado
    end
  end

  # O assunto encerrado (F2) não toca card nenhum: cai fora do case (nil).
  def tocar(escolha, criados)
    opcao = escolha.opcao
    case opcao.tipo
    when :mesmo then @question.atual
    when :card then opcao.card
    when :novo
      etapa = @question.etapa(opcao.pipeline, escolha.etapa)
      outro_pedido_novo(opcao.pipeline, escolha.titulo, etapa, generico: escolha.generico == true)&.tap { |card| criados << card }
    end
  end

  # O pedido novo que não é o principal: nasce sem levar o foco embora (o principal, aplicado depois, fica com ele).
  # etapa (#1910): a coluna escolhida, ou nil (1ª etapa). generico (#2163): o nome é genérico.
  def outro_pedido_novo(pipeline, titulo, etapa, generico: false)
    return if titulo.blank?

    resultado = nil
    @entradas = []
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      # #2084: o contato que saiu do funil enquanto a IA pensava também não ganha o card do outro pedido.
      next if mensagem_mais_nova? || saiu_do_funil?
      # Sugerir, ou a pessoa a respeitar: o pedido novo que não é o principal não vira card nem sugestão (só cabe uma
      # sugestão por conversa, e ela é do principal). Fica no log.
      if modo_efetivo('create', { pipeline: pipeline }) != 'auto'
        next Rails.logger.info("[crm][assunto] outro pedido novo mantido decisao=#{@decisao.id} funil=#{pipeline.id}")
      end

      resultado = criar_ou_dar_nome(pipeline, titulo, etapa, generico: generico)
    end
    entrar_nas_etapas
    resultado[:card] if resultado&.dig(:state) == 'applied'
  end

  # Como no principal: o assunto atual ainda sem nome, no mesmo funil, ganha o nome em vez de nascer outro card.
  # Também como no principal (C36, #1712): o card sem nome que a caixa criou na chegada vai para o funil do pedido e ganha
  # o nome, em vez de sobrar vazio quando o principal fica em dúvida. O card sem nome que já carregava um pedido (#2163)
  # não é renomeado: o pedido novo vira outro card.
  def criar_ou_dar_nome(pipeline, titulo, etapa, generico:)
    atual = @question.atual
    mesmo_funil = @question.atual_sem_nome? && atual.pipeline_id == pipeline.id
    return dar_nome_e_levar(atual.reload, titulo, etapa, generico: generico) if mesmo_funil && !@question.atual_carrega_pedido?
    return criar(pipeline, titulo, etapa, generico: generico) if mesmo_funil

    @chegada = card_da_chegada(pipeline)
    return adotar_a_chegada(atual.reload, titulo, pipeline, etapa, generico: generico) if @chegada

    criar(pipeline, titulo, etapa, generico: generico)
  end

  # Sem assunto (#1918, revoga o critério 5 do #1693): o card em foco, que o Applier devolve; sem card em foco, nada.
  # Pedido novo que virou sugestão não tem card; a sugestão repetida nem chega aqui (Identifier#tocados_da_repetida).
  # Assunto encerrado (F2): nenhum card a reler; o encerrado não continua.
  def card_do_principal(opcao, resultado)
    return if opcao.nil? || opcao.tipo == Crm::Subjects::Encerrado::TIPO || %w[applied kept suggested].exclude?(resultado[:state])
    return if opcao.tipo == :sem_assunto && chegada_intacta?(resultado[:card])

    resultado[:card]
  end

  # O card vazio que a caixa criou na chegada, ainda intacto, fica de fora no sem assunto (C36, #1711).
  def chegada_intacta?(card)
    Crm::Subjects::CardDaChegada.intacta?(conversation: @conversation, card: card, mode: @mode)
  end

  # Um card novo que não é o principal nasce em foco (Crm::Cards::Creator). Se o foco ainda está num deles, volta para
  # o principal aplicado, ou para o assunto de antes quando o principal não mudou nada (mesmo assunto, sugestão, card
  # fechado, mensagem mais nova). Foco que já saiu deles (outra decisão, uma pessoa) não é mexido. Voltar o foco não
  # agenda avaliação: os cards da mensagem já vão na avaliação conjunta.
  def devolver_foco(resultado, criados)
    foco = resultado[:state] == 'applied' ? resultado[:card] : @question.atual
    return unless foco&.reload&.open?

    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      next unless criados.any? { |card| Crm::Assunto.atual?(card, @conversation) }

      Crm::Cards::Focus.new(account: @account, card: foco, conversation: @conversation, avaliar: false).perform
    end
  end
end
