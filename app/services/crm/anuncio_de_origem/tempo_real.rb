# O tempo real da conversa (#2271): o mesmo evento vai a vários destinatários. Quando ele leva os toques de anúncio da
# conversa e algum destinatário não vê o anúncio (Crm::AnuncioDeOrigem.ve?), o evento sai em dois envios: o inteiro para
# quem vê e o sem o anúncio para quem não vê. Sem toque na conversa ou com todos vendo, sai num envio só, como antes.
#
# Onde o evento leva a conversa: na raiz (eventos da conversa), em `conversation` (digitando) e no `primary_actor` da
# notificação. O token do contato (widget) não é de um usuário e recebe o evento inteiro, como antes.
#
#   Crm::AnuncioDeOrigem::TempoReal.envios(account, tokens, payload)              -> [[tokens, payload], ...]
#   Crm::AnuncioDeOrigem::TempoReal.transmite(account, tokens, event_name, payload) -> um ActionCableBroadcastJob por envio
class Crm::AnuncioDeOrigem::TempoReal
  CAMINHOS = [[], [:conversation], %i[notification primary_actor]].freeze

  def self.envios(account, tokens, payload)
    new(account, tokens, payload).envios
  end

  def self.transmite(account, tokens, event_name, payload)
    envios(account, tokens, payload).each do |destino, dados|
      ::ActionCableBroadcastJob.perform_later(destino, event_name, dados)
    end
  end

  def initialize(account, tokens, payload)
    @account = account
    @tokens = tokens
    @payload = payload
  end

  def envios
    return [[@tokens, @payload]] unless com_toques?

    ocultos = tokens_que_nao_veem
    return [[@tokens, @payload]] if ocultos.empty?

    [[@tokens - ocultos, @payload], [ocultos, payload_oculto]].reject { |tokens, _payload| tokens.empty? }
  end

  private

  def com_toques?
    CAMINHOS.any? do |caminho|
      atributos = atributos_em(caminho)
      atributos.is_a?(Hash) && Crm::AnuncioDeOrigem.com_toques?(atributos.stringify_keys)
    end
  end

  def atributos_em(caminho)
    alvo = caminho.empty? ? @payload : @payload.dig(*caminho)
    alvo[:additional_attributes] if alvo.is_a?(Hash)
  end

  def tokens_que_nao_veem
    usuarios = User.where(pubsub_token: @tokens).select(:id, :pubsub_token).to_a
    return [] if usuarios.empty?

    membros = @account.account_users.where(user_id: usuarios.map(&:id)).index_by(&:user_id)
    usuarios.reject { |usuario| Crm::AnuncioDeOrigem.ve?(membros[usuario.id]) }.map(&:pubsub_token)
  end

  # Cópia só ao longo de cada caminho (sem deep_dup: o payload leva registros, como o contact_inbox, que o job serializa).
  def payload_oculto
    CAMINHOS.reduce(@payload) { |payload, caminho| oculta_em(payload, caminho) }
  end

  def oculta_em(alvo, caminho)
    return alvo unless alvo.is_a?(Hash)

    if caminho.empty?
      atributos = alvo[:additional_attributes]
      return alvo unless atributos.is_a?(Hash)

      return alvo.merge(additional_attributes: Crm::AnuncioDeOrigem.oculta_atributos(atributos.stringify_keys))
    end

    chave, *resto = caminho
    alvo.key?(chave) ? alvo.merge(chave => oculta_em(alvo[chave], resto)) : alvo
  end
end
