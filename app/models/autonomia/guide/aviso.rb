# O que o Guia avisa a uma pessoa quando uma vigia cruza o gatilho (#935).
#
# Um aviso é de UMA pessoa: ela vê os dela (o de outra pessoa é 404) e marca como visto. Pode juntar
# várias vigias que cruzaram no mesmo pulso — é um aviso só.
#
# `chave` é única: o mesmo aviso nunca nasce duas vezes, nem com dois pulsos ao mesmo tempo.
# `sinal` guarda só ids e números do que foi medido; o texto é montado do nome da vigia e desses
# números, sem modelo. Nenhum texto lido da conta entra aqui. Some em 30 dias (`LimparAvisosJob`).
#
# Estados: `novo` (na conversa, ainda não visto), `visto`, `adiado` (passou do orçamento do dia: sai
# no resumo do dia seguinte) e `resumido` (já saiu no resumo).
class Autonomia::Guide::Aviso < ApplicationRecord
  self.table_name = 'autonomia_guide_avisos'

  NOVO = 'novo'.freeze
  VISTO = 'visto'.freeze
  ADIADO = 'adiado'.freeze
  RESUMIDO = 'resumido'.freeze
  ESTADOS = [NOVO, VISTO, ADIADO, RESUMIDO].freeze
  URGENTE = 'urgente'.freeze
  VALIDADE = 30.days

  belongs_to :account
  belongs_to :user
  belongs_to :turno, class_name: 'Autonomia::Guide::Turno', optional: true
  # O sino mostra o aviso urgente; sem o aviso, a notificação ficaria sem o que mostrar.
  has_many :notifications, as: :primary_actor, dependent: :delete_all

  validates :chave, presence: true, uniqueness: true
  validates :texto, presence: true
  validates :estado, inclusion: { in: ESTADOS }
  validates :gravidade, inclusion: { in: Autonomia::Guide::Vigia::GRAVIDADES }
  validate :sinal_so_com_numeros

  scope :de, ->(account, user) { where(account: account, user: user) }
  scope :recentes, -> { order(created_at: :desc, id: :desc) }

  def urgente?
    gravidade == URGENTE
  end

  def para_tela
    { 'id' => id, 'estado' => estado, 'gravidade' => gravidade, 'texto' => texto, 'sinal' => sinal,
      'conversa_id' => turno&.conversation_id, 'criado_em' => created_at.iso8601 }
  end

  # O que a notificação (sino, push) leva do aviso.
  def push_event_data
    { id: id, texto: texto, gravidade: gravidade }
  end

  private

  # Só ids e números: o sinal nunca carrega texto lido da conta (AC-I9).
  def sinal_so_com_numeros
    errors.add(:sinal, 'aceita só ids e números') unless so_numeros?(sinal)
  end

  def so_numeros?(valor)
    case valor
    when Hash then valor.values.all? { |item| so_numeros?(item) }
    when Array then valor.all? { |item| so_numeros?(item) }
    else valor.nil? || valor.is_a?(Numeric)
    end
  end
end
