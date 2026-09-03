# Sugestão de FAQ extraída de uma conversa RESOLVIDA atendida por um agente Autonom.ia (#284 · 2b).
# Fica pendente até um administrador aprovar (vira KnowledgeEntry), editar-e-aprovar ou ignorar.
# `question_hash` = SHA256 da pergunta normalizada: dedupe barato entre sugestões e contra o
# conhecimento já aprovado (o KnowledgeEntry criado carrega o mesmo hash no metadata).
class Autonomia::Agents::FaqSuggestion < ApplicationRecord
  self.table_name = 'autonomia_agent_faq_suggestions'

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id, inverse_of: :faq_suggestions
  # FKs lógicas: a sugestão sobrevive à conversa/usuário (sem constraint no banco).
  belongs_to :conversation, class_name: '::Conversation', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true

  enum status: { pending: 0, approved: 1, edited: 2, ignored: 3 }

  validates :question, :answer, presence: true
  validates :question, length: { maximum: 500 }
  validates :answer, length: { maximum: 4_000 }

  before_validation :set_question_hash

  scope :ordered, -> { order(created_at: :desc) }

  # Normalização p/ dedupe: sem acentos, minúsculas, só letras/dígitos/espaços, espaços colapsados.
  def self.normalize_question(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9\s]/, ' ').squish
  end

  def self.question_hash_for(text)
    Digest::SHA256.hexdigest(normalize_question(text))
  end

  def reviewed?
    !pending?
  end

  private

  def set_question_hash
    self.question_hash = self.class.question_hash_for(question) if question.present?
  end
end
