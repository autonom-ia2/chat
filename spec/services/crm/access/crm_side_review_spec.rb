require 'rails_helper'

# Revisão da Orquestração na parte C (#1148): lembrete, reunião, sugestão de etapa da IA, sincronização em tempo real e
# listas do CRM seguem a mesma regra do funil. Cada caso confere o que a pessoa NÃO recebe ou não consegue; o fim do
# arquivo confere que, sem nenhuma linha de acesso, tudo segue como antes.
RSpec.describe 'Acesso por funil: revisão da parte C' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:livre_agent) { create_crm_agent(account: account, name: 'Sem restrição').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent, sinistro_agent, livre_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
  let(:card_sinistro) do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', contact: conversa.contact,
                              inbox: inbox, primary_conversation: conversa)
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  def restrict(user, pipeline)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def overdue_follow_up(card, assignee)
    account.crm_follow_ups.create!(card: card, title: 'Retornar', description: 'Detalhe do caso', due_at: 10.minutes.ago,
                                   timezone: 'UTC', automation_mode: :reminder_only, status: :overdue, assignee: assignee,
                                   created_by: admin)
  end

  def held_by(meeting, actor)
    service = Crm::Meetings::RecordOutcomeService.new(meeting: meeting, outcome: 'held', notes: nil, actor: actor)
    service.perform
    service.post_meeting
  end

  def suggestion_for(card, to_stage)
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: card.stage, to_stage: to_stage, confidence: 0.9, model_used: 'test')
  end

  def accept(suggestion, user)
    post "/api/v1/accounts/#{account.id}/crm/ai_suggestions/#{suggestion.id}/accept", headers: user.create_new_auth_token, as: :json
  end

  def with_ai_role(user)
    role = create(:custom_role, account: account, permissions: %w[crm_view crm_manage_ai conversation_manage])
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
  end

  # Consultas da regra do funil (o apelido crm_access_cards só aparece nelas).
  def funnel_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].include?('crm_access_cards') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  describe 'com acesso por funil' do
    before do
      restrict(vendas_agent, vendas.first)
      restrict(sinistro_agent, sinistro.first)
    end

    describe 'lembrete com responsável que não vê o card' do
      let(:follow_up) { overdue_follow_up(card_sinistro, vendas_agent) }

      it 'o aviso em tempo real não leva o título do card a quem não o vê' do
        allow(ActionCableBroadcastJob).to receive(:perform_later)

        Crm::FollowUps::Broadcaster.broadcast_due(follow_up)

        expect(ActionCableBroadcastJob).to have_received(:perform_later).with([sinistro_agent.pubsub_token], any_args)
        expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with([vendas_agent.pubsub_token], any_args)
      end

      it 'nem a notificação (push e e-mail)' do
        users = Crm::FollowUps::ReminderNotifier.new(follow_up).send(:recipient_users)

        expect(users).to include(sinistro_agent)
        expect(users).not_to include(vendas_agent)
      end

      it 'nem o aviso de falha do envio automático' do
        follow_up
        allow(ActionCableBroadcastJob).to receive(:perform_later)

        Crm::FollowUps::DueProcessor.new.send(:notify_auto_send_failed, follow_up)

        expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
      end
    end

    describe 'reunião: mover sozinho depois de "Aconteceu"' do
      let(:world) { build_booking_world(account: account) }
      let(:meeting) do
        create_internal_meeting(world: world, starts_at: 2.hours.ago, metadata: { 'booking_profile_id' => world.profile.id })
      end

      before do
        world.card.update!(inbox: inbox)
        Crm::InboxAgentAccess.find_by(account: account, user: vendas_agent).agent_pipelines
                             .create!(account: account, pipeline: world.pipeline)
      end

      it 'não leva o card para um funil que quem marcou não pode mover (e não oferece o botão)' do
        _pos_venda, pos_venda_stage = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
        world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: pos_venda_stage)

        expect(held_by(meeting, vendas_agent)).to be_nil
        expect(world.card.reload.pipeline_id).to eq(world.pipeline.id)
      end

      it 'dentro de um funil dela segue movendo' do
        proposta = create_crm_stage(account: account, pipeline: world.pipeline, name: 'Proposta')
        world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposta)

        expect(held_by(meeting, vendas_agent)).to include(mode: 'auto', moved: true)
        expect(world.card.reload.stage_id).to eq(proposta.id)
      end
    end

    describe 'aceitar a sugestão de etapa da IA', type: :request do
      before { with_ai_role(vendas_agent) }

      it 'vale a regra do /move: quem vê o card de outro funil (atende a conversa) não o move' do
        conversa.update!(assignee: vendas_agent)
        suggestion = suggestion_for(card_sinistro, create_crm_stage(account: account, pipeline: sinistro.first, name: 'Vistoria'))
        user_context = { user: vendas_agent, account: account, account_user: AccountUser.find_by(account: account, user: vendas_agent) }
        expect(Crm::AiStageSuggestionPolicy.new(user_context, suggestion).accept?).to be(true)

        accept(suggestion, vendas_agent)

        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
        expect(card_sinistro.reload.stage_id).to eq(sinistro.last.id)
        expect(suggestion.reload).to be_pending
      end

      it 'no funil dela, aceita e move' do
        card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'V', inbox: inbox,
                                         contact: create(:contact, account: account), owner: vendas_agent)
        proposta = create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta')

        accept(suggestion_for(card, proposta), vendas_agent)

        expect(response).to have_http_status(:ok)
        expect(card.reload.stage_id).to eq(proposta.id)
      end
    end

    describe 'sincronização em tempo real' do
      it 'vincular a conversa enfileira uma sincronização só' do
        card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'V', inbox: inbox, contact: conversa.contact)

        expect { Crm::Cards::ConversationLinker.new(card: card, conversation: conversa, actor: admin, primary: true).link }
          .to have_enqueued_job(Crm::Access::VisibilitySyncJob).exactly(:once)
      end

      it 'card antigo com a principal sem linha de vínculo: trocar a principal sincroniza também a que saiu' do
        card_sinistro
        Crm::CardConversation.where(card: card_sinistro, conversation: conversa).delete_all
        Crm::Access::CountInvalidation.sync_started!([conversa.id])
        nova = create_crm_conversation(account: account, inbox: inbox, contact: conversa.contact)

        expect { Crm::Cards::ConversationLinker.new(card: card_sinistro, conversation: nova, actor: admin, primary: true).link }
          .to have_enqueued_job(Crm::Access::VisibilitySyncJob).with([conversa.id])
      end

      it 'com uma sincronização na fila não enfileira outra; quando ela começa, a próxima mudança enfileira' do
        card_sinistro

        expect { card_sinistro.update!(pipeline: vendas.first, stage: vendas.last) }
          .not_to have_enqueued_job(Crm::Access::VisibilitySyncJob)

        Crm::Access::CountInvalidation.sync_started!([conversa.id])

        expect { card_sinistro.update!(pipeline: sinistro.first, stage: sinistro.last) }
          .to have_enqueued_job(Crm::Access::VisibilitySyncJob).with([conversa.id]).exactly(:once)
      end

      it 'só quem tem linha restritiva recebe: membro sem restrição e administrador ficam como estavam' do
        inbox.update!(enable_auto_assignment: false)
        admin
        card_sinistro
        allow(ActionCableBroadcastJob).to receive(:perform_later)

        Crm::Access::VisibilitySync.perform(conversa)

        expect(ActionCableBroadcastJob).to have_received(:perform_later)
          .with([sinistro_agent.pubsub_token], Events::Types::CONVERSATION_UPDATED, anything).once
        expect(ActionCableBroadcastJob).to have_received(:perform_later)
          .with([vendas_agent.pubsub_token], 'conversation.access_revoked', hash_including(id: conversa.id)).once
        expect(ActionCableBroadcastJob).to have_received(:perform_later).twice
      end
    end

    describe 'listas do CRM: a regra do funil numa consulta só' do
      def cards_with_conversations(count)
        Array.new(count) do |index|
          conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
          card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: "V#{index}", inbox: inbox,
                                           contact: conversation.contact, primary_conversation: conversation)
          extra = create_crm_conversation(account: account, inbox: inbox, contact: conversation.contact)
          Crm::CardConversation.create!(account: account, card: card, conversation: extra)
          card
        end
      end

      it 'depois do preload_cards, ver as conversas (principais e vinculadas) não consulta mais' do
        cards = cards_with_conversations(3)
        visibility = Crm::Conversations::Visibility.new(account: account, user: vendas_agent,
                                                        account_user: AccountUser.find_by(account: account, user: vendas_agent))
        visibility.preload_cards(cards)

        queries = funnel_queries do
          cards.each do |card|
            visibility.visible?(card.primary_conversation)
            card.linked_conversations.each { |conversation| visibility.visible?(conversation) }
          end
        end

        expect(queries).to eq(0)
      end

      it 'as etiquetas de etapa da lista de conversas não fazem uma consulta de funil por conversa', type: :request do
        url = "/api/v1/accounts/#{account.id}/crm/conversations/card_stages"
        two = funnel_queries do
          get url, params: { conversation_ids: cards_with_conversations(2).map { |card| card.primary_conversation.display_id } },
                   headers: vendas_agent.create_new_auth_token
        end
        expect(response.parsed_body['payload'].size).to eq(2)

        five = funnel_queries do
          get url, params: { conversation_ids: cards_with_conversations(5).map { |card| card.primary_conversation.display_id } },
                   headers: vendas_agent.create_new_auth_token
        end

        expect(response.parsed_body['payload'].size).to eq(5)
        expect(five).to eq(two)
      end

      it 'a lista de cards não faz uma consulta de funil por card', type: :request do
        url = "/api/v1/accounts/#{account.id}/crm/cards"
        cards_with_conversations(2)
        two = funnel_queries { get url, params: { pipeline_id: vendas.first.id }, headers: vendas_agent.create_new_auth_token }
        expect(response).to have_http_status(:ok)

        cards_with_conversations(3)
        five = funnel_queries { get url, params: { pipeline_id: vendas.first.id }, headers: vendas_agent.create_new_auth_token }

        expect(response.parsed_body['payload'].size).to eq(5)
        expect(five).to eq(two)
      end
    end

    describe Crm::Ai::Evaluator do
      it 'a IA só conhece, para a passagem, quem pode receber a conversa' do
        evaluator = described_class.new(card: card_sinistro)
        allow(evaluator).to receive(:handoff_config).and_return({ enabled: true })

        names = evaluator.send(:eligible_agent_names)

        expect(names).to include(sinistro_agent.name, livre_agent.name)
        expect(names).not_to include(vendas_agent.name)
      end
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'o responsável pelo lembrete recebe o aviso como antes, mesmo fora da caixa' do
      follow_up = overdue_follow_up(card_sinistro, vendas_agent)
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      Crm::FollowUps::Broadcaster.broadcast_due(follow_up)
      Crm::FollowUps::DueProcessor.new.send(:notify_auto_send_failed, follow_up)

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with([vendas_agent.pubsub_token], any_args).twice
      expect(Crm::FollowUps::ReminderNotifier.new(follow_up).send(:recipient_users)).to include(vendas_agent)
    end

    it 'a reunião leva o card para outro funil como antes' do
      world = build_booking_world(account: account)
      meeting = create_internal_meeting(world: world, starts_at: 2.hours.ago, metadata: { 'booking_profile_id' => world.profile.id })
      world.card.update!(inbox: inbox)
      pos_venda, pos_venda_stage = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: pos_venda_stage)

      expect(held_by(meeting, vendas_agent)).to include(moved: true)
      expect(world.card.reload.pipeline_id).to eq(pos_venda.id)
    end

    it 'aceitar a sugestão da IA move como antes', type: :request do
      with_ai_role(vendas_agent)
      conversa.update!(assignee: vendas_agent)
      vistoria = create_crm_stage(account: account, pipeline: sinistro.first, name: 'Vistoria')

      accept(suggestion_for(card_sinistro, vistoria), vendas_agent)

      expect(response).to have_http_status(:ok)
      expect(card_sinistro.reload.stage_id).to eq(vistoria.id)
    end

    it 'criar card a partir da conversa, em qualquer funil, segue como antes', type: :request do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/cards",
             params: { conversation_id: conversa.id, pipeline_id: sinistro.first.id, stage_id: sinistro.last.id, title: 'x' },
             headers: vendas_agent.create_new_auth_token, as: :json
      end.to change(Crm::Card, :count).by(1)
      expect(response).to have_http_status(:ok).or have_http_status(:created)
    end

    it 'mudar o card não enfileira sincronização nem consulta a regra do funil' do
      card_sinistro

      queries = funnel_queries do
        expect { card_sinistro.update!(pipeline: vendas.first, stage: vendas.last) }
          .not_to have_enqueued_job(Crm::Access::VisibilitySyncJob)
      end

      expect(queries).to eq(0)
    end
  end
end
