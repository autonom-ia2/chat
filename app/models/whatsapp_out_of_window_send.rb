# Registro de cada mensagem automática enviada fora da janela de 24 h por modelo (#1585, "Tabela própria"). Uma linha
# por mensagem, gravada por `Whatsapp::Templates::EnvioForaDaJanela.registrar_envio` depois que o envio saiu: o tipo, o
# caminho, a escolha, o modelo, a categoria, a origem e a autorização vigente naquele instante.
#
# Append-only e guardado para sempre (Rodrigo, 15/10/2026: "trava no banco"; "o cliente pode entrar na justiça tempos
# depois"): o Postgres recusa UPDATE, DELETE e TRUNCATE (gatilho da migration 20261103100000), e o app também não muda
# nem apaga (`readonly?`). Sem chave estrangeira: conta, caixa, mensagem, follow-up ou autorização apagados deixam a
# linha intacta, com o id de origem. Por isso toda referência é `optional` na leitura; na criação, conta e caixa são
# obrigatórias e toda referência informada precisa existir e ser da conta.
class WhatsappOutOfWindowSend < ApplicationRecord
  REFERENCIAS_DA_CONTA = %i[inbox message crm_follow_up whatsapp_template_consent].freeze

  belongs_to :account, optional: true
  belongs_to :inbox, optional: true
  belongs_to :message, optional: true
  belongs_to :crm_follow_up, class_name: 'Crm::FollowUp', optional: true
  belongs_to :whatsapp_template_consent, optional: true

  validates :account, :inbox, presence: true, on: :create
  validates :tipo, :caminho, :template_name, :template_language, :categoria, :origem, presence: true
  validate :referencias_da_mesma_conta, on: :create

  def readonly?
    persisted?
  end

  private

  # Sem chave estrangeira, o banco não confere nada: o id informado precisa apontar para uma linha que existe e é da conta.
  def referencias_da_mesma_conta
    REFERENCIAS_DA_CONTA.each do |campo|
      next if public_send(:"#{campo}_id").nil?

      referencia = public_send(campo)
      errors.add(campo, :invalid) if referencia.nil? || referencia.account_id != account_id
    end
  end
end
