# O que pendura no card anonimizado (Crm::Cards::Anonimizador): sai o texto e o que aponta para a pessoa; fica o que
# os números contam (as linhas, com ids, códigos, valores e datas). Roda sob as travas e dentro da transação de quem
# chama. Um UPDATE ou DELETE por tabela, para todos os cards do contato de uma vez.
# rubocop:disable Rails/SkipsModelValidations
class Crm::Cards::Anonimizador::Historico
  # Chaves do payload das atividades que ficam: ids, códigos, valores e datas, que a linha do tempo e os relatórios
  # leem (closed_with no crédito das metas, from/to_stage_id no tempo de resolução e nas conversões, by e
  # etapa_escolhida nas regras da IA). Saem título, descrição, motivo digitado, raciocínio e resumo da IA, link e
  # título de reunião, erro, campos personalizados, e os ids de contato, conversa e mensagem, que deixam de existir.
  CHAVES_DA_ATIVIDADE = %w[
    pipeline_id stage_id from_pipeline_id to_pipeline_id from_stage_id to_stage_id target_stage_id inbox_id owner_id
    team_id assignee_id from_user_id to_user_id etapa_escolhida value_cents currency priority score expected_close_at
    closed_with by motivo reason duplicado_de confidence sugestao_da_ia retorno_em suggestion_id follow_up_id series_id
    meeting_id canceled_meeting_id notice_id invite_id booking_profile_id status automation_mode due_at mode kind touch
    next_due_at send_mode delivery_transport attempts retry_at final trigger outcome starts_at provider location_type
    guests_count stage_automation_id step_id de_agent_bot_id para_agent_bot_id autonomia_agent_id transfer_id acao
    threshold_seconds renotify_count pickup_seconds business_pickup_seconds dedup_window_days
  ].freeze
  # Onde a mesma chave é texto livre da IA, e não código: o pedido de abrir assunto (motivo) e a passagem (reason).
  TEXTO_POR_EVENTO = {
    'ai_subject_opened' => %w[motivo reason],
    'ai_handoff' => %w[reason],
    'ai_handoff_invite' => %w[reason]
  }.freeze
  # Metadata que fica: a origem do retorno (relatório de retornos, Crm::Reports::FollowUps) e o motivo do cancelamento;
  # na reunião, o perfil e o link de agendamento (relatório de atenção) e a marca de teste (scope :real).
  METADATA_DO_RETORNO = %w[source canceled_reason].freeze
  METADATA_DA_REUNIAO = %w[booking_profile_id booking_link_id test].freeze
  MOTIVO = 'contact_removed'.freeze

  def initialize(account:, card_ids:, agora:)
    @account = account
    @card_ids = card_ids
    @agora = agora
  end

  def limpar!
    limpar_atividades!
    limpar_retornos!
    limpar_reunioes!
    limpar_ia!
    limpar_conversoes!
    soltar_vinculos!
  end

  private

  def dos_cards(modelo, coluna = :card_id)
    modelo.where(account_id: @account.id).where(coluna => @card_ids)
  end

  # A linha fica (histórico de etapas, fechamento e crédito); o payload fica só com as chaves de CHAVES_DA_ATIVIDADE, e
  # a atividade solta a conversa (que sai com o contato e levaria a linha junto, pela cascata).
  def limpar_atividades!
    dos_cards(Crm::Activity).select(:id, :event_type, :payload).find_each do |atividade|
      fora = TEXTO_POR_EVENTO.fetch(atividade.event_type, [])
      payload = atividade.payload.to_h.slice(*CHAVES_DA_ATIVIDADE).except(*fora)
      Crm::Activity.where(id: atividade.id).update_all(payload: payload, conversation_id: nil)
    end
  end

  # Retorno e série ficam (relatório de retornos), sem texto e sem o contato. O que ainda ia acontecer é cancelado: não
  # há mais a quem lembrar nem com quem falar.
  def limpar_retornos!
    titulo = rotulo
    dos_cards(Crm::FollowUp).active.update_all(status: Crm::FollowUp.statuses[:canceled], canceled_at: @agora)
    dos_cards(Crm::FollowUp).find_each do |retorno|
      retorno.update_columns(title: titulo, description: nil, contact_id: nil, conversation_id: nil, updated_at: @agora,
                             metadata: retorno.metadata.to_h.slice(*METADATA_DO_RETORNO).reverse_merge('canceled_reason' => MOTIVO))
    end
    dos_cards(Crm::FollowUpSeries).where.not(status: :ended).update_all(status: Crm::FollowUpSeries.statuses[:ended], ended_at: @agora)
    dos_cards(Crm::FollowUpSeries).update_all(title: titulo, description: nil, contact_id: nil, conversation_id: nil,
                                              metadata: {}, updated_at: @agora)
  end

  # A reunião fica (agenda e relatórios de reunião), sem título, descrição, anotação, link, resumo da IA e endereço. Sai
  # quem foi convidado de fora da equipe (o cliente e os e-mails digitados); o atendente convidado fica.
  def limpar_reunioes!
    reunioes = dos_cards(Crm::Meeting)
    Crm::MeetingGuest.where(account_id: @account.id, meeting_id: reunioes.select(:id), user_id: nil).delete_all
    reunioes.find_each do |reuniao|
      reuniao.update_columns(title: rotulo, description: nil, outcome_notes: nil, online_meeting_url: nil, conversation_id: nil,
                             metadata: reuniao.metadata.to_h.slice(*METADATA_DA_REUNIAO), updated_at: @agora)
    end
  end

  # Sugestão de etapa fica (o relatório IA x pessoa conta por status), sem o raciocínio. Memória do card e decisões do
  # decisor (texto e campos tirados da conversa) saem; execução de automação fica sem o detalhe.
  def limpar_ia!
    dos_cards(Crm::AiStageSuggestion).pending.update_all(status: Crm::AiStageSuggestion.statuses[:expired])
    dos_cards(Crm::AiStageSuggestion).update_all(reasoning: nil, metadata: {}, updated_at: @agora)
    dos_cards(Crm::StageAutomationExecution).update_all(error_message: nil, metadata: {}, updated_at: @agora)
    dos_cards(Crm::MemoriaFato).delete_all
    Crm::MemoriaFato.where(account_id: @account.id, item_ref: @card_ids.map { |id| "card:#{id}" }).delete_all
    dos_cards(Autonomia::DecisorDecisao, :crm_card_id).delete_all
  end

  # Conversões de anúncio: a linha fica (o painel conta o que foi enviado), sem o identificador do clique (gclid,
  # ctwa_clid), que é da pessoa. O que ainda não foi enviado não vai mais.
  def limpar_conversoes!
    google = dos_cards(Crm::GoogleConversionEvent)
    google.where(status: 'ready').update_all(status: 'skipped', skip_reason: MOTIVO, updated_at: @agora)
    google.update_all(gclid: nil, updated_at: @agora)
    meta = dos_cards(Crm::MetaConversionEvent)
    meta.pending.update_all(status: Crm::MetaConversionEvent.statuses[:skipped], updated_at: @agora)
    meta.update_all(ctwa_clid: nil, error_message: nil, updated_at: @agora)
  end

  # Vínculos com a conversa e com quem a pessoa era: saem. Passagens, decisões de assunto e convites são da conversa e
  # saem com ela, que sai com o contato. As execuções de ferramenta do agente (autonomia_agent_tool_runs) não têm chave
  # para a conversa e ficam: só perdem o card (ver o PR #2098). Os leads de prospecção aqui só perdem o card; os ligados
  # ao contato excluído saem depois, com ele (Autonomia::Prospecting::LeadsDoContatoExcluido, #2143).
  def soltar_vinculos!
    dos_cards(Crm::CardConversation).delete_all
    dos_cards(Crm::Passagem).update_all(card_id: nil, updated_at: @agora)
    dos_cards(Crm::SubjectDecision).update_all(card_id: nil, updated_at: @agora)
    tirar_dos_cards_tocados!
    dos_cards(Crm::BookingInvite).update_all(card_id: nil, updated_at: @agora)
    dos_cards(Autonomia::Agents::ToolRun).update_all(card_id: nil, updated_at: @agora)
    dos_cards(Autonomia::Prospecting::Lead, :crm_card_id).update_all(crm_card_id: nil, updated_at: @agora)
  end

  def tirar_dos_cards_tocados!
    Crm::SubjectDecision.where(account_id: @account.id).where('touched_card_ids && ARRAY[?]::bigint[]', @card_ids)
                        .update_all([
                                      'touched_card_ids = ARRAY(SELECT tocado FROM unnest(touched_card_ids) AS tocado ' \
                                      'WHERE tocado <> ALL(ARRAY[?]::bigint[])), updated_at = ?', @card_ids, @agora
                                    ])
  end

  def rotulo
    I18n.t('crm.cards.anonimizado.history_title', locale: @account.locale.presence || I18n.default_locale)
  end
end
# rubocop:enable Rails/SkipsModelValidations
