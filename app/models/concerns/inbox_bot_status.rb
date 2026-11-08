module InboxBotStatus
  extend ActiveSupport::Concern

  included do
    # Sem índice único por inbox_id (#2298): com uma linha inativa e outra ativa na caixa, fica a ativa (active = 0), como
    # o SQL da Lista ("qualquer ativa"); o id desempata. A ordem vale também para o agent_bot (through) e para o preload.
    # eager_load/references ignora a ordem e pode trazer a inativa: para ler o robô de várias caixas, use preload.
    has_one :agent_bot_inbox, -> { order(:status, :id) }, dependent: :destroy_async, inverse_of: :inbox
    has_one :agent_bot, through: :agent_bot_inbox
  end

  def active_bot?
    external_bot_active?
  end

  def external_bot_active?
    agent_bot_inbox&.active? || dialogflow_active?
  end

  private

  def dialogflow_active?
    hooks.exists?(app_id: %w[dialogflow], status: 'enabled')
  end
end
