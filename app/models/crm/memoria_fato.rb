# Um fato da memória das IAs (#1601), com procedência: de onde veio (fonte), se é alegado ou confirmado (status), a
# mensagem que o sustenta (prova_message_ids, prova_trecho copiado pelo código) e o tempo (valido_desde/vence_em, do
# mundo; registrado_em/expirado_em, do sistema). A versão antiga expira, não é apagada. Quem grava é só o
# Crm::Memoria::Gravador. A fonte e o status saem do código; o CHECK do banco impede `confirmado` vindo do cliente.
class Crm::MemoriaFato < ApplicationRecord
  self.table_name = 'crm_memoria_fatos'

  ESCOPOS = %w[card contato conversa].freeze
  TIPOS = %w[fato decisao pedido_encerrado].freeze
  SITUACOES = %w[vigente sugestao divergente].freeze
  # Da mais fraca para a mais forte. A fonte de um fato é a mais fraca das provas dele.
  FONTES = %w[ia_nossa cliente equipe sistema ferramenta_resultado pessoa_corrigiu].freeze
  CONFIRMAM = %w[ferramenta_resultado sistema pessoa_corrigiu].freeze
  VALOR_MAXIMO = 300

  belongs_to :account
  belongs_to :contact
  belongs_to :card, class_name: 'Crm::Card', optional: true

  validates :escopo, inclusion: { in: ESCOPOS }
  validates :tipo, inclusion: { in: TIPOS }
  validates :situacao, inclusion: { in: SITUACOES }
  validates :fonte, inclusion: { in: FONTES }
  validates :status, inclusion: { in: %w[alegado confirmado] }

  scope :vivos, -> { where(expirado_em: nil) }
  scope :vigentes, -> { vivos.where(situacao: 'vigente') }

  def self.forca(fonte)
    FONTES.index(fonte.to_s) || 0
  end

  def forca
    self.class.forca(fonte)
  end

  def vencido?(agora = Time.current)
    vence_em.present? && vence_em <= agora
  end

  def confirmado?
    status == 'confirmado'
  end
end
