# == Schema Information
#
# Table name: autonomia_agent_tool_runs
#
#  id                 :bigint           not null, primary key
#  arguments          :jsonb            not null
#  attempts           :integer          default(0), not null
#  delivered_count    :integer          default(0), not null
#  expected_chunks    :integer          default(0), not null
#  expires_at         :datetime
#  failure_code       :string
#  handle             :jsonb            not null
#  notify_customer    :boolean          default(FALSE), not null
#  sequence           :integer          default(0), not null
#  slug               :string           not null
#  status             :string           default("pending"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_inbox_id     :bigint
#  autonomia_agent_id :bigint           not null
#  conversation_id    :bigint           not null
#  execution_key      :string           not null
#  origin_message_id  :bigint
#
# Indexes
#
#  idx_autonomia_tool_runs_account_slug   (account_id,slug,created_at)
#  idx_autonomia_tool_runs_active         (conversation_id,slug) UNIQUE WHERE status IN ('pending','running')
#  idx_autonomia_tool_runs_conversation   (conversation_id,created_at)
#  idx_autonomia_tool_runs_execution_key  (execution_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Uma EXECUÇÃO de ferramenta assíncrona (#313).
#
# Existe porque uma cotação leva até ~90s e o turno do agente não pode esperar por ela. A linha é o
# que torna a espera segura: nela mora o progresso (em vez da memória de um worker que um deploy
# mata), a idempotência da publicação (retry do Sidekiq não duplica mensagem), o teto de tempo de
# parede, e o argumento que o modelo montou — que fica AQUI e não no payload do job, porque no Redis
# ele sobreviveria no dead set, visível em /monitoring/sidekiq, sem TTL controlado por nós.
#
# UMA execução viva por (conversa, ferramenta), garantido por índice único parcial. Chamada nova
# SUPERSEDE a anterior em vez de coexistir com ela: o cliente que corrige um dado no meio da conversa
# ("na verdade é 2019") não pode acabar com duas cotações concorrentes e dois preços conflitantes.
# É o mesmo last-writer-wins que o namespace já usa no debounce, no sync_token e no build_token.
class Autonomia::Agents::ToolRun < ApplicationRecord
  self.table_name = 'autonomia_agent_tool_runs'

  # `pending` é o estado em que a ferramenta foi ACEITA dentro do turno mas o turno ainda não
  # terminou. Só o Responder promove para `running` — se o turno morrer (falha de IA na segunda
  # chamada, sinal de silêncio), a execução é descartada e nunca chega a falar com o portal.
  ACTIVE_STATUSES = %w[pending running].freeze
  TERMINAL_STATUSES = %w[done failed superseded discarded blocked].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                     inverse_of: false
  # Opcionais na LEITURA: a conversa pode ter sido apagada enquanto a execução corria, e nesse caso
  # o job precisa parar limpo, não levantar. Quem cria a linha sempre tem as duas.
  belongs_to :conversation, optional: true
  belongs_to :agent_inbox, class_name: 'Autonomia::Agents::AgentInbox', optional: true

  validates :slug, presence: true
  validates :execution_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }

  # Abre uma execução para (conversa, ferramenta), substituindo a que estiver viva.
  #
  # `scope` = { conversation_id:, agent_inbox_id:, origin_message_id: }. A mensagem de origem entra
  # aqui, na criação, porque é a chave que separa um PEDIDO NOVO de um RETRY do mesmo turno.
  #
  # Duas escritas numa transação: supersede a anterior e insere a nova. O índice único parcial é
  # quem garante de verdade — duas chamadas concorrentes fazem a segunda estourar `RecordNotUnique`,
  # e aí devolvemos nil em vez de mentir para o modelo dizendo que aceitamos.
  def self.open!(agent:, slug:, arguments:, scope:)
    transaction do
      active.for_conversation(scope[:conversation_id]).where(slug: slug)
            .update_all(status: 'superseded', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      create!(account: agent.account, agent: agent, slug: slug, status: 'pending',
              conversation_id: scope[:conversation_id], agent_inbox_id: scope[:agent_inbox_id],
              origin_message_id: scope[:origin_message_id],
              execution_key: SecureRandom.uuid, arguments: arguments.to_h.deep_stringify_keys)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Este turno já abriu uma execução desta ferramenta? É o freio do RETRY: o `ReplyJob` pode
  # reexecutar o settle e refazer a chamada ao modelo, e sem esta guarda a segunda passada
  # superseder a primeira e abriria uma cotação nova no portal — sem duplicar mensagem, mas
  # duplicando o custo e o registro na seguradora.
  def self.opened_for_turn?(conversation_id, slug, origin_message_id)
    return false if origin_message_id.blank?

    # `pending` órfã NÃO conta: se o worker morreu entre o aceite e o despacho (um deploy basta —
    # o Sidekiq desta instalação tem `:timeout: 25`), a linha ficou parada e ninguém vai executá-la.
    # Contá-la faria o retry do turno recusar a ferramenta e a cotação nunca aconteceria.
    for_conversation(conversation_id).where.not(status: %w[pending discarded blocked])
                                     .exists?(slug: slug, origin_message_id: origin_message_id)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def running?
    status == 'running'
  end

  def expired?
    expires_at.present? && Time.current > expires_at
  end

  # Token que carimba a mensagem publicada, derivado do CONTEÚDO. É por ele que a publicação é
  # idempotente: um retry do Sidekiq, ou uma consulta que reemite a mesma entrega, encontra a
  # mensagem já postada e não posta de novo.
  #
  # Por conteúdo e não por posição: `sequence` identifica ONDE a mensagem entrou, não O QUE ela diz.
  # Uma nova consulta que devolva a mesma lista (o contrato de `Progress` não exige que as entregas
  # sejam incrementais) republicaria o mesmo texto num índice diferente.
  def delivery_token(text)
    "#{execution_key}:#{Digest::SHA256.hexdigest(text.to_s)[0, 16]}"
  end

  # pending -> running. Guardado pelo status para que um despacho repetido (retry do turno) não
  # reabra uma execução que já terminou. -> true quando ESTA chamada promoveu.
  def promote!(expected_chunks:, notify_customer:, expires_at:)
    guarded_update('pending', status: 'running', expected_chunks: expected_chunks.to_i,
                              notify_customer: notify_customer, expires_at: expires_at)
  end

  def finish!(status, failure_code: nil)
    guarded_update('running', status: status, failure_code: failure_code)
  end

  # Descarta uma execução que nunca chegou a rodar (o turno morreu antes de despachar).
  def discard!
    guarded_update('pending', status: 'discarded')
  end

  def record_attempt!(handle: nil)
    attrs = { attempts: attempts + 1 }
    attrs[:handle] = handle.to_h.deep_stringify_keys if handle.present?
    guarded_update('running', **attrs)
  end

  # Registra que uma ENTREGA DA FERRAMENTA foi aceita para publicação (publicada ou adiada). O aviso
  # de espera e a frase de falha NÃO passam por aqui — é o que permite saber, no fim, se o cliente
  # recebeu algum resultado de verdade.
  def record_delivery!
    self.class.where(id: id).update_all('delivered_count = delivered_count + 1, updated_at = NOW()') # rubocop:disable Rails/SkipsModelValidations
    reload
  end

  # Já morreu: supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da conta.
  # Publicar a partir de uma destas entregaria ao cliente o resultado de um pedido que ele corrigiu.
  def dead?
    %w[superseded discarded blocked].include?(status)
  end

  # Avança o contador de mensagens. Otimista no valor atual: se dois publicadores correrem, só um
  # avança e o outro relê — evita duas mensagens com o mesmo número de sequência.
  def advance_sequence!(from)
    updated = self.class.where(id: id, sequence: from)
                  .update_all(sequence: from + 1, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return false if updated.zero?

    self.sequence = from + 1
    true
  end

  private

  # Escrita guardada pelo status atual, sem callbacks nem validações — mesmo padrão de
  # `Autonomia::Agents::Source#guarded_update`. Recarrega o objeto quando a escrita valeu.
  def guarded_update(from_status, **attrs)
    updated = self.class.where(id: id, status: from_status)
                  .update_all(attrs.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    return false if updated.zero?

    reload
    true
  end
end
