require 'rails_helper'

RSpec.describe 'CRM calendar API', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'returns follow-ups and expected closes scoped to the selected pipeline' do
    account, user = create_account_and_user
    first_pipeline, first_stage = create_crm_pipeline(account: account, user: user, name: 'Vendas')
    second_pipeline, second_stage = create_crm_pipeline(account: account, user: user, name: 'Suporte')
    first_card = account.crm_cards.create!(
      pipeline: first_pipeline,
      stage: first_stage,
      title: 'Lead Vendas',
      expected_close_at: 2.days.from_now
    )
    second_card = account.crm_cards.create!(
      pipeline: second_pipeline,
      stage: second_stage,
      title: 'Lead Suporte',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(card: first_card, title: 'Retornar Vendas', due_at: 1.day.from_now, timezone: 'UTC', created_by: user)
    account.crm_follow_ups.create!(card: second_card, title: 'Retornar Suporte', due_at: 1.day.from_now, timezone: 'UTC', created_by: user)

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: {
          pipeline_id: first_pipeline.id,
          from: 1.hour.ago.iso8601,
          to: 3.days.from_now.iso8601
        },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Lead Vendas', 'Retornar Vendas')
    expect(titles).not_to include('Lead Suporte', 'Retornar Suporte')
  end

  # #1538: o vencimento é uma data (00:00 UTC). A janela do mês em São Paulo começa às 03:00 UTC do dia 1; o vencimento
  # do dia 1 precisa aparecer, e o do último dia do mês anterior não.
  it 'inclui o vencimento do primeiro dia da janela pedida no fuso de quem olha' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Cobrança')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Vence no dia 1', expected_close_at: '2026-10-01')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Venceu antes', expected_close_at: '2026-09-30')

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: { pipeline_id: pipeline.id, from: '2026-10-01T00:00:00-03:00', to: '2026-10-31T23:59:59-03:00' },
        headers: auth_headers(user)

    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Vence no dia 1')
    expect(titles).not_to include('Venceu antes')
  end

  it 'filters follow-ups and expected closes by owner_id from the frontend filters' do
    account, admin = create_account_and_user
    first_owner, = create_crm_agent(account: account, name: 'Primeiro')
    second_owner, = create_crm_agent(account: account, name: 'Segundo')
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    first_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: first_owner,
      title: 'Lead Primeiro',
      expected_close_at: 2.days.from_now
    )
    second_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: second_owner,
      title: 'Lead Segundo',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(
      card: first_card,
      assignee: first_owner,
      title: 'Retornar Primeiro',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: admin
    )
    account.crm_follow_ups.create!(
      card: second_card,
      assignee: second_owner,
      title: 'Retornar Segundo',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: admin
    )

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: {
          pipeline_id: pipeline.id,
          owner_id: first_owner.id,
          from: 1.hour.ago.iso8601,
          to: 3.days.from_now.iso8601
        },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Lead Primeiro', 'Retornar Primeiro')
    expect(titles).not_to include('Lead Segundo', 'Retornar Segundo')
  end

  it 'handles invalid calendar filter params without server errors' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead Seguro',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(
      card: card,
      title: 'Retornar Seguro',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: user
    )

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: { pipeline_id: pipeline.id, from: 'data-invalida', to: '999999-01-01', limit: -20 },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to be_an(Array)
  end

  # #1568: o calendário "Meu dia" mostra o cliente e abre a conversa pelo número dela. Sem funil, a consulta já trazia
  # todos os funis (guarda de regressão, não prova nova).
  describe 'detalhes do Meu dia' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, role: :administrator) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, name: 'Mariana Costa', phone_number: '+5511987654321') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    def eventos(params = {}, como: user)
      get "/api/v1/accounts/#{account.id}/crm/calendar/events",
          params: { from: '2026-10-01T00:00:00-03:00', to: '2026-10-31T23:59:59-03:00' }.merge(params),
          headers: auth_headers(como)
      expect(response).to have_http_status(:ok)
      response.parsed_body['payload'].index_by { |event| event['title'] }
    end

    it 'traz o nome e o telefone do cliente e o número da conversa' do
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual', contact: contact,
                                       conversation_id: conversation.id)
      account.crm_follow_ups.create!(card: card, conversation: conversation, contact: contact, title: 'Responder a Mariana',
                                     due_at: '2026-10-14T19:30:00Z', timezone: 'America/Sao_Paulo', created_by: user)

      evento = eventos['Responder a Mariana']

      expect(evento).to include('contact_name' => 'Mariana Costa', 'contact_phone' => '+5511987654321',
                                'conversation_id' => conversation.id, 'conversation_display_id' => conversation.display_id)
    end

    # #1590: a mensagem marcada que não saiu traz o motivo como código; o texto cru fica no servidor.
    it 'manda o motivo de a mensagem marcada não ter saído' do
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual', contact: contact,
                                       conversation_id: conversation.id)
      falhou = account.crm_follow_ups.create!(card: card, contact: contact, title: 'Não saiu', due_at: '2026-10-14T19:30:00Z',
                                              timezone: 'UTC', created_by: user)
      falhou.update!(status: :overdue, metadata: { 'send_error' => 'sender_required' })

      expect(eventos['Não saiu']).to include('send_error_code' => 'sem_remetente')
      expect(eventos['Não saiu'].to_json).not_to include('sender_required')
    end

    it 'não manda o contato de um lembrete quando ele não é o do card nem o da conversa' do
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      outro = create(:contact, account: account, name: 'Outra Pessoa', phone_number: '+5511900000000')
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual', contact: contact)
      account.crm_follow_ups.create!(card: card, contact: outro, title: 'Contato trocado', due_at: '2026-10-14T19:30:00Z',
                                     timezone: 'UTC', created_by: user)

      expect(eventos['Contato trocado']).to include('contact_id' => nil, 'contact_name' => nil, 'contact_phone' => nil)
    end

    it 'não manda o número da conversa que a pessoa não pode ver' do
      agente = create(:user, account: account, role: :agent)
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual', contact: contact, owner: agente,
                                       conversation_id: conversation.id)
      account.crm_follow_ups.create!(card: card, conversation: conversation, contact: contact, assignee: agente,
                                     title: 'Conversa fechada', due_at: '2026-10-14T19:30:00Z', timezone: 'UTC', created_by: user)
      # O agente cuida do card, mas não está na caixa da conversa: a regra real de visibilidade decide.
      expect(eventos({}, como: agente)['Conversa fechada']).to include('conversation_id' => nil, 'conversation_display_id' => nil)
    end

    it 'passando do limite, deixa de fora os lembretes mais antigos, não os de hoje' do
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual')
      %w[2026-10-02 2026-10-10 2026-10-14].each do |dia|
        account.crm_follow_ups.create!(card: card, title: "Lembrete #{dia}", due_at: "#{dia}T15:00:00Z", timezone: 'UTC',
                                       created_by: user)
      end

      titulos = eventos({ limit: 2 }).keys

      expect(titulos).to eq(['Lembrete 2026-10-10', 'Lembrete 2026-10-14'])
    end

    it 'manda o vencimento como dia inteiro, com a data UTC' do
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Vence dia 20', expected_close_at: '2026-10-20')

      expect(eventos['Vence dia 20']).to include('all_day' => true, 'date' => '2026-10-20')
    end

    it 'sem funil, traz os eventos de todos os funis' do
      vendas, etapa_vendas = create_crm_pipeline(account: account, user: user, name: 'Vendas')
      cobranca, etapa_cobranca = create_crm_pipeline(account: account, user: user, name: 'Cobrança')
      venda = account.crm_cards.create!(pipeline: vendas, stage: etapa_vendas, title: 'Card de venda')
      conta = account.crm_cards.create!(pipeline: cobranca, stage: etapa_cobranca, title: 'Card de cobrança')
      [[venda, 'Ligar na venda'], [conta, 'Ligar na cobrança']].each do |card, titulo|
        account.crm_follow_ups.create!(card: card, title: titulo, due_at: '2026-10-15T12:00:00Z', timezone: 'UTC', created_by: user)
      end

      expect(eventos.keys).to include('Ligar na venda', 'Ligar na cobrança')
    end
  end
end
