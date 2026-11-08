# O tempo real da conversa (#2271), aplicado no próprio ActionCableBroadcastJob, depois de ele buscar a conversa de novo
# (prepare_broadcast_data): um ponto só cobre o ActionCableListener, o Crm::Access::VisibilitySync e qualquer outro
# chamador. Quando o evento leva um toque de anúncio e algum destinatário não vê o anúncio (Crm::AnuncioDeOrigem.ve?), o
# mesmo job entrega o evento inteiro a quem vê e o sem o anúncio a quem não vê. Sem toque de anúncio (a maioria, inclusive
# digitando), não há consulta: um envio só, como antes.
#
# Onde o evento leva a conversa: na raiz (eventos da conversa), em `conversation` (digitando) e no `primary_actor` da
# notificação. O token do contato (widget) não é de um usuário e recebe o evento inteiro, como antes.
#
# Se o recorte falhar (exceção), o evento nunca sai inteiro para uma pessoa e o job não deixa de enviar; o erro vai para
# o log e para o ChatwootExceptionTracker (só a classe e o stack):
# - os tokens de pessoa recebem a conversa sem o anúncio; o de contato e widget, a conversa inteira;
# - se nem isso der para saber, todos recebem sem o anúncio;
# - se esconder o anúncio também falhar, a conversa sai sem os campos de campanha (campaign, campaign_touches e
#   campaign_source_ids).
#
#   Crm::AnuncioDeOrigem::TempoReal.envios(account_id, tokens, payload) -> [[tokens, payload], ...]
class Crm::AnuncioDeOrigem::TempoReal
  CAMINHOS = [[], [:conversation], %i[notification primary_actor]].freeze
  CHAVES_DE_CAMPANHA = %w[campaign campaign_touches campaign_source_ids].freeze

  def self.envios(account_id, tokens, payload)
    new(account_id, tokens, payload).envios
  end

  def initialize(account_id, tokens, payload)
    @account_id = account_id
    @tokens = tokens
    @payload = payload
  end

  def envios
    return [[@tokens, @payload]] unless @payload.is_a?(Hash) && com_anuncio?

    separados
  rescue StandardError => e
    registra(e)
    sem_recorte
  end

  private

  def separados
    ocultos = tokens_que_nao_veem
    return [[@tokens, @payload]] if ocultos.empty?

    [[@tokens - ocultos, @payload], [ocultos, payload_oculto]].reject { |tokens, _payload| tokens.empty? }
  end

  # Sem o recorte: as pessoas recebem sem o anúncio; contato e widget, inteiro. Sem saber quem é pessoa, todos sem.
  def sem_recorte
    pessoas = tokens_de_pessoas
    [[@tokens - pessoas, @payload], [pessoas, payload_seguro]].reject { |tokens, _payload| tokens.empty? }
  rescue StandardError => e
    registra(e)
    [[@tokens, payload_seguro]]
  end

  # Os logs de produção somem e o Sentry pode estar desligado: vai para os dois. Só a classe e o stack, nunca a mensagem
  # original (pode trazer o SQL com os pubsub_token; Crm::AnuncioDeOrigem::FalhaNoRecorte).
  def registra(erro)
    Rails.logger.error("[anuncio_de_origem] tempo real sem o recorte por destinatário (account #{@account_id}): #{erro.class.name}")
    ChatwootExceptionTracker.new(Crm::AnuncioDeOrigem::FalhaNoRecorte.de(erro), account: conta_do_evento).capture_exception
  rescue StandardError
    # Já estamos no caminho de erro: registrar não pode impedir o envio.
    nil
  end

  def conta_do_evento
    Account.find_by(id: @account_id)
  rescue StandardError
    nil
  end

  def com_anuncio?
    CAMINHOS.any? do |caminho|
      atributos = atributos_em(caminho)
      atributos.is_a?(Hash) && Crm::AnuncioDeOrigem.com_anuncio?(atributos.stringify_keys)
    end
  end

  def atributos_em(caminho)
    alvo = caminho.empty? ? @payload : @payload.dig(*caminho)
    alvo[:additional_attributes] if alvo.is_a?(Hash)
  end

  def usuarios
    @usuarios ||= User.where(pubsub_token: @tokens).select(:id, :pubsub_token).to_a
  end

  def tokens_de_pessoas = usuarios.map(&:pubsub_token)

  # Usuário fora da conta (ou conta não achada) não vê. Token que não é de usuário (contato, widget) não entra aqui.
  def tokens_que_nao_veem
    return [] if usuarios.empty?

    membros = AccountUser.where(account_id: @account_id, user_id: usuarios.map(&:id)).index_by(&:user_id)
    usuarios.reject { |usuario| Crm::AnuncioDeOrigem.ve?(membros[usuario.id]) }.map(&:pubsub_token)
  end

  def payload_oculto
    troca_atributos { |atributos| Crm::AnuncioDeOrigem.oculta_atributos(atributos.stringify_keys) }
  end

  def payload_seguro
    payload_oculto
  rescue StandardError => e
    registra(e)
    troca_atributos { |atributos| atributos.except(*CHAVES_DE_CAMPANHA, *CHAVES_DE_CAMPANHA.map(&:to_sym)) }
  end

  # Cópia só ao longo de cada caminho (sem deep_dup: o payload leva registros, como o contact_inbox).
  def troca_atributos(&)
    CAMINHOS.reduce(@payload) { |payload, caminho| troca_em(payload, caminho, &) }
  end

  def troca_em(alvo, caminho, &)
    return alvo unless alvo.is_a?(Hash)
    return troca_atributos_de(alvo, &) if caminho.empty?

    chave, *resto = caminho
    alvo.key?(chave) ? alvo.merge(chave => troca_em(alvo[chave], resto, &)) : alvo
  end

  def troca_atributos_de(alvo)
    atributos = alvo[:additional_attributes]
    return alvo unless atributos.is_a?(Hash)

    alvo.merge(additional_attributes: yield(atributos))
  end
end
