# E-mail recebido com convite de reunião (#1995): confere, fora do recebimento, se ele substitui um convite anterior da
# mesma reunião, ou se já chega substituído (ConversaCanal::ConviteSubstituido). Entra no Message por um prepend
# (config/initializers/conversa_canal_email.rb).
module ConversaCanal::ConviteSubstituidoNaMensagem
  def self.prepended(base)
    base.after_create_commit :conversa_canal_convite_substituido
  end

  private

  def conversa_canal_convite_substituido
    return unless incoming? && (content_attributes || {}).deep_stringify_keys.dig('email', 'convite', 'uid').present?

    ConversaCanal::ConviteSubstituidoJob.perform_later(self)
  end
end
