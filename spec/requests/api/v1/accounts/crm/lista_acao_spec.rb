require 'rails_helper'

# Lista nova "o que fazer agora" (#2283): a lista (sort=acao) e a contagem (summaries?group_by=acao) contam o mesmo, e
# nada conta conversa que a pessoa não vê.
RSpec.describe 'CRM Lista nova (sort=acao)', type: :request do
  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestora Ana') }
  let(:agent) { create_crm_agent(account: account, name: 'Atendente Beto').first }
  let(:inbox) { create_crm_inbox(account: account, members: [admin, agent]) }
  let(:hidden_inbox) { create_crm_inbox(account: account, name: 'Caixa da gestão', members: [admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:api) { "/api/v1/accounts/#{account.id}/crm" }

  def conversation(inbox:, assignee: nil, waiting: false)
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: assignee).tap do |record|
      record.update_columns(waiting_since: waiting ? 1.hour.ago : nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def card(title, inbox:, conversation: nil, owner: nil)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, inbox: inbox, owner: owner,
                              primary_conversation: conversation)
  end

  def list(user, params = {})
    get "#{api}/cards", params: { sort: 'acao', per_page: 100 }.merge(params), headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def counts(user, params = {})
    get "#{api}/cards/summaries", params: { group_by: 'acao' }.merge(params), headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'groups').to_h { |group| [group['key'], group['count']] }
  end

  describe 'agente sem acesso à caixa' do
    let!(:visible_waiting) do
      card('Esperando visível', inbox: inbox, owner: agent, conversation: conversation(inbox: inbox, assignee: agent, waiting: true))
    end
    # O card é da caixa do agente, mas a conversa é de uma caixa que ele não vê.
    let!(:hidden_conversation_card) do
      card('Conversa invisível', inbox: inbox, conversation: conversation(inbox: hidden_inbox, assignee: admin, waiting: true))
    end

    before do
      card('Card da caixa fechada', inbox: hidden_inbox, conversation: conversation(inbox: hidden_inbox, waiting: true))
      card('Conversa invisível sem ninguém', inbox: inbox, conversation: conversation(inbox: hidden_inbox))
    end

    it 'conta na contagem o mesmo que a lista mostra, sem o card nem a conversa invisíveis' do
      body = list(agent)
      rows = body['payload'].to_h { |row| [row['title'], row['action_group']] }
      waiting = list(agent, waiting: 'true')

      expect(rows).to eq('Esperando visível' => 'esperando', 'Conversa invisível' => 'demais',
                         'Conversa invisível sem ninguém' => 'demais')
      expect(counts(agent)).to eq('esperando' => 1, 'retorno' => 0, 'ninguem' => 0, 'parado' => 0, 'demais' => 2)
      expect(counts(agent).values.sum).to eq(body.dig('meta', 'count'))
      expect(waiting['payload'].pluck('id')).to eq([visible_waiting.id])
      expect(waiting.dig('meta', 'count')).to eq(counts(agent)['esperando'])
    end

    it 'não manda o nome de quem conversa nem de quem cuida da conversa invisível' do
      row = list(agent)['payload'].find { |item| item['id'] == hidden_conversation_card.id }

      expect(row).not_to have_key('responsible')
      expect(row['current_responsible']).to be_nil
      expect(row['conversation_id']).to be_nil
      expect(response.body).not_to include('Gestora Ana')
    end

    it 'também não manda no Quadro o nome de quem conversa na conversa invisível' do
      get "#{api}/kanban", params: { pipeline_id: hidden_conversation_card.pipeline_id }, headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
      row = response.parsed_body.dig('payload', 'stages').flat_map { |stage| stage['cards'] }
                    .find { |item| item['id'] == hidden_conversation_card.id }
      expect(row['responsible']).to be_nil
      expect(response.body).not_to include('Gestora Ana')
    end

    it 'mostra ao administrador a conversa e quem cuida' do
      row = list(admin)['payload'].find { |item| item['id'] == hidden_conversation_card.id }

      expect(row['action_group']).to eq('esperando')
      expect(row['current_responsible']).to include('type' => 'agent', 'name' => 'Gestora Ana')
      expect(counts(admin)).to include('esperando' => 3, 'ninguem' => 1)
    end
  end

  describe 'retorno' do
    it 'põe o retorno vencido ontem no grupo 2 com o id para o "Feito"' do
      overdue_card = card('Retorno de ontem', inbox: inbox, owner: agent, conversation: conversation(inbox: inbox, assignee: agent))
      overdue = account.crm_follow_ups.create!(card: overdue_card, created_by: agent, title: 'Ligar', due_at: 1.day.ago,
                                               timezone: 'America/Sao_Paulo', status: :overdue)
      account.crm_follow_ups.create!(card: overdue_card, created_by: agent, title: 'Ligar de novo', due_at: 2.days.from_now,
                                     timezone: 'America/Sao_Paulo')

      row = list(agent)['payload'].find { |item| item['id'] == overdue_card.id }

      expect(row).to include('action_group' => 'retorno', 'next_follow_up_id' => overdue.id)
      expect(counts(agent)['retorno']).to eq(1)
      expect(list(agent, follow_up_status: 'due')['payload'].pluck('id')).to eq([overdue_card.id])
    end

    it 'põe no grupo 2 o lembrete da IA para a equipe que já disparou, com o id dele para o "Feito"' do
      ai_card = card('Lembrete da IA', inbox: inbox, owner: agent, conversation: conversation(inbox: inbox, assignee: agent))
      # Como o AutoFollowupRunner#create_reminder deixa o toque no modo "IA lembra a equipe", vencido pelo DueProcessor.
      reminder = account.crm_follow_ups.create!(card: ai_card, created_by: agent, title: 'Lembrete da IA', due_at: 2.hours.ago,
                                                timezone: 'America/Sao_Paulo', status: :overdue, follow_up_type: :message,
                                                metadata: { 'source' => Crm::FollowUp::AI_FOLLOWUP_SOURCE, 'touch' => 1,
                                                            'action_mode' => Crm::FollowUp::AI_REMINDER_ACTION_MODE })
      # O próximo toque da cadência, ainda sem disparar, segue fora.
      account.crm_follow_ups.create!(card: ai_card, created_by: agent, title: 'Toque 2', due_at: 3.hours.ago,
                                     timezone: 'America/Sao_Paulo', follow_up_type: :message,
                                     metadata: { 'source' => Crm::FollowUp::AI_FOLLOWUP_SOURCE, 'touch' => 2 })

      row = list(agent)['payload'].find { |item| item['id'] == ai_card.id }

      expect(row).to include('action_group' => 'retorno', 'next_follow_up_id' => reminder.id)
      expect(counts(agent)['retorno']).to eq(1)
    end
  end

  describe 'só meus' do
    it 'traz a conversa minha esperando em card de outro dono no grupo 1 e na contagem' do
      mine_in_other_card = card('Card do gestor, conversa minha', inbox: inbox, owner: admin,
                                                                  conversation: conversation(inbox: inbox, assignee: agent, waiting: true))
      card('Card do gestor', inbox: inbox, owner: admin, conversation: conversation(inbox: inbox, assignee: admin, waiting: true))
      nobody = card('Ninguém cuidando', inbox: inbox, conversation: conversation(inbox: inbox))

      body = list(agent, mine: 'true')

      expect(body['payload'].to_h { |row| [row['id'], row['action_group']] })
        .to eq(mine_in_other_card.id => 'esperando', nobody.id => 'ninguem')
      expect(counts(agent, mine: 'true')).to eq('esperando' => 1, 'retorno' => 0, 'ninguem' => 1, 'parado' => 0, 'demais' => 0)
      expect(body.dig('meta', 'count')).to eq(2)
    end
  end

  it 'mantém a Lista atual sem os campos de grupo quando não pede sort=acao' do
    card('Qualquer', inbox: inbox, owner: agent)

    get "#{api}/cards", headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['payload'].first
    expect(row).not_to have_key('action_group')
    expect(row['current_responsible']).to include('type' => 'agent', 'name' => 'Atendente Beto')
    expect(row['next_follow_up_id']).to be_nil
  end
end
