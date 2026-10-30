class Api::V1::Accounts::Crm::CardsController < Api::V1::Accounts::Crm::BaseController
  rescue_from ::Crm::Access::CardGuard::OwnerWithoutFunnel, with: :render_owner_without_funnel

  include Crm::FilterParameters

  before_action :validate_crm_filter_parameters, only: %i[index export]

  include Crm::IdempotentRequests
  include Crm::OpportunityRegistration
  include DeferInteractiveAi

  before_action :fetch_card, only: [
    :show, :update, :destroy, :restore, :move, :close, :link_conversation, :unlink_conversation, :link_contact, :unlink_contact,
    :current_ai_suggestion, :evaluate_ai, :summarize, :reset_auto_followup
  ]
  before_action :ensure_crm_ai_enabled, only: [:current_ai_suggestion, :evaluate_ai, :summarize, :reset_auto_followup]

  RESULTS_PER_PAGE = 25
  MAX_RESULTS_PER_PAGE = 100
  XLSX_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

  def index
    authorize ::Crm::Card
    # Ordering is owned by FilterQuery#apply_sort (whitelisted sort/direction,
    # defaulting to updated_at desc — byte-identical to the historical default).
    @action_list = ::Crm::Cards::OrganizarPor.lista_nova?(params)
    cards = filtered_cards
    # Lista nova (#2283): o grupo e o retorno de cada card vêm na linha; a contagem abaixo é de outra consulta, sem o select.
    cards = cards.select('crm_cards.*', ::Crm::Cards::ActionGroups::SELECT) if @action_list
    @cards = cards.page(params[:page] || 1).per(per_page)
    @card_companies = Crm::Cards::CompanyResolver.for_cards(@cards.to_a)
    @cards_count = filtered_cards.count
  end

  # Planilha da Lista (#722): mesmo filtro, busca, ordem e visibilidade da Lista, sem página.
  def export
    authorize ::Crm::Card, :export?
    export = ::Crm::Cards::XlsxExport.new(
      cards: filtered_cards, account: Current.account, user: Current.user, account_user: Current.account_user,
      pipeline: policy_scope(::Crm::Pipeline).find_by(id: params[:pipeline_id])
    )
    send_data export.generate, filename: export.filename, type: XLSX_CONTENT_TYPE, disposition: :attachment
  end

  def show; end

  # Quem não pode ser dono (#1149): por card (lista e ação em lote) ou por funil e caixa (card novo).
  def owner_options
    authorize ::Crm::Card, :index?
    options = ::Crm::Access::OwnerOptions.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    cards = policy_scope(::Crm::Card).where(id: Array(params[:card_ids]).first(::Crm::Access::OwnerOptions::MAX_CARDS))
    render json: { payload: { cards: options.for_cards(cards), blocked: options.blocked_for_new_card(params[:inbox_id], params[:pipeline_id]) } }
  end

  def by_conversation
    # Chatwoot's frontend identifies conversations by display_id (per-account).
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_crm_conversation!(conversation)
    # Só cards que a pessoa pode ver: o selo traz título, funil e etapa.
    cards = ::Crm::Cards::ConversationCardFinder.new(account: Current.account).all(conversation)
    card = cards.where(id: policy_scope(::Crm::Card).select(:id)).includes(:stage, :pipeline).first
    render json: { payload: stage_badge_payload(card) }
  end

  # Bulk stage lookup for the conversation list (virtual stage chips). Returns
  # { conversation_id => stage_badge } only for conversations the requester can
  # see that have an OPEN card. Capped at 100 ids per call. One badge per
  # conversation: the current subject, plus how many open subjects it has.
  def card_stages
    # Frontend sends display_ids (Chatwoot's per-account conversation identifier);
    # respond keyed by the SAME display_id so the client can match.
    display_ids = Array(params[:conversation_ids]).filter_map { |id| id.to_s[/\d+/]&.to_i }.uniq.first(100)
    return render(json: { payload: {} }) if display_ids.blank?

    conversations = Current.account.conversations.where(display_id: display_ids).to_a
    # Acesso por funil (#1148, parte C): a regra do funil para a página inteira numa consulta só.
    crm_visibility.preload(conversations)
    conversations = conversations.select { |conversation| crm_visibility.visible?(conversation) }
    return render(json: { payload: {} }) if conversations.blank?

    render json: { payload: conversation_badges(conversations) }
  end

  def create
    authorize ::Crm::Card
    permitted_params = create_params.to_h.with_indifferent_access
    external_id = permitted_params[:external_id].presence
    @registration = registration_for_creation
    persist_card_creation(permitted_params, external_id)
  rescue ::Crm::Cards::RegistrationInput::Invalid => e
    render_registration_error(e)
  rescue ActiveRecord::RecordInvalid => e
    raise unless @registration

    render_registration_record_error(e)
  rescue ActiveRecord::RecordNotUnique
    return render_registration_error(@registration.conflict) if @registration
    raise unless external_id

    # The failed transaction is rolled back before resolving an external upsert race.
    ActiveRecord::Base.transaction do
      with_idempotency { upsert_existing_card!(Current.account.crm_cards.find_by!(external_id: external_id), permitted_params) }
    end
  end

  def from_conversation
    authorize ::Crm::Card, :from_conversation?
    conversation = conversation_for_from_conversation!
    authorize_crm_conversation!(conversation)
    result = from_conversation_handler(conversation).perform { |card| authorize card, :show? }

    @card = result.card
    broadcast_card(::Events::Types::CRM_CARD_CREATED) if result.created
    render :show, status: result.created ? :created : :ok
  end

  def update
    attributes = update_params.to_h.with_indifferent_access.except(*hidden_value_attributes)
    strip_ai_metadata!(attributes)
    promessa = payment_promise_from(attributes)
    return render_unprocessable('crm.invalid_payment_promise') if promessa == PROMESSA_INVALIDA

    ensure_new_owner_allowed!(attributes[:owner_id]) if attributes.key?(:owner_id)
    if attributes.present? || promessa != SEM_PROMESSA
      mark_value_source_human!(attributes) if attributes.key?(:value_cents)
      mark_score_source_manual!(attributes) if score_changed_by_hand?(attributes)
      apply_update!(attributes, promessa: promessa)
      broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    end
    render :show
  end

  def destroy
    broadcast_card(::Events::Types::CRM_CARD_ARCHIVED) if ::Crm::Cards::Archiver.new(card: @card, actor: Current.user).perform
    render :show
  end

  def move
    with_idempotency do
      target_stage = Current.account.crm_pipeline_stages.find(params[:stage_id])
      ensure_move_allowed!(@card, target_stage.pipeline_id)
      @card = ::Crm::Cards::Mover.new(card: @card, actor: Current.user, target_stage: target_stage).perform
      broadcast_card(::Events::Types::CRM_CARD_MOVED)
      render :show
    end
  end

  # Card arquivado (#2095, com a flag crm_arquivados): reabrir por aqui é restaurar, com as regras do restaurar
  # (permissão de arquivar, funil arquivado, cliente que já voltou). Ganhar ou perder um card arquivado é recusado:
  # restaure antes. Sem a flag, como antes.
  def close
    with_idempotency do
      next close_archived if ::Crm::Cards::Restorer.reabrir_e_restaurar?(@card)

      @card = ::Crm::Cards::Closer.new(
        card: @card,
        actor: Current.user,
        result: params[:result],
        value_cents: params[:value_cents],
        currency: params[:currency],
        lost_reason: params[:lost_reason]
      ).perform
      broadcast_card(::Events::Types::CRM_CARD_UPDATED)
      render :show
    rescue ::Crm::Cards::Closer::InvalidResult
      render json: { error: 'invalid_result' }, status: :unprocessable_entity
    end
  end

  # Restaurar o arquivado (#2095): volta para a etapa onde estava (Crm::Cards::Restorer). Quem pode arquivar pode
  # restaurar (Crm::CardPolicy#restore?). Cliente que já voltou (outro card aberto do contato no mesmo funil) dá 409 com
  # esse card, se a pessoa o enxerga; `force=true` restaura mesmo assim.
  def restore
    force = ActiveModel::Type::Boolean.new.cast(params[:force]) || false
    result = ::Crm::Cards::Restorer.new(card: @card, actor: Current.user, force: force).perform
    return render_restore_refusal(result) unless result.restored?

    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  def link_conversation
    conversation = Current.account.conversations.find(params[:conversation_id])
    authorize_crm_conversation!(conversation)
    # Acesso por funil (#1148, decisão b): vincular põe a conversa no funil do card, então a pessoa precisa ter esse
    # funil também na caixa da conversa.
    raise Pundit::NotAuthorizedError unless card_guard.create_allowed?(@card.pipeline_id, conversation: conversation, inbox_id: @card.inbox_id)

    @card = ::Crm::Cards::ConversationLinker.new(
      card: @card,
      conversation: conversation,
      actor: Current.user,
      primary: ActiveModel::Type::Boolean.new.cast(params[:primary])
    ).link
    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  def unlink_conversation
    conversation = Current.account.conversations.find(params[:conversation_id])
    authorize_crm_conversation!(conversation)
    @card = ::Crm::Cards::ConversationLinker.new(card: @card, conversation: conversation, actor: Current.user).unlink
    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  def link_contact
    contact = attachable_contact!(params[:contact_id])
    @card = ::Crm::Cards::ContactLinker.new(card: @card, contact: contact, actor: Current.user).link
    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  def unlink_contact
    @card = ::Crm::Cards::ContactLinker.new(card: @card, contact: @card.contact, actor: Current.user).unlink
    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  def current_ai_suggestion
    @ai_suggestion = @card.account.crm_ai_stage_suggestions.current_pending.find_by(card: @card)
    render json: { payload: ai_suggestion_payload(@ai_suggestion) }
  end

  def evaluate_ai
    defer_interactive_ai('card_evaluate', { card_id: @card.id })
  end

  def summarize
    # The summary is derived from the conversation's messages, so gate on the
    # same conversation visibility used elsewhere to avoid leaking content to
    # agents who cannot see the underlying conversation.
    authorize_crm_conversation!(@card.primary_conversation) if @card.primary_conversation.present?
    defer_interactive_ai('card_summary', { card_id: @card.id })
  end

  # Re-arms a fresh AI auto-follow-up cadence on a card whose previous cycle was
  # spent (reached max_touches, was stopped, or skipped). Cancels any still-active
  # ai_followup touches, clears the cadence state to an un-armed shape so the next
  # planner sweep starts a new cycle, then broadcasts the updated card.
  # O reset é o dono da recusa 'follow_up_reply' do contato (chat#1325). Tudo vai numa transação só, travando na ordem
  # follow-up -> card -> contato: primeiro os toques ai_followup ativos do card (por id), depois o card, cuja marca é
  # relida com ele travado, e por último o contato, na liberação. É a ordem do caminho principal do DueProcessor/
  # AutoFollowupRunner (follow-up -> card) e combina com o OptOutDecision (card -> contato). O caminho de parada do
  # runner (stop_cadence/stop_closure/skip -> cancel_pending_siblings) faz card -> toques irmãos; o cruzamento com ele
  # pode dar deadlock, que o banco resolve abortando um dos lados, sem corromper dado. Já existia no runner (#1342).
  # Toque criado pelo planner depois da primeira leitura não é cancelado aqui (travá-lo depois do card inverteria a
  # ordem), e o runner não lê state['active'], então ele pode sair. Janela estreita, já existente, registrada no #1342.
  def reset_auto_followup
    ActiveRecord::Base.transaction do
      ai_follow_ups = @card.follow_ups.active.where("crm_follow_ups.metadata->>'source' = 'ai_followup'").order(:id).lock.to_a
      @card.lock!
      ai_follow_ups.each { |follow_up| follow_up.update!(status: :canceled) }
      @contact_opt_out = reset_auto_followup_state!
    end

    ::Crm::ActivityLogger.new(
      card: @card, actor: Current.user, event_type: 'ai_followup_reset',
      conversation: @card.primary_conversation, payload: {}
    ).perform
    broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    render :show
  end

  private

  # Business fields an external upsert may set on an existing card. Excludes
  # status (goes through #close) and metadata (server-owned 'ai' block).
  UPSERT_ATTRIBUTES = %i[
    title description value_cents currency lost_reason source priority score
    expected_close_at pipeline_id stage_id owner_id team_id contact_id
  ].freeze

  # O card devolve o contato vinculado (#1849): só vincula quem vê esse contato.
  def attachable_contact!(contact_id)
    Current.account.contacts.find(contact_id).tap { |contact| authorize contact, :attach? }
  end

  def upsert_existing_card!(card, permitted_params)
    @card = card
    authorize @card, :update?
    attributes = permitted_params.slice(*(UPSERT_ATTRIBUTES.map(&:to_s) - hidden_value_attributes)).compact
    attributes['contact_id'] = attachable_contact!(attributes['contact_id']).id if attributes['contact_id'].present?
    ensure_move_allowed!(@card, upsert_pipeline_id(attributes)) if attributes.key?('pipeline_id') || attributes.key?('stage_id')
    ensure_new_owner_allowed!(attributes['owner_id'], pipeline_id: upsert_pipeline_id(attributes) || @card.pipeline_id) if attributes.key?('owner_id')
    # Campos do card (#1146): o upsert junta com o que já está salvo, como o PATCH.
    if permitted_params[:custom_attributes].present?
      attributes['custom_attributes'] = @card.custom_attributes.to_h.merge(permitted_params[:custom_attributes].to_h).compact
    end
    if attributes.present?
      @card.update!(attributes)
      ::Crm::ActivityLogger.new(card: @card, actor: Current.user, event_type: 'update', payload: attributes).perform
      broadcast_card(::Events::Types::CRM_CARD_UPDATED)
    end
    render :show, status: :ok
  end

  # Valor de venda (#2075): quem não vê o valor deste card não o muda. A gaveta manda value_cents em toda edição; com o
  # valor escondido (nil), gravaria 0 por cima e travaria a IA. Ganhar (#close) segue aceitando o valor digitado.
  def hidden_value_attributes
    ::Crm::ValorDeVenda.ve_o_card?(Current.account_user, @card) ? [] : %w[value_cents currency]
  end

  # The 'ai' metadata block is server-owned (value_source lock, summary, eval
  # timestamps). Clients must never write it — strip it from incoming metadata
  # while preserving the existing server-side ai block.
  def strip_ai_metadata!(attributes)
    return unless attributes.key?(:metadata) && attributes[:metadata].is_a?(Hash)

    incoming = attributes[:metadata].except('ai')
    server_ai = (@card.metadata || {})['ai']
    incoming['ai'] = server_ai if server_ai.present?
    attributes[:metadata] = incoming
  end

  # A manual value edit locks the field: the AI auto-fill must not undo a human
  # correction on a later evaluation (Crm::Ai::Evaluator#apply_ai_value!).
  def mark_value_source_human!(attributes)
    metadata = (attributes[:metadata].presence || @card.metadata || {}).deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge('value_source' => 'human')
    attributes[:metadata] = metadata
  end

  # O drawer envia `score` em TODA edição, inclusive quando o usuário só mexeu no título. Marcar
  # manual pela presença da chave congelava a nota da IA sem ninguém ter tocado nela. Só conta como
  # intervenção humana quando o valor realmente muda.
  def score_changed_by_hand?(attributes)
    return false unless attributes.key?(:score)

    attributes[:score].to_i != @card.score.to_i
  end

  # Score editado na mão trava a IA neste estágio: ela volta a assumir quando o card se mover, senão
  # a nota manual envelhece e vira mentira.
  def mark_score_source_manual!(attributes)
    metadata = (attributes[:metadata].presence || @card.metadata || {}).deep_dup
    ai = metadata['ai'] || {}
    ai['score'] = (ai['score'] || {}).merge(
      'value' => attributes[:score].to_i,
      'source' => 'manual',
      'stage_id' => @card.stage_id,
      'calculated_at' => Time.current.iso8601
    )
    metadata['ai'] = ai
    attributes[:metadata] = metadata
  end

  # Um selo por conversa (o assunto atual) e quantos assuntos abertos ela tem, chaveados pelo display_id.
  def conversation_badges(conversations)
    display_by_global = conversations.index_by(&:id).transform_values(&:display_id)
    multiple = multiple_pipelines?
    subjects_count = Hash.new(0)
    # Principal ou vinculada (#1197): mesma regra do ConversationCardFinder, numa consulta para a lista toda.
    badges = ::Crm::Cards::ConversationCardFinder.new(account: Current.account).all_for(conversations.map(&:id))
                                                 .where(status: :open)
                                                 .where(id: policy_scope(::Crm::Card).select(:id))
                                                 .includes(:stage, :pipeline)
                                                 .each_with_object({}) do |card, acc|
      display_id = display_by_global[card.listed_conversation_id]
      next if card.stage.blank? || display_id.blank?

      subjects_count[display_id] += 1
      acc[display_id] ||= stage_badge_payload(card).merge(multiple_pipelines: multiple)
    end
    badges.each { |display_id, badge| badge[:subjects_count] = subjects_count[display_id] }
  end

  def stage_badge_payload(card)
    return if card.blank? || card.stage.blank?

    {
      card_id: card.id,
      title: card.title,
      pipeline_name: card.pipeline&.name,
      stage_name: card.stage.name,
      stage_color: card.stage.color,
      multiple_pipelines: multiple_pipelines?
    }
  end

  # Mais de um funil que a pessoa enxerga (acesso por funil, #1148 PR D): o selo mostra o nome do funil.
  def multiple_pipelines?
    @multiple_pipelines = policy_scope(::Crm::Pipeline).count > 1 unless defined?(@multiple_pipelines)
    @multiple_pipelines
  end

  def ai_suggestion_payload(suggestion)
    return if suggestion.blank? || suggestion.fechar_fora_da_tela?(@card)

    {
      id: suggestion.id,
      from_stage_id: suggestion.from_stage_id,
      to_stage_id: suggestion.to_stage_id,
      to_stage_name: suggestion.to_stage&.name,
      confidence: suggestion.confidence.to_f,
      reasoning: suggestion.reasoning,
      status: suggestion.status,
      created_at: suggestion.created_at
    }.merge(suggestion.fechar ? { fechar: suggestion.fechar } : {})
  end

  def fetch_card
    @card = policy_scope(::Crm::Card).includes(
      { contact: Crm::Cards::CompanyResolver.contact_preload },
      :owner, :inbox, :stage, :pipeline, :primary_conversation
    ).find(params[:id])
    authorize @card, card_policy_query
  end

  # Reabrir o card arquivado pelo /close é restaurar (#2095): a regra é a do restaurar, não a do fechar.
  def card_policy_query
    return :restore? if action_name == 'close' && ::Crm::Cards::Restorer.reabrir_e_restaurar?(@card)

    "#{action_name}?".to_sym
  end

  def close_archived
    return render_unprocessable(::Crm::Cards::Restorer::CLOSE_ARCHIVED) unless ::Crm::Cards::Closer.reopen?(params[:result])

    restore
  end

  def conversation_for_from_conversation!
    return Current.account.conversations.find_by!(display_id: params[:conversation_display_id]) if params[:conversation_display_id].present?

    Current.account.conversations.find(params[:conversation_id])
  end

  def persist_card_creation(permitted_params, external_id)
    # Registration, opportunity, idempotency key and captured response commit together.
    ActiveRecord::Base.transaction do
      with_idempotency do
        existing = external_id && Current.account.crm_cards.find_by(external_id: external_id)
        next upsert_existing_card!(existing, permitted_params) if existing

        @card, created = create_authorized_card(permitted_params)
        authorize @card, :show?
        broadcast_card(::Events::Types::CRM_CARD_CREATED) if created
        render :show, status: created ? :created : :ok
      end
    end
  end

  # Devolve [card, criado?]. Com conversation_id, segue o contrato de from_conversation (#1197): a conversa com card
  # aberto devolve o assunto atual; card novo nela só com new_subject.
  def create_authorized_card(permitted_params)
    conversation = conversation_from_params(permitted_params)
    resolved_params = resolved_create_params(permitted_params, conversation: conversation)
    create_authorizer.authorize!(resolved_params, conversation: conversation)
    ensure_create_allowed!(resolved_params.to_h.with_indifferent_access, conversation)
    if @registration
      card = @registration.perform do |contact|
        ::Crm::Cards::Creator.new(account: Current.account, user: Current.user, params: resolved_params.merge(contact_id: contact.id),
                                  etapa_escolhida: permitted_params[:stage_id].present?).perform
      end
      return [card, true]
    end

    current = current_open_card(conversation, resolved_params)
    return [current, false] if current

    [::Crm::Cards::Creator.new(account: Current.account, user: Current.user, params: resolved_params, conversation: conversation,
                               etapa_escolhida: permitted_params[:stage_id].present?).perform, true]
  end

  # O card aberto da conversa no funil pedido, que o agente enxerga. Trava a conversa (como from_conversation) para duas
  # chamadas juntas não criarem dois cards. Com external_id a integração cuida do próprio card: cria e, nas próximas
  # chamadas, atualiza pelo external_id. Funil diferente é outro assunto: card novo. Sem funil no pedido, o assunto atual.
  def current_open_card(conversation, resolved_params)
    return if conversation.blank? || resolved_params[:external_id].present?
    return if ActiveModel::Type::Boolean.new.cast(params[:new_subject])

    conversation.lock!
    cards = ::Crm::Cards::ConversationCardFinder.new(account: Current.account).all(conversation)
                                                .where(id: policy_scope(::Crm::Card).select(:id), status: :open)
    cards = cards.where(pipeline_id: resolved_params[:pipeline_id]) if resolved_params[:pipeline_id].present?
    cards.first
  end

  # Zera o estado do follow-up e, se este card estava parado a pedido do cliente, libera a recusa 'follow_up_reply' do
  # contato que a marca prova (o gravado no "sim", mesmo que o card tenha mudado de contato depois). Só ela, nunca a de
  # outra origem, e só quando nenhum outro card continua marcado para esse contato (Crm::FollowUps::CardOptOut,
  # release_opt_out!). Sem isso, o card re-armado ficaria parado no runner (contact_opted_out?). Chamado com o card travado.
  # Devolve o que aconteceu com a recusa do contato (release_follow_up_reply), para a resposta e o aviso do drawer.
  def reset_auto_followup_state!
    marked_contact = ::Crm::FollowUps::CardOptOut.marked_contact(@card) if ::Crm::FollowUps::CardOptOut.card_opted_out?(@card)
    @card.update!(metadata: reset_auto_followup_metadata)
    release_follow_up_reply(marked_contact)
  end

  # A recusa do contato vale para a conta inteira: tirá-la exige a mesma permissão do painel do contato
  # (ContactPolicy#update?, com o override do EE), além da de IA do CRM no funil que o reset já confere. Sem ela, o reset
  # limpa só o card e a recusa continua.
  def release_follow_up_reply(contact)
    return 'none' unless contact&.opt_out_source == 'follow_up_reply'
    return 'kept_no_permission' unless policy(contact).update?

    contact.release_opt_out!(source: 'follow_up_reply', by: Current.user)
    contact.reload
    return 'released' unless contact.opted_out?

    contact.opt_out_source == 'follow_up_reply' ? 'kept_other_cards' : 'kept_other_source'
  end

  def reset_auto_followup_metadata
    metadata = (@card.metadata || {}).deep_dup
    metadata['ai'] ||= {}
    metadata['ai']['auto_followup_state'] = {
      'active' => false, 'spent' => false, 'touch' => 0,
      'stopped_reason' => nil, 'opted_out' => false,
      'next_due_at' => nil, 'last_sent_at' => nil,
      'last_marketing_template_sent_at' => nil, 'touches' => []
    }
    metadata
  end

  def broadcast_card(event_name)
    return ::Crm::Cards::Broadcaster.broadcast(@card, event_name) unless action_name == 'create'

    card = @card
    ActiveRecord.after_all_transactions_commit { ::Crm::Cards::Broadcaster.broadcast(card, event_name) }
  end

  def replay_stored_response(record)
    return super unless action_name == 'create'

    # A replay must honor current visibility, not return a historical payload
    # containing conversations the requesting user can no longer read.
    @card = policy_scope(::Crm::Card).find(record.response_body.fetch('payload').fetch('id'))
    authorize @card, :show?
    response.headers[REPLAYED_HEADER] = 'true'
    render :show, status: record.response_status
  end

  def filtered_cards
    ::Crm::Cards::FilterQuery.new(scope: policy_scope(::Crm::Card), params: params, conversation_visibility: crm_visibility).perform
  end

  def per_page
    params.fetch(:per_page, RESULTS_PER_PAGE).to_i.clamp(1, MAX_RESULTS_PER_PAGE)
  end

  def from_conversation_handler(conversation)
    ::Crm::Cards::FromConversationHandler.new(
      account: Current.account,
      user: Current.user,
      conversation: conversation,
      requested_params: create_params.to_h.with_indifferent_access,
      new_subject: ActiveModel::Type::Boolean.new.cast(params[:new_subject]) || false
    )
  end

  def conversation_from_params(permitted_params)
    return if permitted_params[:conversation_id].blank?

    conversation = Current.account.conversations.find(permitted_params[:conversation_id])
    authorize_crm_conversation!(conversation)
    conversation
  end

  def create_authorizer
    ::Crm::Cards::CreateAuthorizer.new(account: Current.account, user: Current.user, account_user: Current.account_user)
  end

  def resolved_create_params(permitted_params, conversation:)
    ::Crm::Cards::CreateParamsResolver.new(
      account: Current.account,
      user_context: pundit_user,
      params: permitted_params,
      conversation: conversation
    ).perform
  end

  def create_params
    parameter_set(:card).permit(
      :pipeline_id, :stage_id, :contact_id, :conversation_id, :inbox_id, :owner_id, :team_id,
      :title, :description, :value_cents, :currency, :status, :lost_reason, :source,
      :priority, :score, :expected_close_at, :external_id, metadata: {}, custom_attributes: {}
    )
  end

  # `status` and `stage_id` are intentionally NOT permitted on update: won/lost
  # transitions must go through #close (audited + value lock) and stage changes
  # through #move, never a raw PATCH (which would bypass the activity log,
  # closed_at, and stage-move side effects). `owner_id` IS permitted so the list
  # view can inline-assign / reassign an owner (authorized via card :update? +
  # same-account validation on the model).
  # Acesso por funil (#1148, parte C): ver Crm::Access::CardGuard.
  def card_guard
    @card_guard ||= ::Crm::Access::CardGuard.new(user: Current.user, account: Current.account, account_user: Current.account_user)
  end

  def ensure_move_allowed!(card, pipeline_id)
    raise Pundit::NotAuthorizedError unless card_guard.move_allowed?(card, pipeline_id)
  end

  def ensure_create_allowed!(params, conversation)
    return if params[:pipeline_id].blank?
    return if card_guard.create_allowed?(params[:pipeline_id], conversation: conversation, inbox_id: params[:inbox_id])

    raise Pundit::NotAuthorizedError
  end

  # Dono do card (#1148, decisão a): só quem tem o funil do card; administrador escolhe qualquer pessoa.
  def ensure_new_owner_allowed!(owner_id, pipeline_id: @card.pipeline_id)
    return if owner_id.to_s == @card.owner_id.to_s

    card_guard.ensure_owner_allowed!(owner_id, inbox_id: @card.inbox_id, pipeline_id: pipeline_id)
  end

  def render_restore_refusal(result)
    return render_unprocessable(result.error) unless result.error == ::Crm::Cards::Restorer::CONFLICT

    open_card = result.open_card if policy(result.open_card).show?
    render json: { error: result.error, open_card: open_card && restore_conflict_payload(open_card) }, status: :conflict
  end

  def restore_conflict_payload(card)
    { id: card.id, title: card.title, pipeline_id: card.pipeline_id, stage_id: card.stage_id, stage_name: card.stage&.name }
  end

  def render_owner_without_funnel
    render_unprocessable(::Crm::Access::CardGuard::OwnerWithoutFunnel::CODE)
  end

  # Recusa por funil (#1148, decisão b; #1149): quem não tem o funil do card recebe um código que a tela traduz, em
  # vez da recusa genérica. Mesmo status de sempre.
  def render_unauthorized(message)
    return super if @card.nil? || card_guard.edit_allowed?(@card)

    render json: { error: ::Crm::Access::CardGuard::FUNNEL_REQUIRED }, status: :unauthorized
  end

  def upsert_pipeline_id(attributes)
    attributes['pipeline_id'].presence || Current.account.crm_pipeline_stages.find_by(id: attributes['stage_id'])&.pipeline_id
  end

  def update_params
    parameter_set(:card).permit(
      :title, :description, :value_cents, :currency, :lost_reason, :source,
      :priority, :score, :expected_close_at, :external_id, :owner_id, :payment_promise_at, metadata: {}, custom_attributes: {}
    )
  end

  # Cobrança (#1498): o dia em que o cliente prometeu pagar, só no formato "AAAA-MM-DD". Devolve SEM_PROMESSA quando
  # o pedido não traz o campo, nil para tirar e PROMESSA_INVALIDA para data que não existe.
  SEM_PROMESSA = :sem_promessa
  PROMESSA_INVALIDA = :promessa_invalida

  def payment_promise_from(attributes)
    return SEM_PROMESSA unless attributes.key?(:payment_promise_at)

    value = attributes.delete(:payment_promise_at).to_s.strip
    return if value.empty?

    date = Date.strptime(value, '%Y-%m-%d')
    date.strftime('%Y-%m-%d') == value ? value : PROMESSA_INVALIDA
  rescue Date::Error
    PROMESSA_INVALIDA
  end

  def with_payment_promise(metadata, promessa)
    metadata = (metadata || {}).deep_dup
    promessa ? metadata.merge('payment_promise_at' => promessa) : metadata.except('payment_promise_at')
  end

  # Campos do card (#1146): o PATCH manda só o que mudou. Junta com o que já está salvo (chave com null sai), com o card
  # travado, para duas edições ao mesmo tempo não apagarem o campo uma da outra.
  # Promessa de pagamento (#1498): só a chave dela muda no metadata, com o card travado, para não desfazer o que a IA
  # gravou no meio tempo; o histórico registra a data, não o metadata inteiro.
  def apply_update!(attributes, promessa: SEM_PROMESSA)
    ActiveRecord::Base.transaction do
      registro = attributes.dup
      if attributes.key?(:custom_attributes)
        @card.lock!
        attributes[:custom_attributes] = @card.custom_attributes.to_h.merge(attributes[:custom_attributes].to_h).compact
      end
      unless promessa == SEM_PROMESSA
        @card.lock!
        attributes[:metadata] = with_payment_promise(attributes[:metadata].presence || @card.metadata, promessa)
        registro[:payment_promise_at] = promessa
      end
      @card.update!(attributes)
      # O histórico (e o webhook) registram só os campos que o pedido mandou, não o hash inteiro já juntado.
      ::Crm::ActivityLogger.new(card: @card, actor: Current.user, event_type: 'update', payload: registro).perform
    end
  end
end
