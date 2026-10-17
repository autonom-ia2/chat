# W4 (#1601): a memória vem DE CARONA na avaliação de card que já roda (nenhuma chamada paga nova). O modelo devolve
# `memoria_ops` junto da etapa; aqui o código confere tudo antes de gravar (Crm::Memoria::Gravador):
#
#   Crm::Memoria::Pendente.guardar!(card:, classificacao:, token:)  # antes de aplicar a avaliação
#   Crm::Memoria::Pendente.aplicar!(card)                           # no fim, e no retry do job (chama este Escritor)
#
# Idempotência (A8): `memoria_ops` fica gravado no card (metadata.ai.memoria_pendente) ANTES de aplicar; o retry do job
# aplica o que ficou pendente sem chamar o modelo de novo. A chave de cada operação é estrutural (avaliação, card,
# operação, grupo, chave, item, hash do valor). A avaliação superada (outra agendada depois dela, relendo o card) não
# grava nada.
#
# Conferências, nesta ordem, por operação:
#  1. grupo (contato, pedido, conversa, decisao) e chave no catálogo; fora dele, descartada e contada.
#  2. provas: só os ids LOCAIS (m1..mN) que esta avaliação enviou (A10); da mesma conta, públicas, sem duplicata,
#     indisponível, sem conteúdo ou encaminhada; voto que não vale mais (TurnKinds.choice_current?) não prova.
#  3. pedido e decisão: cada prova presa ao card pela decisão de assunto (applied, accepted, kept) ou, sem decisão, a
#     conversa tinha UM card aberto ligado no momento da mensagem; senão, sugestão.
#  4. fonte = a mais fraca das provas (ia_nossa < cliente < equipe). Fato cuja única prova é nossa (IA, follow-up,
#     robô, sistema) é rejeitado; decisão aceita.
#  5. identidade e item natural: o valor (e o item) precisam aparecer na prova normalizada (A9); senão, sugestão.
#  6. status sempre `alegado`: o modelo não tem campo de fonte nem de status.
class Crm::Memoria::Escritor
  GRUPOS = {
    'contato' => %w[contact_attribute contato], 'pedido' => %w[card_attribute card],
    'conversa' => %w[conversation_attribute conversa], 'decisao' => %w[sistema card]
  }.freeze
  # Quem escreveu -> fonte do fato. Eco nosso (IA, follow-up, robô de fora, sistema) nunca prova fato sobre o mundo.
  FONTE_DO_AUTOR = {
    'cliente' => 'cliente', 'desconhecido' => 'cliente', 'pessoa_painel' => 'equipe', 'pessoa_celular' => 'equipe',
    'ia_nossa' => 'ia_nossa', 'follow_up_nosso' => 'ia_nossa', 'robo_externo' => 'ia_nossa', 'sistema' => 'ia_nossa'
  }.freeze
  ESTADOS_DE_ASSUNTO = %w[applied accepted kept].freeze

  def initialize(card:, pendente:)
    @card = card
    @account = card.account
    @pendente = pendente
    @contagem = Hash.new(0)
  end

  # Ordem das travas: conversa e depois card (a da Entrega e das Passagens). Cada operação no seu savepoint.
  def aplicar
    return if @card.contact_id.blank?

    Crm::MemoriaFato.transaction do
      conversa = @card.conversa_em_atendimento
      Conversation.where(id: conversa.id).lock.pick(:id) if conversa
      Crm::Card.where(id: @card.id).lock.pick(:id)
      @pendente['ops'].each { |dados| aplicar_com_seguranca(dados) }
    end
    Rails.logger.info("[crm][memoria][escritor] card=#{@card.id} #{@contagem.map { |motivo, total| "#{motivo}=#{total}" }.join(' ')}")
    @contagem
  end

  private

  # Uma operação do modelo já resolvida: o grupo, o escopo, a chave do catálogo e as provas que valem.
  Operacao = Struct.new(:dados, :grupo, :escopo, :definicao, :provas, keyword_init: true) do
    def decisao? = grupo == 'decisao'
    def valor = dados['valor'].to_s.strip
  end

  # Uma operação que falha (dado fora do formato, corrida perdida de novo) é contada e vai ao rastreador; as outras
  # seguem, cada uma no seu savepoint.
  def aplicar_com_seguranca(dados)
    Crm::MemoriaFato.transaction(requires_new: true) { aplicar_op(dados.to_h) }
  rescue ActiveRecord::ActiveRecordError, ArgumentError, TypeError, NoMethodError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    contar(:erro)
  end

  def aplicar_op(dados)
    operacao = resolver(dados)
    return contar(:chave_fora_do_catalogo) if operacao.definicao.nil?
    return contar(:sem_prova) if operacao.provas.empty?

    fonte = fonte_de(operacao.provas)
    return contar(:so_eco_nosso) if !operacao.decisao? && fonte == 'ia_nossa'
    return invalidar!(dados) if dados['op'] == 'invalidar'

    gravar!(operacao, fonte)
  end

  def resolver(dados)
    grupo = dados['grupo'].to_s
    modelo, escopo = GRUPOS[grupo]
    chave = grupo == 'decisao' ? Crm::Memoria::Catalogo::DECISAO : dados['chave'].to_s
    Operacao.new(dados: dados, grupo: grupo, escopo: escopo, definicao: modelo && catalogo[[modelo, chave]],
                 provas: provas_de(dados['provas']))
  end

  def gravar!(operacao, fonte)
    valor = operacao.valor
    return contar(:sem_valor) if valor.empty?

    item = item_de(operacao, valor)
    atributos = base(operacao).merge(
      tipo: operacao.decisao? ? 'decisao' : 'fato', chave: operacao.definicao.chave, item_ref: item.to_s, valor: valor, fonte: fonte,
      situacao: sugestao?(operacao, valor, item) ? 'sugestao' : nil, base_versao: operacao.dados['base_versao'].presence&.to_i,
      idempotency_key: chave_idempotente(operacao, item, valor)
    )
    contar(Crm::Memoria::Gravador.gravar!(atributos.compact)&.situacao || :nada)
  end

  def base(operacao)
    provas = operacao.provas
    desde = provas.map(&:created_at).max
    validade = operacao.definicao.validade_dias
    {
      account_id: @account.id, contact_id: @card.contact_id, escopo: operacao.escopo,
      card_id: (@card.id if operacao.escopo == 'card'), conversation_id: (provas.last.conversation_id if operacao.escopo == 'conversa'),
      prova_message_ids: provas.map(&:id), prova_trecho: texto(provas.max_by(&:created_at)), valido_desde: desde,
      vence_em: validade && (desde + validade.days), gerado_por: "avaliacao@#{@pendente['avaliacao_id'].to_s.first(8)}/#{@pendente['modelo']}"
    }
  end

  # Cardinalidade N: cada item é um fato, pelo identificador natural (a placa). A própria chave de item natural usa o
  # valor como item; as outras chaves do item precisam do item dito pelo modelo.
  def item_de(operacao, valor)
    definicao = operacao.definicao
    return '' if !definicao.varios? || operacao.decisao?
    return Crm::Memoria::Normal.linha(valor) if definicao.item_natural?

    Crm::Memoria::Normal.linha(operacao.dados['item_ref'].to_s).presence
  end

  def sugestao?(operacao, valor, item)
    return true if %w[pedido decisao].include?(operacao.grupo) && !operacao.provas.all? { |message| prova_do_card?(message) }
    return true if operacao.definicao.varios? && !operacao.decisao? && item.blank?

    !conferido_na_prova?(operacao, valor, item)
  end

  # A9: identidade e item natural têm de estar no que o cliente ou a equipe disse; o item, sempre que houver.
  def conferido_na_prova?(operacao, valor, item)
    textos = de_quem_disse(operacao.provas).map { |message| texto(message) }
    return false if operacao.definicao.conferir_na_prova? && !Crm::Memoria::Normal.contido?(valor, textos)

    item.blank? || Crm::Memoria::Normal.contido?(item, textos)
  end

  # Invalidar: só fato vivo deste contato (e deste card, no escopo card), sem trava, na versão que o modelo viu.
  def invalidar!(dados)
    fato = Crm::MemoriaFato.vigentes.find_by(id: dados['alvo_fato_id'].to_i, account_id: @account.id, contact_id: @card.contact_id)
    return contar(:invalidar_sem_alvo) if fato.nil? || (fato.escopo == 'card' && fato.card_id != @card.id)
    return contar(:invalidar_travado) if fato.travado? || (dados['base_versao'].present? && dados['base_versao'].to_i != fato.versao)

    fato.update!(expirado_em: Time.current)
    contar(:invalidado)
  end

  def provas_de(refs)
    ids = Array(refs).filter_map { |ref| @pendente['refs'][ref.to_s] }.uniq
    return [] if ids.empty?

    Message.where(id: ids, account_id: @account.id, private: false).includes(:attachments).to_a.select { |message| vale_como_prova?(message) }
  end

  # Sem autoria (mensagem sem contato) não prova; descartável (duplicata, sem conteúdo, encaminhada) também não.
  def vale_como_prova?(message)
    origem = Crm::Memoria::Origem.para(message)
    return false if origem.nil? || origem.descartavel?

    voto_atual?(message)
  end

  # Voto de enquete ou escolha de lista (#1709/#1741): vale só enquanto for a escolha atual
  # (Waha::RichNative::TurnKinds.choice_current?). Sem essa leitura na base, voto nenhum prova nada.
  MARCAS_DE_VOTO = %w[c2y_ai_turn selected_option poll_votes].freeze

  def voto_atual?(message)
    atributos = message.content_attributes.to_h
    return true if MARCAS_DE_VOTO.none? { |marca| atributos[marca].present? }
    return false unless defined?(Waha::RichNative::TurnKinds)

    Waha::RichNative::TurnKinds.choice_current?(message)
  end

  # O valor precisa estar no que o cliente ou a equipe disse, não no eco da nossa IA (A9). Decisão só da IA: as provas dela.
  def de_quem_disse(provas)
    proprias = provas.reject { |message| FONTE_DO_AUTOR[Crm::Memoria::Origem.para(message).autor_tipo] == 'ia_nossa' }
    proprias.presence || provas
  end

  # A mais fraca das provas que não são eco nosso: o cliente + a IA repetindo dá `cliente`. Só eco nosso: `ia_nossa`.
  def fonte_de(provas)
    fontes = provas.map { |message| FONTE_DO_AUTOR.fetch(Crm::Memoria::Origem.para(message).autor_tipo, 'cliente') }
    (fontes - ['ia_nossa']).min_by { |fonte| Crm::MemoriaFato.forca(fonte) } || 'ia_nossa'
  end

  def prova_do_card?(message)
    decisoes = Crm::SubjectDecision.where(account_id: @account.id, conversation_id: message.conversation_id, message_id: message.id,
                                          state: ESTADOS_DE_ASSUNTO).to_a
    return decisoes.any? { |decisao| decisao.card_id == @card.id || Array(decisao.touched_card_ids).include?(@card.id) } if decisoes.any?

    cards_abertos_em(message) == [@card.id]
  end

  # Os cards ligados à conversa e abertos no momento da mensagem (M15).
  def cards_abertos_em(message)
    momento = message.created_at
    ligados = Crm::CardConversation.where(account_id: @account.id, conversation_id: message.conversation_id, created_at: ..momento)
                                   .pluck(:card_id)
    ligados |= Crm::Card.where(account_id: @account.id, conversation_id: message.conversation_id).pluck(:id)
    Crm::Card.where(id: ligados, created_at: ..momento).where('closed_at IS NULL OR closed_at > ?', momento).pluck(:id)
  end

  def texto(message)
    partes = [message.content.to_s]
    message.attachments.each do |anexo|
      meta = anexo.meta.to_h
      partes << meta['transcribed_text'].to_s << meta['ai_caption'].to_s
    end
    partes.compact_blank.join(' ').squish
  end

  def chave_idempotente(operacao, item, valor)
    "aval:#{@pendente['avaliacao_id']}:card:#{@card.id}:#{operacao.dados['op']}:#{operacao.grupo}:#{operacao.definicao.chave}:" \
      "#{item}:#{Digest::SHA256.hexdigest(valor).first(16)}"
  end

  def catalogo
    @catalogo ||= Crm::Memoria::Catalogo.da_conta(@account)
  end

  def contar(motivo)
    @contagem[motivo.to_s] += 1
    nil
  end
end
