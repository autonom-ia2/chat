# Autorização do dono para o sistema criar modelos da Meta (#1586, épico #1585). Registro append-only: cada vez que
# alguém liga ou desliga uma marca grava uma linha nova, com o texto exato do aviso, a versão e os preços mostrados.
#
# Guardado para sempre (Rodrigo, 15/10/2026: "trava no banco"; "o cliente pode entrar na justiça tempos depois"): o
# Postgres recusa UPDATE, DELETE e TRUNCATE (gatilho da migration 20261104100000), e o app também não muda nem apaga
# (`readonly?`). Sem chave estrangeira: conta ou usuário apagados deixam a linha intacta. `user_name` guarda o nome de
# quem mudou no momento da gravação, para o "quem" sobreviver ao usuário apagado.
#
# Marcas: `utility` (Aviso de serviço: criar e enviar modelos de utilidade) e `marketing` (Divulgação, só com a
# primeira ligada). O estado atual é a última linha por (conta, marca): `ativo?(conta, :utility)`.
class WhatsappTemplateConsent < ApplicationRecord
  MARCAS = %w[utility marketing].freeze
  LIGOU = 'ligou'.freeze
  DESLIGOU = 'desligou'.freeze

  belongs_to :account, optional: true
  belongs_to :user, optional: true

  validates :account, presence: true, on: :create
  validates :marca, inclusion: { in: MARCAS }
  validates :acao, inclusion: { in: [LIGOU, DESLIGOU] }
  validates :versao_aviso, :texto_aviso, presence: true

  # Aviso de serviço ligado (#1586): quem precisa reagir assina este evento (o Agendamento cria os avisos fixos dele).
  # Sai depois do commit, uma vez por linha `utility` + `ligou`; desligar e Divulgação não publicam.
  EVENTO_LIGADO = 'whatsapp_templates.consentimento_ligado'.freeze

  scope :ordem_de_gravacao, -> { order(:created_at, :id) }

  before_create :copiar_nome_de_quem_mudou
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

  def copiar_nome_de_quem_mudou
    self.user_name = user&.name
  end

  # A linha já está gravada: um assinante que falha não pode fazer a tela dizer que a autorização não ligou. A falha
  # fica no log com a classe (sem a mensagem, que pode trazer dado do assinante) para quem assina corrigir.
  def publicar_ligado
    ActiveSupport::Notifications.instrument(EVENTO_LIGADO, account_id: account_id, marca: marca)
  rescue StandardError => e
    Rails.logger.error("[whatsapp][templates][consentimento] evento_falhou account_id=#{account_id} #{e.class.name}")
  end
end
