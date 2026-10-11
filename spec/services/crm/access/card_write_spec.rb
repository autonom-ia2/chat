require 'rails_helper'

# Mexer no card exige o funil dele (#1148, decisão do Rodrigo em 11/10). Quem só vê o card de outro funil (dono ou
# atendente) continua vendo, mas não edita, fecha, arquiva, reabre, move nem vincula. Sem acesso por funil, e para o
# administrador, nada muda.
RSpec.describe 'Acesso por funil: mexer no card', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:contact) { create(:contact, account: account) }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: vendas_agent) }
  let(:card_sinistro) do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', inbox: inbox, contact: contact,
                              primary_conversation: conversa, owner: vendas_agent)
  end
  let(:card_vendas) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox, contact: contact,
                              owner: vendas_agent)
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def restrict!
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: vendas_agent, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: vendas.first)
  end

  def card_url(card, action = nil)
    ["/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", action].compact.join('/')
  end

  def headers(user = vendas_agent)
    user.create_new_auth_token
  end

  # O Chatwoot responde 401 a toda negação do Pundit (RequestExceptionHandler); o front não desloga por isso.
  def forbidden?
    response.status == 401
  end

  def bulk(card, action, payload = {})
    post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
         params: { ids: [card.id], action_name: action, payload: payload }, headers: headers, as: :json
    response.parsed_body['payload']
  end

  describe 'com acesso por funil' do
    before { restrict! }

    it 'dono e atendente do card de outro funil ainda o veem' do
      get card_url(card_sinistro), headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'mas não editam, fecham nem arquivam' do
      patch card_url(card_sinistro), params: { card: { title: 'Outro' } }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_sinistro, 'close'), params: { result: 'won' }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      delete card_url(card_sinistro), headers: headers, as: :json
      expect(forbidden?).to be(true)

      expect(card_sinistro.reload).to have_attributes(title: 'Sinistro', status: 'open')
    end

    it 'nem vinculam nem desvinculam conversa' do
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: vendas_agent)

      post card_url(card_sinistro, 'link_conversation'), params: { conversation_id: outra.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_sinistro, 'unlink_conversation'), params: { conversation_id: conversa.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)

      expect(card_sinistro.card_conversations.pluck(:conversation_id)).not_to include(outra.id)
    end

    it 'nem pelo lote (status, arquivar, dono)' do
      expect(bulk(card_sinistro, 'status', result: 'won')['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })
      expect(bulk(card_sinistro, 'delete')['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })
      expect(bulk(card_sinistro, 'assign', owner_id: admin.id)['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })

      expect(card_sinistro.reload).to have_attributes(status: 'open', owner_id: vendas_agent.id)
    end

    it 'nem vincula ao card uma conversa de outra caixa onde ela não tem o funil do card' do
      instagram = create_crm_inbox(account: account, name: 'Instagram', members: [vendas_agent])
      Crm::InboxAgentAccess.create!(account: account, inbox: instagram, user: vendas_agent, all_pipelines: false, triage: false)
      dela = create_crm_conversation(account: account, inbox: instagram, contact: contact, assignee: vendas_agent)

      post card_url(card_vendas, 'link_conversation'), params: { conversation_id: dela.id }, headers: headers, as: :json

      expect(forbidden?).to be(true)
      expect(card_vendas.card_conversations.pluck(:conversation_id)).not_to include(dela.id)
    end

    it 'nem cria ou muda lembrete do card' do
      follow_up = account.crm_follow_ups.create!(card: card_sinistro, title: 'Retornar', due_at: 1.day.from_now, timezone: 'UTC',
                                                 automation_mode: :reminder_only, assignee: vendas_agent, created_by: admin)

      post "/api/v1/accounts/#{account.id}/crm/follow_ups",
           params: { follow_up: { card_id: card_sinistro.id, title: 'Novo', due_at: 1.day.from_now, timezone: 'UTC' } }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      patch "/api/v1/accounts/#{account.id}/crm/follow_ups/#{follow_up.id}", params: { follow_up: { title: 'Outro' } }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post "/api/v1/accounts/#{account.id}/crm/follow_ups/#{follow_up.id}/complete", headers: headers, as: :json
      expect(forbidden?).to be(true)

      expect(follow_up.reload.title).to eq('Retornar')
    end

    describe 'com a IA do CRM', type: :request do
      around { |example| with_modified_env(CRM_AI_ENABLED: 'true') { example.run } }

      before do
        role = create(:custom_role, account: account, permissions: %w[crm_view crm_manage_cards crm_manage_ai conversation_manage])
        AccountUser.find_by(account: account, user: vendas_agent).update!(custom_role: role)
      end

      it 'não gera o resumo (gravado no card) nem recusa a sugestão de etapa' do
        vistoria = create_crm_stage(account: account, pipeline: sinistro.first, name: 'Vistoria')
        suggestion = account.crm_ai_stage_suggestions.create!(card: card_sinistro, from_stage: sinistro.last, to_stage: vistoria,
                                                              confidence: 0.9, model_used: 'test')

        post card_url(card_sinistro, 'summarize'), headers: headers, as: :json
        expect(forbidden?).to be(true)
        post "/api/v1/accounts/#{account.id}/crm/ai_suggestions/#{suggestion.id}/dismiss", headers: headers, as: :json
        expect(forbidden?).to be(true)

        expect(suggestion.reload).to be_pending
      end

      it 'no funil dela, recusa a sugestão normalmente' do
        proposta = create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta')
        suggestion = account.crm_ai_stage_suggestions.create!(card: card_vendas, from_stage: vendas.last, to_stage: proposta,
                                                              confidence: 0.9, model_used: 'test')

        post "/api/v1/accounts/#{account.id}/crm/ai_suggestions/#{suggestion.id}/dismiss", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(suggestion.reload).to be_dismissed
      end
    end

    it 'a automação da etapa não leva o card para um funil que quem moveu não pode mover' do
      step = instance_double(Crm::StageAutomationStep, action_type: 'move_stage', action_config: { 'target_stage_id' => sinistro.last.id })

      result = Crm::StageAutomations::StepExecutor.new(card: card_vendas, step: step, actor: vendas_agent).perform

      expect(result.error).to eq('funnel_not_allowed')
      expect(card_vendas.reload.pipeline_id).to eq(vendas.first.id)
    end

    it 'reabre card arquivado do funil dela mesmo sem ver a conversa (que voltou para a triagem)' do
      arquivado = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Antigo', inbox: inbox, contact: contact,
                                            primary_conversation: create_crm_conversation(account: account, inbox: inbox, contact: contact))
      arquivado.update!(status: :archived)

      patch card_url(arquivado), params: { card: { title: 'Antigo revisto' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'no funil dela, mexe normalmente' do
      patch card_url(card_vendas), params: { card: { title: 'Proposta enviada' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      post card_url(card_vendas, 'close'), params: { result: 'won' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(card_vendas.reload).to have_attributes(title: 'Proposta enviada', status: 'won')
    end

    it 'o administrador mexe em qualquer card' do
      patch card_url(card_sinistro), params: { card: { title: 'Revisado' } }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(card_sinistro.reload.title).to eq('Revisado')
    end
  end

  describe '"Só as suas" e só triagem (decisão do Rodrigo em 11/10)' do
    def access!(only_own:, triage:)
      Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: vendas_agent, all_pipelines: false, triage: triage,
                                    only_own: only_own)
    end

    it 'em "Só as suas", mexe no próprio card (editar, fechar, trocar de etapa), mas não muda de funil' do
      access!(only_own: true, triage: false)
      proposta = create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta')

      patch card_url(card_vendas), params: { card: { title: 'Meu' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post card_url(card_vendas, 'move'), params: { stage_id: proposta.id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post card_url(card_vendas, 'move'), params: { stage_id: sinistro.last.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_vendas, 'close'), params: { result: 'won' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(card_vendas.reload).to have_attributes(title: 'Meu', pipeline_id: vendas.first.id, status: 'won')
    end

    it 'só com a triagem, mexe no card da conversa que atende' do
      access!(only_own: false, triage: true)

      patch card_url(card_sinistro), params: { card: { title: 'Atendo' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'não mexe no card dos outros' do
      access!(only_own: true, triage: false)
      alheio = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Alheio', inbox: inbox, contact: contact,
                                         owner: admin)

      patch card_url(alheio), params: { card: { title: 'X' } }, headers: headers, as: :json

      expect(response.status).to be_in([401, 404])
      expect(alheio.reload.title).to eq('Alheio')
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'o dono mexe no card de qualquer funil, como antes' do
      patch card_url(card_sinistro), params: { card: { title: 'Outro' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(bulk(card_sinistro, 'delete')['updated']).to eq([card_sinistro.id])
      expect(card_sinistro.reload).to have_attributes(title: 'Outro', status: 'archived')
    end
  end
end
