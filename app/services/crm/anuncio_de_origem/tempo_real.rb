# O tempo real da conversa (#2271), aplicado no próprio ActionCableBroadcastJob, depois de ele buscar a conversa de novo
# (prepare_broadcast_data): um ponto só cobre o ActionCableListener, o Crm::Access::VisibilitySync e qualquer outro
# chamador. Quando o evento leva um toque de anúncio e algum destinatário não vê o anúncio (Crm::AnuncioDeOrigem.ve?), o
# mesmo job entrega o evento inteiro a quem vê e o sem o anúncio a quem não vê. Sem toque de anúncio (a maioria, inclusive
# digitando), não há consulta: um envio só, como antes.
#
# Se achar quem vê falhar (exceção), o evento NUNCA sai inteiro: todos recebem a conversa sem o anúncio, e o erro vai
# para o log.
#
# Onde o evento leva a conversa: na raiz (eventos da conversa), em `conversation` (digitando) e no `primary_actor` da
# notificação. O token do contato (widget) não é de um usuário e recebe o evento inteiro, como antes.
#
#   Crm::AnuncioDeOrigem::TempoReal.envios(account_id, tokens, payload) -> [[tokens, payload], ...]
class Crm::AnuncioDeOrigem::TempoReal
  CAMINHOS = [[], [:conversation], %i[notification primary_actor]].freeze

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
    Rails.logger.error("[anuncio_de_origem] tempo real sem o recorte por destinatário (account #{@account_id}): #{e.class.name}")
    [[@tokens, payload_oculto]]
  end

  private

  def separados
    ocultos = tokens_que_nao_veem
    return [[@tokens, @payload]] if ocultos.empty?

    [[@tokens - ocultos, @payload], [ocultos, payload_oculto]].reject { |tokens, _payload| tokens.empty? }
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

  # Usuário fora da conta (ou conta não achada) não vê. Token que não é de usuário (contato, widget) não entra aqui.
  def tokens_que_nao_veem
    usuarios = User.where(pubsub_token: @tokens).select(:id, :pubsub_token).to_a
    return [] if usuarios.empty?

    membros = AccountUser.where(account_id: @account_id, user_id: usuarios.map(&:id)).index_by(&:user_id)
    usuarios.reject { |usuario| Crm::AnuncioDeOrigem.ve?(membros[usuario.id]) }.map(&:pubsub_token)
  end

  # Cópia só ao longo de cada caminho (sem deep_dup: o payload leva registros, como o contact_inbox).
  def payload_oculto
    CAMINHOS.reduce(@payload) { |payload, caminho| oculta_em(payload, caminho) }
  end

  def oculta_em(alvo, caminho)
    return alvo unless alvo.is_a?(Hash)
    return oculta_atributos_de(alvo) if caminho.empty?

    chave, *resto = caminho
    alvo.key?(chave) ? alvo.merge(chave => oculta_em(alvo[chave], resto)) : alvo
  end

  def oculta_atributos_de(alvo)
    atributos = alvo[:additional_attributes]
    return alvo unless atributos.is_a?(Hash)

    alvo.merge(additional_attributes: Crm::AnuncioDeOrigem.oculta_atributos(atributos.stringify_keys))
  end
end
