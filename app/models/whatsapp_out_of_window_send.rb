# Registro de cada mensagem automática enviada fora da janela de 24 h por modelo (#1585, "Tabela própria"). Uma linha
# por mensagem, gravada por `Whatsapp::Templates::EnvioForaDaJanela.registrar_envio` depois que o envio saiu: o tipo, o
# caminho, a escolha, o modelo, a categoria, a origem e a autorização vigente naquele instante.
# Append-only: linha gravada não muda nem sai pelo app (`readonly?`); só some com a conta ou a caixa (on_delete: cascade).
class WhatsappOutOfWindowSend < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :message, optional: true
  belongs_to :crm_follow_up, class_name: 'Crm::FollowUp', optional: true
  belongs_to :whatsapp_template_consent, optional: true

  validates :tipo, :caminho, :template_name, :template_language, :categoria, :origem, presence: true
  validate :referencias_da_mesma_conta

  def readonly?
    persisted?
  end

  private

  # A chave estrangeira só confere que a linha existe: caixa, mensagem, follow-up e autorização precisam ser da conta.
  def referencias_da_mesma_conta
    { inbox: inbox, message: message, crm_follow_up: crm_follow_up, whatsapp_template_consent: whatsapp_template_consent }
      .each { |campo, referencia| errors.add(campo, :invalid) if referencia && referencia.account_id != account_id }
  end
end
