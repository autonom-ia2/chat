# Excluir de vez (#2096): um card com tudo que pendura nele, e a conferência de que nenhuma tabela ficou apontando para
# ele. A conferência lê o próprio banco (toda coluna card_id/crm_card_id), então pega também tabela nova que alguém
# criar depois sem chave estrangeira.
module CrmExclusaoHelpers
  COLUNAS_DE_CARD = %w[card_id crm_card_id].freeze

  # rubocop:disable Metrics/AbcSize
  def create_card_cheio(account:, user:, pipeline:, contact:, conversation:)
    stage = pipeline.stages.order(:position).first
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido completo',
                                     conversation_id: conversation.id, status: :archived, value_cents: 150_000)
    Crm::CardConversation.create!(account: account, card: card, conversation: conversation)
    Crm::ActivityLogger.new(card: card, actor: user, event_type: 'note', payload: { 'text' => 'anotação' }).perform
    Crm::FollowUp.create!(account: account, card: card, title: 'Retorno', due_at: 1.day.from_now, status: :pending)
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: stage, confidence: 0.8, reasoning: 'x', model_used: 'm')
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Boas-vindas', trigger_event: :on_enter)
    Crm::StageAutomationExecution.create!(account: account, card: card, stage_automation: automacao, trigger_token: SecureRandom.hex(4))
    Crm::Memoria::Gravador.gravar!(account_id: account.id, contact_id: contact.id, escopo: 'card', card_id: card.id, tipo: 'fato',
                                   chave: 'placa', valor: 'ABC1D23', fonte: 'pessoa_corrigiu', gerado_por: 'spec')
    Crm::Memoria::Fechamento.gravar!(card, 'ganho', Time.current)
    Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'suggest', action: 'create', state: 'suggested',
                                 pipeline: pipeline, card: card, title: 'Assunto', touched_card_ids: [card.id])
    Crm::Passagem.create!(account: account, conversation: conversation, card: card, para_type: 'User', para_id: user.id,
                          motivo: 'passar_para', em: Time.current)
    create_registros_sem_chave(account: account, card: card)
    card
  end
  # rubocop:enable Metrics/AbcSize

  # Tabelas que guardam o card sem chave estrangeira.
  def create_registros_sem_chave(account:, card:)
    create(:crm_ai_usage_event, account: account, pipeline_id: card.pipeline_id, card_id: card.id, cost_estimate: 0.5)
    create(:crm_google_conversion_event, account: account, card_id: card.id)
    Crm::MetaConversionEvent.create!(account: account, card: card, event_id: "crm-#{card.id}-won-1", event_type: 'won', status: :accepted)
  end

  # Reunião interna (sem calendário) com convidado e aviso: o convidado não tem cascata no banco.
  def create_reuniao(account:, card:, user:, contact:, starts_at:)
    meeting = account.crm_meetings.create!(card: card, created_by: user, title: 'Conversa', provider: :internal,
                                           online_meeting_type: :whatsapp_video, status: :scheduled, timezone: 'America/Sao_Paulo',
                                           starts_at: starts_at, ends_at: starts_at + 30.minutes)
    meeting.meeting_guests.create!(account: account, phone_number: contact.phone_number, contact: contact, name: contact.name,
                                   guest_type: :contact_guest)
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', due_at: 1.minute.ago)
    meeting
  end

  # Toda linha de qualquer tabela que ainda aponte para o card, mais os cards tocados e a memória do cliente.
  def onde_o_card_ainda_aparece(card_id)
    conexao = ActiveRecord::Base.connection
    tabelas = conexao.tables.flat_map do |tabela|
      conexao.columns(tabela).filter_map do |coluna|
        next unless COLUNAS_DE_CARD.include?(coluna.name)

        sql = "SELECT COUNT(*) FROM #{conexao.quote_table_name(tabela)} WHERE #{conexao.quote_column_name(coluna.name)} = #{Integer(card_id)}"
        "#{tabela}.#{coluna.name}" if conexao.select_value(sql).to_i.positive?
      end
    end
    tabelas << 'crm_subject_decisions.touched_card_ids' if Crm::SubjectDecision.exists?(['? = ANY(touched_card_ids)', card_id])
    tabelas << 'crm_memoria_fatos.item_ref' if Crm::MemoriaFato.exists?(item_ref: "card:#{card_id}")
    tabelas
  end
end

RSpec.configure do |config|
  config.include CrmExclusaoHelpers
end
