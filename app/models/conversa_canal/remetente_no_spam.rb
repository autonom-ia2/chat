# Remetente marcado como Spam numa caixa de e-mail (#1809, decisão do Rodrigo, 18/10: "só a caixa de email"). E-mail
# novo dele nessa caixa cai direto no Spam (ConversaCanal::SpamDoBloqueado); o contato e os outros canais seguem
# normais. "Não é spam" apaga a linha. O endereço é guardado em minúsculas.
class ConversaCanal::RemetenteNoSpam < ApplicationRecord
  self.table_name = 'conversa_canal_remetentes_no_spam'

  belongs_to :account
  belongs_to :inbox
  belongs_to :user, optional: true

  validates :email, presence: true, uniqueness: { scope: :inbox_id }

  def self.normalizar(email)
    email.to_s.strip.downcase.presence
  end

  def self.bloqueado?(inbox_id:, email:)
    endereco = normalizar(email)
    endereco.present? && exists?(inbox_id: inbox_id, email: endereco)
  end
end
