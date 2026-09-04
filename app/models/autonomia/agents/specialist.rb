# == Schema Information
#
# Table name: autonomia_agent_specialists
#
#  id                 :bigint           not null, primary key
#  custom_instruction :text
#  description        :text             not null
#  enabled            :boolean          default(TRUE), not null
#  instruction        :text             not null
#  metadata           :jsonb            not null
#  name               :string           not null
#  slug               :string           not null
#  tool_slugs         :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#
# Indexes
#
#  idx_autonomia_agent_specialists_account_enabled          (account_id,enabled)
#  idx_autonomia_agent_specialists_agent_slug               (autonomia_agent_id,slug) UNIQUE
#  index_autonomia_agent_specialists_on_autonomia_agent_id  (autonomia_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Subagente especializado de um agente Autonom.ia (#311).
#
# DELEGAÇÃO ENTRE AGENTES, NÃO PARA HUMANO. O caminho agente -> pessoa continua sendo
# `Crm::Ai::HandoffExecutor` (CRM/kanban/atribuição), acionado pela instrução — este model NÃO
# encosta nele e não usa `Captain::Tools::HandoffTool`.
#
# O especialista é exposto ao modelo como uma FUNÇÃO (`consultar_<slug>`). Quando o principal a
# chama, o Specialists::Runner roda um ciclo próprio — instrução própria, tools próprias — e
# devolve TEXTO CORRIDO. O principal parafraseia; não interpreta estrutura. Esse contrato em prosa
# é deliberado: é o que funciona nos fluxos de cotação em produção e evita que o principal precise
# entender o payload de um ramo inteiro.
class Autonomia::Agents::Specialist < ApplicationRecord
  self.table_name = 'autonomia_agent_specialists'

  # Teto por agente. Era 8, escolhido por precaução e sem medição — e 8 não cabe o produto: o
  # catálogo do AGGER tem 65 produtos, 26 ativos, e o desenho é um especialista por ramo.
  #
  # O que o teto protege NÃO é a escolha do modelo: o `Answerer` expõe apenas os especialistas
  # HABILITADOS naquela conta, e uma corretora habilita os ramos que vende (a conta que medimos
  # tem 10). O que ele protege é o prompt de cada turno, que carrega o schema de toda função
  # declarada. 30 é folga para o catálogo inteiro e ainda barra configuração absurda.
  #
  # Se um dia uma conta habilitar dezenas de ramos e o roteamento começar a errar, o conserto não é
  # subir este número: é uma função de cotação só, recebendo o ramo como parâmetro.
  MAX_PER_AGENT = 30
  # A OpenAI limita nome de função a 64 chars; `consultar_` come 10.
  FUNCTION_PREFIX = 'consultar_'.freeze
  MAX_SLUG_LENGTH = 54
  SLUG_FORMAT = /\A[a-z][a-z0-9_]*\z/
  MAX_INSTRUCTION_LENGTH = 50_000
  MAX_CUSTOM_INSTRUCTION_LENGTH = 20_000
  MAX_DESCRIPTION_LENGTH = 500
  # Nome do único parâmetro da função. O principal escreve aqui, em português, o que precisa do
  # especialista ("cotar auto para o CPF X, placa Y").
  REQUEST_PARAM = 'pedido'.freeze

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                     inverse_of: :specialists

  before_validation :normalize_slug
  before_validation :inherit_account
  before_validation :normalize_tool_slugs
  before_create :ensure_within_limit

  validates :name, presence: true
  validates :description, presence: true, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :instruction, presence: true, length: { maximum: MAX_INSTRUCTION_LENGTH }
  validates :custom_instruction, length: { maximum: MAX_CUSTOM_INSTRUCTION_LENGTH }, allow_nil: true
  validates :slug, presence: true, uniqueness: { scope: :autonomia_agent_id },
                   length: { maximum: MAX_SLUG_LENGTH }, format: { with: SLUG_FORMAT }

  scope :enabled, -> { where(enabled: true) }

  def function_name
    "#{FUNCTION_PREFIX}#{slug}"
  end

  # Schema da função exposta ao modelo. Um parâmetro só, de propósito: quanto mais estrutura o
  # principal tiver que preencher, mais ele erra — quem conhece os campos do ramo é o especialista.
  def openai_schema
    {
      type: 'function',
      name: function_name,
      description: description,
      parameters: {
        type: 'object',
        properties: {
          REQUEST_PARAM => {
            type: 'string',
            description: 'O que você precisa do especialista, em português, com os dados que o cliente já forneceu.'
          }
        },
        required: [REQUEST_PARAM],
        additionalProperties: false
      },
      strict: true
    }
  end

  # Instrução efetiva: bloco do sistema primeiro, bloco do dono da conta depois. A ordem importa —
  # o bloco do sistema estabelece escopo e regras duras; o do cliente ajusta tom e detalhe da
  # corretora, sem revogar o que está acima. A UI (#321) só deixa editar `custom_instruction`.
  def effective_instruction
    [instruction, custom_instruction.presence].compact.join("\n\n")
  end

  # Ferramentas reservadas a este especialista, na ordem declarada. Slug que não existe (ou foi
  # desabilitado) é ignorado em silêncio: o especialista trabalha com o que sobrou em vez de
  # derrubar o turno inteiro por causa de uma configuração velha.
  def tools
    return [] if tool_slugs.blank?

    # Memoizado: o runner consulta esta lista uma vez por turno, mas `for_agent` faz consulta ao
    # banco e monta o catálogo de nativas — não há motivo para refazer isso a cada chamada.
    @tools ||= begin
      by_slug = Autonomia::Agents::Tools::Bound.for_agent(agent).index_by(&:slug)
      tool_slugs.filter_map { |slug| by_slug[slug.to_s] }
    end
  end

  private

  def normalize_tool_slugs
    self.tool_slugs = Array(tool_slugs).map { |slug| slug.to_s.strip }.reject(&:blank?).uniq
  end

  def inherit_account
    self.account_id ||= agent&.account_id
  end

  def normalize_slug
    self.slug = name.to_s.parameterize(separator: '_') if slug.blank? && name.present?
    self.slug = slug.to_s.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_')
                    .delete_prefix('_').delete_suffix('_')[0, MAX_SLUG_LENGTH]
  end

  def ensure_within_limit
    Autonomia::Agents::Agent.lock.find(autonomia_agent_id)
    return if agent.specialists.count < MAX_PER_AGENT

    errors.add(:base, "Limite de #{MAX_PER_AGENT} especialistas por agente atingido")
    throw(:abort)
  end
end
