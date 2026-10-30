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

      expect(row).to include('action_group' => 'retorno', 'next_follow_up_id' => overdue.id,
                             'next_follow_up_due_at' => overdue.due_at.iso8601)
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

    # A conversa é da pessoa, mas numa caixa que ela não vê: o card não entra em "Só meus" (nem esperando, nem ninguém
    # cuidando) e, na lista inteira, fica em "demais" sem quem cuida, sem a conversa e sem o retorno dela.
    it 'deixa fora o card cuja conversa é minha numa caixa que não vejo' do
      mine_hidden = conversation(inbox: hidden_inbox, assignee: agent, waiting: true)
      hidden_card = card('Minha, caixa oculta', inbox: inbox, conversation: mine_hidden)
      account.crm_follow_ups.create!(card: hidden_card, conversation: mine_hidden, created_by: agent, title: 'Retorno oculto',
                                     due_at: 1.day.ago, timezone: 'America/Sao_Paulo', status: :overdue)

      expect(list(agent, mine: 'true')['payload']).to eq([])
      expect(counts(agent, mine: 'true').values.sum).to eq(0)
      row = list(agent)['payload'].find { |item| item['id'] == hidden_card.id }
      expect(row).to include('action_group' => 'demais', 'current_responsible' => nil, 'conversation_id' => nil,
                             'next_follow_up_id' => nil)
    end
  end

  it 'mantém a Lista atual sem os campos de grupo quando não pede sort=acao' do
    card('Qualquer', inbox: inbox, owner: agent)

    get "#{api}/cards", headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['payload'].first
    expect(row).not_to have_key('action_group')
    expect(row['current_responsible']).to include('type' => 'agent', 'name' => 'Atendente Beto')
    expect(row).to include('next_follow_up_id' => nil, 'next_follow_up_due_at' => nil, 'conversation_hidden' => false)
  end

  it 'devolve lista vazia, e não a lista inteira, com grupo inválido' do
    card('Qualquer', inbox: inbox, owner: agent)

    body = list(agent, action_group: 'nao-existe')

    expect(body['payload']).to eq([])
    expect(body.dig('meta', 'count')).to eq(0)
  end

  it 'conta uma vez, na lista, no count e na contagem, o card com várias conversas' do
    many = card('Várias conversas', inbox: inbox, owner: agent, conversation: conversation(inbox: inbox, assignee: agent, waiting: true))
    2.times do
      many.card_conversations.create!(account: account, conversation: conversation(inbox: inbox, assignee: agent), linked_by: admin)
    end

    body = list(agent)

    expect(body['payload'].pluck('id')).to eq([many.id])
    expect(body['payload'].first['action_group']).to eq('esperando')
    expect(body.dig('meta', 'count')).to eq(1)
    expect(counts(agent).values.sum).to eq(1)
  end

  describe 'lembrete de outra conta' do
    it 'não põe o card em retorno nem manda o id, com e sem funil' do
      own = card('Card desta conta', inbox: inbox, owner: agent, conversation: conversation(inbox: inbox, assignee: agent))
      stranger = account.crm_follow_ups.create!(card: own, created_by: agent, title: 'De outra conta', due_at: 1.day.ago,
                                                timezone: 'America/Sao_Paulo', status: :overdue)
      stranger.update_columns(account_id: create(:account).id) # rubocop:disable Rails/SkipsModelValidations

      [{}, { pipeline_id: own.pipeline_id }].each do |params|
        row = list(agent, params)['payload'].find { |item| item['id'] == own.id }

        expect(row).to include('action_group' => 'demais', 'next_follow_up_id' => nil)
        expect(counts(agent, params)['retorno']).to eq(0)
      end
      get "#{api}/cards/#{own.id}", headers: auth_headers(agent)
      expect(response.parsed_body.dig('payload', 'next_follow_up_id')).to be_nil
    end
  end

  describe 'retorno de conversa oculta' do
    let(:hidden_conversation) { conversation(inbox: hidden_inbox, assignee: admin) }
    let!(:shown_card) { card('Card visível, conversa oculta', inbox: inbox, owner: agent, conversation: hidden_conversation) }

    it 'não conta nem manda o id do retorno ligado à conversa que a pessoa não vê' do
      account.crm_follow_ups.create!(card: shown_card, conversation: hidden_conversation, created_by: admin, title: 'Retorno oculto',
                                     due_at: 1.day.ago, timezone: 'America/Sao_Paulo', status: :overdue)

      row = list(agent)['payload'].find { |item| item['id'] == shown_card.id }

      expect(row).to include('action_group' => 'demais', 'next_follow_up_id' => nil, 'conversation_hidden' => true)
      expect(counts(agent)['retorno']).to eq(0)
      expect(list(agent, follow_up_status: 'due')['payload']).to eq([])
      get "#{api}/cards/#{shown_card.id}", headers: auth_headers(agent)
      expect(response.parsed_body.dig('payload', 'next_follow_up_id')).to be_nil
    end

    it 'não diz que outra pessoa está conversando quando ninguém atende a conversa oculta' do
      hidden_conversation.update!(assignee: nil)

      row = list(agent)['payload'].find { |item| item['id'] == shown_card.id }

      expect(row['conversation_hidden']).to be(false)
    end

    it 'conta o retorno sem conversa do mesmo card, que o grupo calcula só com dado visível' do
      visible = account.crm_follow_ups.create!(card: shown_card, created_by: agent, title: 'Ligar', due_at: 1.day.ago,
                                               timezone: 'America/Sao_Paulo', status: :overdue)

      row = list(agent)['payload'].find { |item| item['id'] == shown_card.id }

      expect(row).to include('action_group' => 'retorno', 'next_follow_up_id' => visible.id, 'conversation_id' => nil)
    end
  end

  describe 'consultas por página' do
    def sql_count(&)
      count = 0
      counter = lambda { |*, payload|
        next if payload[:name] == 'SCHEMA' || payload[:sql].start_with?('BEGIN', 'COMMIT')

        count += 1
      }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
      count
    end

    # Cada rodada traz caixas novas, cada uma com o próprio robô ativo: uma que o agente vê e outra que ele não vê (a
    # conversa oculta, atendida pela gestora, cai no robô da caixa no lugar do atendente).
    def seed_round(pairs)
      pairs.times do
        tag = SecureRandom.hex(3)
        shown = create_crm_inbox(account: account, name: "Robô visível #{tag}", members: [admin, agent])
        hidden = create_crm_inbox(account: account, name: "Robô oculto #{tag}", members: [admin])
        [shown, hidden].each { |box| AgentBotInbox.create!(inbox: box, agent_bot: create(:agent_bot, account: account), status: :active) }
        card("Atendido #{tag}", inbox: inbox, conversation: conversation(inbox: inbox, assignee: agent))
        card("Robô #{tag}", inbox: shown, conversation: conversation(inbox: shown))
        card("Oculta #{tag}", inbox: inbox, conversation: conversation(inbox: hidden, assignee: admin))
      end
    end

    def surfaces(user)
      pipeline_id = pipeline_and_stage.first.id
      list = { nova: ["#{api}/cards", { sort: 'acao' }], legada: ["#{api}/cards", {}],
               quadro: ["#{api}/kanban", { pipeline_id: pipeline_id }] }
      user == admin ? list.merge(planilha: ["#{api}/cards/export", {}]) : list
    end

    def measure(user)
      surfaces(user).transform_values do |(path, params)|
        get path, params: params, headers: auth_headers(user) # aquece (cache de conta, permissões)
        sql_count { get path, params: params, headers: auth_headers(user) }
      end
    end

    it 'não cresce com cards nem com caixas de robô, para gestor e agente, em todas as telas' do
      seed_round(1)
      before = { admin: measure(admin), agent: measure(agent) }
      seed_round(3)
      after = { admin: measure(admin), agent: measure(agent) }

      expect(after).to eq(before)
    end
  end

  describe 'quem cuida com a conversa oculta' do
    def board_row(card)
      get "#{api}/kanban", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(agent)
      response.parsed_body.dig('payload', 'stages').flat_map { |stage| stage['cards'] }.find { |item| item['id'] == card.id }
    end

    it 'mostra o dono do card no lugar de quem atende a conversa oculta' do
      owned = card('Com dono', inbox: inbox, owner: agent, conversation: conversation(inbox: hidden_inbox, assignee: admin))

      row = list(agent)['payload'].find { |item| item['id'] == owned.id }

      expect(row['current_responsible']).to include('type' => 'agent', 'name' => 'Atendente Beto')
      expect(row['responsible']).to include('type' => 'agent', 'name' => 'Atendente Beto')
      expect(row.dig('owner', 'name')).to eq('Atendente Beto')
      expect(response.body).not_to include('Gestora Ana')
      expect(board_row(owned)['responsible']).to include('type' => 'agent', 'name' => 'Atendente Beto')
      expect(response.body).not_to include('Gestora Ana')
    end

    it 'mostra o robô da caixa no lugar de quem atende a conversa oculta, num card sem dono' do
      AgentBotInbox.create!(inbox: hidden_inbox, agent_bot: create(:agent_bot, account: account, name: 'Assistente Bia'), status: :active)
      attended = card('Atendida sem dono', inbox: inbox, conversation: conversation(inbox: hidden_inbox, assignee: admin))

      row = list(agent)['payload'].find { |item| item['id'] == attended.id }

      expect(row['current_responsible']).to include('type' => 'bot', 'name' => 'Assistente Bia')
      expect(board_row(attended)['responsible']).to include('type' => 'bot', 'name' => 'Assistente Bia')
      expect(response.body).not_to include('Gestora Ana')
    end

    it 'mostra o robô da caixa quando ninguém atende a conversa oculta' do
      AgentBotInbox.create!(inbox: hidden_inbox, agent_bot: create(:agent_bot, account: account, name: 'Assistente Bia'), status: :active)
      by_bot = card('Robô cuida', inbox: inbox, conversation: conversation(inbox: hidden_inbox))

      row = list(agent)['payload'].find { |item| item['id'] == by_bot.id }

      expect(row['current_responsible']).to include('type' => 'bot', 'name' => 'Assistente Bia')
      expect(row['responsible']).to include('type' => 'bot', 'name' => 'Assistente Bia')
      expect(board_row(by_bot)['responsible']).to include('type' => 'bot', 'name' => 'Assistente Bia')
    end
  end
end
