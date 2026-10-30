require 'rails_helper'

# CRM › Números por papel (#1897, F3 do #1871): a visão "Só eu" por HTTP, a matriz de quem vê o quê e o fim do
# vazamento (Decisão 2): com a flag, o agente comum deixa de ler os números da equipe; sem a flag, nada muda.
RSpec.describe 'Api::V1::Accounts::Crm::Numeros', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Marcos') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:sale) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') do
      travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run }
    end
  end

  before do
    account.enable_features('crm_numeros_lentes')
    account.save!
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(user, path, params = {})
    get path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def card(owner:, value_cents: 0, **attrs)
    pipeline, stage = sale
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, title: "Card #{SecureRandom.hex(3)}",
                              value_cents: value_cents, **attrs)
  end

  def won(card)
    Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform
  end

  describe 'quem vê o quê' do
    let(:people) do
      {
        admin: admin, agent: ana, gestor: role_user('crm_view', 'crm_view_reports'), crm: role_user('crm_view'),
        socio: role_user('crm_view_reports'), sem_crm: role_user('conversation_manage')
      }
    end

    it 'dá "Só eu" a quem trabalha no CRM, "Equipe" a quem tem a chave, e nega quem não tem nenhuma' do
      expected = {
        admin: %w[eu equipe], agent: %w[eu], gestor: %w[eu equipe], crm: %w[eu], socio: %w[equipe], sem_crm: nil
      }
      expected.each do |who, visoes|
        call(people[who], "#{base}/numeros")
        if visoes.nil?
          expect(response).to have_http_status(:unauthorized), who.to_s
        else
          expect(response).to have_http_status(:ok), who.to_s
          expect(response.parsed_body['visoes']).to eq(visoes), who.to_s
        end
      end
    end

    it 'só a visão da equipe para quem só tem a chave dela: nenhum número pessoal na resposta' do
      call(people[:socio], "#{base}/numeros")

      expect(response.parsed_body.keys).to contain_exactly('visoes', 'visao', 'mes')
    end

    it 'fecha os números da equipe para o agente comum com a flag, e só para ele' do
      sale
      %i[agent crm].each do |who|
        call(people[who], "#{base}/reports/summary")
        expect(response).to have_http_status(:unauthorized), who.to_s
        call(people[who], "#{base}/ai_usage")
        expect(response).to have_http_status(:unauthorized), who.to_s
        call(people[who], "#{base}/meta_conversions/summary")
        expect(response).to have_http_status(:unauthorized), who.to_s
      end
      %i[admin gestor socio].each do |who|
        call(people[who], "#{base}/reports/summary")
        expect(response).to have_http_status(:ok), who.to_s
        call(people[who], "#{base}/meta_conversions/summary")
        expect(response).to have_http_status(:ok), who.to_s
      end
    end

    it 'sem a flag nada muda: o agente comum segue lendo o painel e o endpoint novo não existe' do
      account.disable_features('crm_numeros_lentes')
      account.save!
      sale

      call(ana, "#{base}/reports/summary")
      expect(response).to have_http_status(:ok)
      call(ana, "#{base}/numeros")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'a visão "Só eu"' do
    it 'conta só o que é da pessoa, sem nome nem valor de colega, e a barra da equipe só em porcentagem' do
      sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 2_000_000, 'currency' => 'BRL' } })
      won(card(owner: ana, value_cents: 620_000))
      won(card(owner: bruno, value_cents: 700_000))
      card(owner: ana, next_follow_up_at: 1.day.ago)
      card(owner: ana)

      call(ana, "#{base}/numeros")

      body = response.parsed_body
      expect(body).to include('visao' => 'eu', 'papel' => 'vende', 'moeda' => 'BRL', 'equipePct' => 66, 'estimado' => false,
                              'podeCriarFunil' => false, 'atendendo' => nil, 'funis' => { 'vendas' => sale.first.id, 'suporte' => nil })
      expect(body['topo']).to include('escopo' => 'eu', 'feito' => 6200.0, 'meta' => nil, 'fechadas' => 1,
                                      'botao' => { 'tipo' => 'meus_atrasados', 'n' => 1 })
      expect(body['vendendo']['itens']).to eq([
                                                { 'tipo' => 'fechadas', 'n' => 1, 'valor' => 6200.0, 'lista' => true },
                                                { 'tipo' => 'andamento', 'n' => 2 },
                                                { 'tipo' => 'atrasados', 'n' => 1 }
                                              ])
      expect(response.body).not_to include('Bruno', '7000.0')
    end

    it 'aceita o mês anterior e recusa o mês que ainda não chegou' do
      sale
      call(ana, "#{base}/numeros", mes: '2026-09')
      expect(response.parsed_body['mes']).to include('chave' => '2026-09', 'fechado' => true)

      call(ana, "#{base}/numeros", mes: '2026-11')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.numeros.mes_invalido')
    end

    it 'conta sem funil nenhum como tela vazia, com o botão de criar só para quem pode' do
      call(admin, "#{base}/numeros")
      expect(response.parsed_body).to include('vazio' => true, 'podeCriarFunil' => true)

      call(ana, "#{base}/numeros")
      expect(response.parsed_body).to include('vazio' => true, 'podeCriarFunil' => false)
    end
  end

  describe 'a visão "Equipe" nova (#1992)' do
    let(:gestor) { role_user('crm_view', 'crm_view_reports') }
    let(:socio) { role_user('crm_view_reports') }

    before do
      won(card(owner: ana, value_cents: 620_000))
      won(card(owner: bruno, value_cents: 290_000))
    end

    def ligar_equipe
      account.enable_features('crm_numeros_equipe')
      account.save!
    end

    it 'sem a flag, quem pede a equipe recebe o de antes: o administrador fica no "Só eu" e o sócio só nas visões' do
      call(admin, "#{base}/numeros", visao: 'equipe')
      expect(response.parsed_body['visao']).to eq('eu')

      call(socio, "#{base}/numeros")
      expect(response.parsed_body.keys).to contain_exactly('visoes', 'visao', 'mes')
    end

    # #2075: o gestor desta função não tem sales_value_view, então vê as linhas sem o R$.
    it 'com a flag, o administrador vê o R$ de cada um e o custo da IA; o gestor vê as linhas sem R$ nem custo' do
      ligar_equipe

      call(admin, "#{base}/numeros", visao: 'equipe')
      body = response.parsed_body
      expect(body).to include('visao' => 'equipe', 'papel' => 'dono', 'visoes' => %w[eu equipe], 'leitura' => false)
      expect(body['quemCuidou']['linhas'].map { |linha| linha['venda']['valor'] }).to contain_exactly(6200.0, 2900.0)

      call(gestor, "#{base}/numeros", visao: 'equipe')
      expect(response.parsed_body).to include('visao' => 'equipe', 'papel' => 'gestor_vendas')
      expect(response.parsed_body['quemCuidou']['linhas'].map { |linha| linha['venda']['valor'] }).to eq([nil, nil])
      expect(response.parsed_body.dig('quemCuidou', 'ia', 'custo')).to be_nil
    end

    # #1999: o custo da IA é dinheiro da conta e segue financial_view (#1982), não o papel de administrador.
    it 'com a flag, o custo da IA aparece para quem tem financial_view e some para quem só vê os relatórios' do
      ligar_equipe
      allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: 5.0, fetched_at: nil)
      robo = create(:agent_bot, account: account, name: 'Sofia')
      chat = create_crm_conversation(account: account, inbox: create_crm_inbox(account: account, members: [ana]),
                                     contact: create(:contact, account: account))
      card(owner: ana, primary_conversation: chat)
      create(:message, account: account, inbox: chat.inbox, conversation: chat, message_type: :outgoing, sender: robo)
      financeiro = role_user('crm_view_reports')
      # A chave financial_view entra no CustomRole::PERMISSIONS no #1969; até o merge com a main, gravada direto.
      financeiro.account_users.find_by(account: account).custom_role
                .update_column(:permissions, %w[crm_view_reports financial_view]) # rubocop:disable Rails/SkipsModelValidations

      call(financeiro, "#{base}/numeros")
      expect(response.parsed_body.dig('quemCuidou', 'ia', 'custo')).to include('moeda')

      call(socio, "#{base}/numeros")
      expect(response.parsed_body.dig('quemCuidou', 'ia')).to be_present
      expect(response.parsed_body.dig('quemCuidou', 'ia', 'custo')).to be_nil
    end

    it 'com a flag, o agente comum que pede a equipe continua no "Só eu", sem nome de colega' do
      ligar_equipe

      call(ana, "#{base}/numeros", visao: 'equipe')

      expect(response.parsed_body).to include('visao' => 'eu', 'visoes' => %w[eu])
      expect(response.body).not_to include('Bruno')
    end

    it 'com a flag, quem só vê a equipe recebe a equipe em modo leitura, sem botões' do
      ligar_equipe

      call(socio, "#{base}/numeros")

      expect(response.parsed_body).to include('visao' => 'equipe', 'papel' => 'leitura', 'leitura' => true, 'proximo' => [])
      expect(response.parsed_body['topo']['botao']).to be_nil
    end
  end
end
