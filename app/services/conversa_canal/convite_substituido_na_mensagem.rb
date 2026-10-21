# E-mail recebido com convite de reunião (#1995): confere, fora do recebimento, se ele substitui um convite anterior da
# mesma reunião, ou se já chega substituído (ConversaCanal::ConviteSubstituido). Antes de gravar, guarda a chave do UID
# em additional_attributes.convite_uid_sha256, que a busca usa pelo índice (#2042). Entra no Message por um prepend
# (config/initializers/conversa_canal_email.rb).
module ConversaCanal::ConviteSubstituidoNaMensagem
  def self.prepended(base)
    base.before_create :conversa_canal_chave_do_convite
    base.after_create_commit :conversa_canal_convite_substituido
  end

  private

  def conversa_canal_chave_do_convite
    return unless conversa_canal_convite_uid

    self.additional_attributes = (additional_attributes || {}).merge(
      'convite_uid_sha256' => ConversaCanal::ConviteSubstituido.chave(conversa_canal_convite_uid)
    )
  end

  def conversa_canal_convite_substituido
    return unless conversa_canal_convite_uid

    ConversaCanal::ConviteSubstituidoJob.perform_later(self)
  end

  def conversa_canal_convite_uid
    uid = (content_attributes || {}).deep_stringify_keys.dig('email', 'convite', 'uid')
    uid if incoming? && uid.present?
  end
end
