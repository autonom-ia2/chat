# Autorização do dono para o sistema criar modelos da Meta (#1586, épico #1585). Registro append-only: cada vez que
# alguém liga ou desliga uma marca grava uma linha nova, com o texto exato do aviso, a versão e os preços mostrados.
# Linha gravada não muda nem sai pelo app (`readonly?`); só some com a conta (on_delete: cascade).
#
# Marcas: `utility` (Aviso de serviço: criar e enviar modelos de utilidade) e `marketing` (Divulgação, só com a
# primeira ligada). O estado atual é a última linha por (conta, marca): `ativo?(conta, :utility)`.
class WhatsappTemplateConsent < ApplicationRecord
  MARCAS = %w[utility marketing].freeze
  LIGOU = 'ligou'.freeze
  DESLIGOU = 'desligou'.freeze

  belongs_to :account
  belongs_to :user, optional: true

  validates :marca, inclusion: { in: MARCAS }
  validates :acao, inclusion: { in: [LIGOU, DESLIGOU] }
  validates :versao_aviso, :texto_aviso, presence: true

  # Aviso de serviço ligado (#1586): quem precisa reagir assina este evento (o Agendamento cria os avisos fixos dele).
  # Sai depois do commit, uma vez por linha `utility` + `ligou`; desligar e Divulgação não publicam.
  EVENTO_LIGADO = 'whatsapp_templates.consentimento_ligado'.freeze

  scope :ordem_de_gravacao, -> { order(:created_at, :id) }

  after_create_commit :publicar_ligado, if: -> { marca == 'utility' && acao == LIGOU }

  def self.ativo?(account, marca)
    ultima(account, marca)&.acao == LIGOU
  end

  def self.ultima(account, marca)
    where(account_id: account.id, marca: marca.to_s).ordem_de_gravacao.last
  end

  def readonly?
    persisted?
  end

  private

  # A linha já está gravada: um assinante que falha não pode fazer a tela dizer que a autorização não ligou. A falha
  # fica no log com a classe (sem a mensagem, que pode trazer dado do assinante) para quem assina corrigir.
  def publicar_ligado
    ActiveSupport::Notifications.instrument(EVENTO_LIGADO, account_id: account_id, marca: marca)
  rescue StandardError => e
    Rails.logger.error("[whatsapp][templates][consentimento] evento_falhou account_id=#{account_id} #{e.class.name}")
  end
end
