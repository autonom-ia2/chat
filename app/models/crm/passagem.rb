# Uma passagem de conversa (#1606): de quem, para quem, pedida por quem, quando, e quando voltou. Quem grava é só o
# Crm::Passagens (registrar! e, na desatribuição sem destino, encerrar_aberta!); aqui ficam a forma e a leitura.
#
# Em aberto: devolvida_em vazio. A "passagem em aberto" de uma conversa é a mais recente delas
# (Crm::Passagens.ultima_aberta).
class Crm::Passagem < ApplicationRecord
  self.table_name = 'crm_passagens'

  CLASSES = ['User', 'Autonomia::Agents::Agent', 'AgentBot'].freeze
  # Passagens em que o robô passou a conversa mesmo sem `de` gravado (o robô que pede ou é desligado, o n8n, a IA do
  # CRM, a recuperação de mensagem). Com `de` gravado, a origem é a própria classe dele.
  MOTIVOS_DA_IA = %w[robo_pediu robo_desligado n8n ia_crm recuperacao_falhou recuperacao_tarde].freeze

  # Uma ponta já resolvida: tipo (:pessoa | :ia), classe ('User' | 'Autonomia::Agents::Agent' | 'AgentBot'), id (na
  # tabela da classe) e o nome gravado na hora.
  Ponta = Struct.new(:tipo, :classe, :id, :nome, keyword_init: true) do
    def mesma?(outra)
      outra.present? && classe == outra.classe && id.to_i == outra.id.to_i
    end

    def pessoa?
      tipo == :pessoa
    end

    def ia?
      tipo == :ia
    end
  end

  belongs_to :account
  belongs_to :conversation
  belongs_to :card, class_name: 'Crm::Card', optional: true
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true

  validates :para_type, inclusion: { in: CLASSES }
  validates :para_id, :em, presence: true
  validates :de_type, inclusion: { in: CLASSES }, allow_nil: true
  validates :pedida_por_type, :devolvida_por_type, inclusion: { in: CLASSES }, allow_nil: true

  scope :abertas, -> { where(devolvida_em: nil) }
  # A IA passou a conversa para uma pessoa da equipe (filtro "Recebidas da IA" da caixa, #1883). `de_type` vazio não é
  # IA por si (a atribuição sem ninguém antes): só entra pelo motivo. Pessoa → IA (passar_para_ia) fica de fora.
  scope :da_ia_para_equipe, lambda {
    where(para_type: 'User').merge(where.not(de_type: 'User').or(where(motivo: MOTIVOS_DA_IA)))
  }
  # A trava da conversa serializa as gravações: o id é a ordem real (o relógio de dois servidores pode divergir).
  scope :em_ordem, -> { order(id: :desc) }

  def de
    ponta(:de)
  end

  def para
    ponta(:para)
  end

  def pedida_por
    ponta(:pedida_por)
  end

  def devolvida_por
    ponta(:devolvida_por)
  end

  def aberta?
    devolvida_em.nil?
  end

  private

  def ponta(lado)
    classe = self["#{lado}_type"]
    return if classe.blank?

    Ponta.new(tipo: classe == 'User' ? :pessoa : :ia, classe: classe, id: self["#{lado}_id"], nome: self["#{lado}_nome"])
  end
end
