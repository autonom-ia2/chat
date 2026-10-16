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
#  delegate_agent_id  :bigint
#
# Indexes
#
#  idx_autonomia_agent_specialists_account_enabled          (account_id,enabled)
#  idx_autonomia_agent_specialists_agent_slug               (autonomia_agent_id,slug) UNIQUE
#  idx_autonomia_agent_specialists_delegate                 (delegate_agent_id) WHERE (delegate_agent_id IS NOT NULL)
#  idx_autonomia_agent_specialists_par_delegate             (autonomia_agent_id,delegate_agent_id) UNIQUE
#                                                           WHERE (delegate_agent_id IS NOT NULL)
#  index_autonomia_agent_specialists_on_autonomia_agent_id  (autonomia_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (delegate_agent_id => autonomia_agents.id) ON DELETE => cascade
#
# Subagente especializado de um agente Autonom.ia (#311).
#
# DELEGAÇÃO ENTRE AGENTES, NÃO PARA HUMANO. O caminho agente -> pessoa continua sendo
# `Crm::Ai::HandoffExecutor` (CRM/kanban/atribuição), acionado pela instrução — este model NÃO
# encosta nele e não usa `Captain::Tools::HandoffTool`.
#
# O especialista é exposto ao modelo como uma FUNÇÃO (`consultar_<slug>`). Quando o principal a
# chama, o Specialists::Runner roda um ciclo próprio — instrução própria, tools próprias — e
# devolve TEXTO. O principal não interpreta estrutura. Esse contrato em prosa
# é deliberado: é o que funciona nos fluxos de cotação em produção e evita que o principal precise
# entender o payload de um ramo inteiro. O especialista de cotação devolve os FATOS rotulados, em texto, e não
# frase para parafrasear (`Insurance::QuoteAgent::RetornoDoEspecialista`, item 9 da auditoria de voz de 26/09/2026).
#
# O AJUDANTE (tema 14, #1434): com `delegate_agent_id`, a linha é o VÍNCULO principal → ajudante, outro agente da
# conta. A instrução, a base e as ferramentas vêm do agente apontado, e não de texto embutido; `description` guarda o
# "quando chamar". O ajudante é um agente interno (não fala com cliente, não tem caixa) e não chama ajudante
# (profundidade 1). A Lia não entra: os degraus do ajudante vêm DEPOIS dos `Builder.*_mantida`, por onde ela sai.
# Quem grava o conjunto é `Autonomia::Agents::Ajudantes.definir!`; quem decide se entra no turno, `Ajudantes.disponivel?`.
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
  # O que o ajudante lê antes da instrução dele: quem o consulta e que a resposta nunca vai ao cliente.
  CONTEXTO_DO_AJUDANTE = 'Você é %<ajudante>s, um ajudante consultado pelo agente %<principal>s. Você nunca fala ' \
                         'com o cliente: responda a %<principal>s com os fatos que encontrou e diga o que ainda falta. ' \
                         'Não cumprimente nem se apresente.'.freeze

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                     inverse_of: :specialists
  belongs_to :delegate, class_name: 'Autonomia::Agents::Agent', foreign_key: :delegate_agent_id, optional: true,
                        inverse_of: :vinculos_de_ajudante

  before_validation :normalize_slug
  before_validation :inherit_account
  before_validation :normalize_tool_slugs
  before_validation :sem_instrucao_propria, if: :delegado?
  before_create :ensure_within_limit

  validates :name, presence: true
  validates :description, presence: true, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :instruction, presence: true, unless: :delegado?
  validates :instruction, length: { maximum: MAX_INSTRUCTION_LENGTH }
  validates :custom_instruction, length: { maximum: MAX_CUSTOM_INSTRUCTION_LENGTH }, allow_nil: true
  validates :slug, presence: true, uniqueness: { scope: :autonomia_agent_id },
                   length: { maximum: MAX_SLUG_LENGTH }, format: { with: SLUG_FORMAT }
  validates :delegate_agent_id, uniqueness: { scope: :autonomia_agent_id }, allow_nil: true
  validate :ajudante_valido, if: :delegado?

  scope :enabled, -> { where(enabled: true) }
  scope :de_ajudante, -> { where.not(delegate_agent_id: nil) }

  # Aponta para outro agente da conta: é o vínculo com um ajudante (tema 14).
  def delegado?
    delegate_agent_id.present?
  end

  def function_name
    "#{FUNCTION_PREFIX}#{slug}"
  end

  # Schema da função exposta ao modelo. Um parâmetro só, de propósito: quanto mais estrutura o
  # principal tiver que preencher, mais ele erra — quem conhece os campos do ramo é o especialista.
  def openai_schema
    {
      type: 'function',
      name: function_name,
      description: descricao_do_sistema,
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
    [instrucao_do_sistema, custom_instruction.presence].compact.join("\n\n")
  end

  # A mantida pela Autonom.ia — o arquivo do deploy — quando este é um especialista do agente de
  # cotação; a gravada, para os demais. Ver `QuoteAgent::Builder.instrucao_mantida`: é o que faz um
  # agente já criado receber o manual novo sem ser recriado (entrega 3, termo 5).
  def instrucao_do_sistema
    ::Autonomia::Insurance::QuoteAgent::Builder.instrucao_mantida(self) || (delegado? ? instrucao_do_ajudante : instruction)
  end

  # Idem para a descrição que o principal lê na função (`openai_schema`).
  def descricao_do_sistema
    ::Autonomia::Insurance::QuoteAgent::Builder.descricao_mantida(self) || (delegado? ? descricao_do_ajudante : description)
  end

  # Os slugs das ferramentas reservadas a este especialista: os do deploy quando ele é um especialista do
  # Agente de Cotação (`QuoteAgent::Builder.ferramentas_mantidas_do_especialista`, fatia 2 do #420), os
  # gravados em `tool_slugs` para os demais. `tools` e a reserva do principal (`Answerer`) leem daqui.
  # O vínculo com um ajudante não reserva nada: as ferramentas dele são as do agente apontado (`tools`), e as do
  # principal continuam com o principal — um ajudante com agenda não tira a agenda de quem o consulta.
  def ferramentas_do_sistema
    ::Autonomia::Insurance::QuoteAgent::Builder.ferramentas_mantidas_do_especialista(self) || (delegado? ? [] : tool_slugs)
  end

  # Ferramentas reservadas a este especialista, na ordem declarada. Slug que não existe (ou foi
  # desabilitado) é ignorado em silêncio: o especialista trabalha com o que sobrou em vez de
  # derrubar o turno inteiro por causa de uma configuração velha.
  # O ajudante usa todas as ferramentas DELE (sem especialistas: ajudante não chama ajudante).
  def tools
    return @tools ||= Autonomia::Agents::Tools::Bound.for_agent(delegate) if delegado?

    slugs = ferramentas_do_sistema
    return [] if slugs.blank?

    # Memoizado: o runner consulta esta lista uma vez por turno, mas `for_agent` faz consulta ao
    # banco e monta o catálogo de nativas — não há motivo para refazer isso a cada chamada.
    @tools ||= begin
      by_slug = Autonomia::Agents::Tools::Bound.for_agent(agent, especialista: self).index_by(&:slug)
      encontradas = slugs.filter_map { |slug| by_slug[slug.to_s] }
      avisar_descartadas(slugs, by_slug.keys, encontradas)
      encontradas
    end
  end

  private

  def instrucao_do_ajudante
    contexto = format(CONTEXTO_DO_AJUDANTE, ajudante: delegate.name, principal: agent.name)
    [contexto, delegate.instruction.to_s.strip.presence].compact.join("\n\n")
  end

  def descricao_do_ajudante
    "Consulta o ajudante #{delegate.name}. Só você lê a resposta; o cliente nunca fala com ele. Chame quando: #{description}"
  end

  # A coluna é NOT NULL, e o vínculo não tem instrução própria: quem manda é o agente apontado.
  def sem_instrucao_propria
    self.instruction = '' if instruction.nil?
  end

  def ajudante_valido
    motivo = motivo_de_recusa_do_ajudante
    errors.add(:delegate_agent_id, I18n.t("autonomia.agents.ajudante.#{motivo}")) if motivo
  end

  # Mesma conta; nenhum dos dois é a Lia (instrução mantida) nem agente de sistema; o principal é um agente
  # terminado e não nasceu como ajudante (revisão do PR2); e o ajudante serve (abaixo).
  def motivo_de_recusa_do_ajudante
    return 'outra_conta' unless mesma_conta?
    return 'ele_mesmo' if delegate.id == agent.id
    return 'tipo_proibido' if tipo_proibido?(agent) || tipo_proibido?(delegate)
    return 'principal_rascunho' if agent.draft?
    return 'principal_ajudante' if agent.ajudante_de_origem?

    motivo_do_ajudante
  end

  # O ajudante é interno e NASCEU como ajudante (a marca de origem: um Copiloto da equipe nunca vira ajudante); o
  # principal não é interno, por isso ajudante não chama ajudante (profundidade 1); e o ajudante não tem ajudante dele.
  def motivo_do_ajudante
    return 'ajudante_interno' unless delegate.actuation_internal?
    return 'sem_marca' unless delegate.ajudante_de_origem?

    'profundidade' if alem_da_profundidade_um?
  end

  def mesma_conta?
    delegate.present? && agent.present? && delegate.account_id == agent.account_id
  end

  def alem_da_profundidade_um?
    agent.actuation_internal? || self.class.de_ajudante.exists?(autonomia_agent_id: delegate.id)
  end

  def tipo_proibido?(agente)
    agente.agent_type == 'insurance_quote' || agente.config.to_h['system_key'].present?
  end

  # O descarte silencioso acima esconde o caso em que o especialista fica SEM FERRAMENTA NENHUMA e
  # ainda assim responde ao principal — que foi o defeito da Lia em 08/09/2026: ela pediu placa,
  # CEP e CPF e anunciou uma cotação que nunca chegou ao portal. Continua não derrubando o turno,
  # mas agora deixa rastro. Só slug e id: nada de credencial nem de prompt.
  def avisar_descartadas(slugs, disponiveis, encontradas)
    faltando = slugs.map(&:to_s) - encontradas.map(&:slug)
    return if faltando.empty?

    Rails.logger.warn(
      "[autonomia][specialist] tool_slug fora do catalogo specialist=#{id} " \
      "faltando=#{faltando.join(',')} disponiveis=#{disponiveis.join(',')}"
    )
  end

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
