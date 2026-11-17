# O que o segurado respondeu ao "Algo mudou?" da renovação (E8, #2901), a partir de uma mensagem recebida
# (Carteira::CotacaoRespostaListener). Nunca pelo texto (nada de lista de palavras):
#
# 1. O toque no botão: a resposta rápida chega com `content_attributes.selected_option.id` = o payload do botão
#    (`renovacao_nada_mudou` / `renovacao_mudou`, gravado pelo RichMessages::SelectedOption) e `in_reply_to` = a mensagem
#    do modelo. Só vale quando `in_reply_to` aponta uma mensagem da MESMA conversa com a marca da cotação na etapa
#    `algo_mudou`, o seguro da marca é da conta e do contato da conversa, e o portão está aberto. O primeiro toque da
#    vigência vale (`respondeu_algo_mudou` com `resposta`, `conversa_id` e `mensagem`, o id; travado e relido sob a trava):
#    - `nada_mudou`: a cotação segue (Carteira::Cotacao::CotarJob);
#    - `mudou`: o robô não cota. A equipe é avisada e, quando quem responde é a equipe, sai na sessão o "O que mudou?"
#      (com "Lia responde", quem pergunta é a Lia, no turno normal dela).
# 2. A mensagem seguinte do segurado na mesma conversa, depois do "Mudou algo": entra na história como
#    `cliente_respondeu` (só o id da mensagem, nunca o texto) e avisa a equipe. Uma vez por vigência.
class Carteira::Cotacao::Resposta
  RESPONDEU = 'respondeu_algo_mudou'.freeze
  CLIENTE_RESPONDEU = 'cliente_respondeu'.freeze

  def initialize(message)
    @message = message
  end

  def call
    return unless @message&.incoming? && Carteira::Cotacao::Liberada.para?(@message.account)

    resposta = Carteira::Cotacao::RESPOSTAS[selecionado]
    resposta ? botao(resposta) : depois_do_mudou
  end

  private

  def botao(resposta)
    apolice, config = da_marca
    return if apolice.nil?
    return unless primeiro_toque!(apolice, resposta)

    resposta == Carteira::Cotacao::NADA_MUDOU ? cotar(apolice) : mudou(apolice, config)
  end

  def primeiro_toque!(apolice, resposta)
    apolice.with_lock(requires_new: true) do
      next false if Carteira::Cotacao.passo(apolice, RESPONDEU)

      Carteira::Cotacao.registrar(apolice, RESPONDEU, resposta: resposta, conversa_id: @message.conversation_id, mensagem: @message.id)
      true
    end
  end

  def cotar(apolice)
    Carteira::Cotacao::CotarJob.perform_later(apolice.id, apolice.fim_vigencia.iso8601)
  end

  def mudou(apolice, config)
    Carteira::Cotacao::Aviso.new(apolice, 'mudou').call
    return if config.quem_responde == Carteira::RenovacaoConfig::LIA

    texto = I18n.t('carteira.cotacao.o_que_mudou', locale: @message.account.locale.presence || I18n.default_locale)
    Carteira::Cotacao::Envio.new(apolice, config).texto(@message.conversation, texto, Carteira::Cotacao::ETAPA_O_QUE_MUDOU)
  end

  # O seguro da marca da mensagem citada, se ela é nossa, da mesma conversa e do "Algo mudou?". -> [apolice, config] ou nil.
  def da_marca
    citada_id = atributos(@message.content_attributes)[:in_reply_to]
    return if citada_id.blank?

    marca = Carteira::Cotacao.marca_de(@message.conversation.messages.find_by(id: citada_id))
    return unless marca['etapa'] == Carteira::Cotacao::ETAPA_ALGO_MUDOU

    apolice = Carteira::Apolice.find_by(id: marca['apolice_id'], account_id: @message.account_id)
    return unless apolice && apolice.contact_id == @message.conversation.contact_id

    Carteira::Cotacao.da_vigencia(apolice.id, apolice.fim_vigencia.iso8601)
  end

  # A mensagem seguinte do segurado na conversa em que ele tocou "Mudou algo".
  def depois_do_mudou
    toque = toque_mudou
    return if toque.nil?

    apolice = toque.apolice
    return unless Carteira::Cotacao.da_vigencia(apolice.id, apolice.fim_vigencia.iso8601)
    return unless primeira_resposta!(apolice)

    Carteira::Cotacao::Aviso.new(apolice, CLIENTE_RESPONDEU).call
  end

  def toque_mudou
    do_contato = { account_id: @message.account_id, contact_id: @message.conversation.contact_id }
    Carteira::ApoliceEvento.joins(:apolice).where(carteira_apolices: do_contato)
                           .where(tipo: RESPONDEU)
                           .where("carteira_apolice_eventos.valores->>'resposta' = ?", Carteira::Cotacao::MUDOU)
                           .where("carteira_apolice_eventos.valores->>'conversa_id' = ?", @message.conversation_id.to_s)
                           .where("(carteira_apolice_eventos.valores->>'mensagem')::bigint < ?", @message.id)
                           .order(:quando, :id).last
  end

  def primeira_resposta!(apolice)
    apolice.with_lock(requires_new: true) do
      next false if Carteira::Cotacao.passo(apolice, CLIENTE_RESPONDEU) || !Carteira::Cotacao.mudou?(apolice)

      Carteira::Cotacao.registrar(apolice, CLIENTE_RESPONDEU, mensagem: @message.id)
      true
    end
  end

  def selecionado
    atributos(atributos(@message.content_attributes)[:selected_option])[:id]
  end

  # `content_attributes` e o `selected_option` podem vir como hash (chave texto ou símbolo) ou como json em texto.
  def atributos(valor)
    valor = JSON.parse(valor) if valor.is_a?(String)
    valor.is_a?(Hash) ? valor.with_indifferent_access : {}
  rescue JSON::ParserError
    {}
  end
end
