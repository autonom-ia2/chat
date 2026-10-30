require 'rails_helper'

# Números › "De onde vieram os clientes" (#2001, F6) por HTTP: a flag, quem abre, o funil que a pessoa vê, o gasto só
# para quem vê os anúncios, o R$ só com `sales_value_view` e o relatório baixado com as mesmas regras (a lista de
# clientes só com `crm_export`).
RSpec.describe 'Api::V1::Accounts::Crm::NumerosOrigens', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Marcos') }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').tap { |(funil, _)| funil.update!(is_default: true) } }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/numeros/origens" }
  let(:anuncio) { '120210000000101' }
  let(:conexao) { create_meta_ads_insights_connection(account) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { travel_to(Time.utc(2026, 10, 20, 15, 0)) { example.run } }
  end

  before do
    account.enable_features!('crm_numeros_lentes', 'crm_numeros_equipe', 'crm_numeros_origens')
    ganho(card(vendas, nome: 'Marina Souza', campaign: { 'source' => 'meta_ctwa', 'source_id' => anuncio, 'headline' => 'Oferta' },
                       valor: 120_000))
    card(vendas, nome: 'Paulo Lima')
    card(suporte, nome: 'Rita Alves', campaign: { 'source' => 'google_ads' })
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: conexao.ad_account_id, ad_id: anuncio, date: Date.new(2026, 10, 6),
                                    currency: 'BRL', spend: 300, link_clicks: 40, attribution_window: '7d_click', fetched_at: Time.current)
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def card(funil, nome:, campaign: nil, valor: 0)
    pipeline, stage = funil
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account, name: nome))
    conversation.update_columns(additional_attributes: { 'campaign' => campaign }) if campaign # rubocop:disable Rails/SkipsModelValidations
    account.crm_cards.create!(pipeline: pipeline, stage: stage, primary_conversation: conversation, contact: conversation.contact,
                              title: "Card de #{nome}", value_cents: valor, created_at: Time.utc(2026, 10, 5, 12))
  end

  def ganho(card)
    card.update_columns(status: Crm::Card.statuses[:won], closed_at: Time.utc(2026, 10, 10, 12)) # rubocop:disable Rails/SkipsModelValidations
  end

  def call(user, path = base, params = {})
    get path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def baixar(user, formato, params = {})
    get "#{base}/report", params: params.merge(formato: formato), headers: user.create_new_auth_token
  end

  def texto_do_pdf
    PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
  end

  def celulas(aba)
    planilha = Roo::Excelx.new(StringIO.new(response.body))
    folha = planilha.sheet(aba)
    (1..folha.last_row.to_i).flat_map { |linha| folha.row(linha) }.compact.map(&:to_s)
  end

  def abas
    Roo::Excelx.new(StringIO.new(response.body)).sheets
  end

  describe 'quem abre' do
    it 'responde 404 com a flag desligada, também no relatório' do
      account.disable_features!('crm_numeros_origens')

      call(admin)
      expect(response).to have_http_status(:not_found)
      baixar(admin, 'pdf')
      expect(response).to have_http_status(:not_found)
    end

    it 'depende da visão "Equipe" nova: sem crm_numeros_equipe, 404' do
      account.disable_features!('crm_numeros_equipe')

      call(admin)

      expect(response).to have_http_status(:not_found)
    end

    it 'abre para quem vê a equipe e fecha para quem só tem "Só eu"' do
      call(role_user('crm_view_reports'))
      expect(response).to have_http_status(:ok)

      call(role_user('crm_view'))
      expect(response).to have_http_status(:unauthorized)
      call(create(:user, account: account, role: :agent))
      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa mês inválido' do
      call(admin, base, mes: '2026-13')

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'o funil' do
    let(:gestora) { role_user('crm_view_reports') }

    before do
      inbox.add_members([gestora.id])
      [vendas, suporte].each { |(funil, _)| Crm::PipelineInbox.create!(account: account, inbox: inbox, pipeline: funil) }
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: gestora, all_pipelines: false, triage: false,
                                             only_own: false)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    end

    it 'segue o acesso da pessoa: sem "Todos os funis", e funil que ela não vê é 403' do
      call(gestora)
      expect(response.parsed_body['funil']['opcoes'].pluck('id')).to eq([vendas.first.id.to_s])

      call(gestora, base, funil: suporte.first.id)
      expect(response).to have_http_status(:forbidden)
      baixar(gestora, 'planilha', funil: suporte.first.id)
      expect(response).to have_http_status(:forbidden)
    end

    it 'quem não vê todos e pede "todos" fica no funil principal, sem gasto' do
      call(gestora, base, funil: 'todos')

      expect(response.parsed_body['funil']['escolhido']).to eq(vendas.first.id.to_s)
      expect(response.parsed_body).to include('gasto' => nil, 'gastoEmTodos' => false, 'gastoOculto' => false)
    end

    it 'o administrador escolhe "Todos os funis"' do
      call(admin, base, funil: 'todos')

      expect(response.parsed_body['funil']['opcoes'].pluck('id')).to include('todos')
      expect(response.parsed_body['origens'].sum { |linha| linha['clientes'] }).to eq(3)
    end
  end

  describe 'gasto e valor' do
    it 'gasto só para quem vê os anúncios, e só em "Todos os funis"' do
      call(role_user('crm_view_reports', 'meta_ads_view'), base, funil: 'todos')
      expect(response.parsed_body['gasto']).to include('total' => 300.0, 'porVenda' => 300.0, 'toques' => 40)

      call(role_user('crm_view_reports'), base, funil: 'todos')
      expect(response.parsed_body).to include('gasto' => nil, 'gastoOculto' => true)
      expect(response.parsed_body['anuncios'].first.keys).not_to include('gasto', 'porVenda')

      call(admin)
      expect(response.parsed_body).to include('gasto' => nil, 'gastoEmTodos' => true)
    end

    it 'R$ de venda só com sales_value_view' do
      call(role_user('crm_view_reports', 'sales_value_view'))
      expect(response.parsed_body['origens'].first).to include('valor' => 1200.0)

      call(role_user('crm_view_reports', 'meta_ads_view'), base, funil: 'todos')
      expect(response.parsed_body).to include('valorOculto' => true)
      expect(response.parsed_body['origens'].pluck('valor').uniq).to eq([nil])
      expect(response.parsed_body['gasto']).to include('retorno' => nil)
    end
  end

  describe 'o relatório baixado' do
    it 'PDF com os números e os clientes para quem pode exportar o CRM' do
      baixar(admin, 'pdf', funil: 'todos', mes: '2026-10')

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.headers['Content-Disposition']).to include('attachment').and include('2026-10.pdf')
      expect(texto_do_pdf).to include('Oferta', 'Marina Souza', I18n.t('numeros_origens_report.numbers.spend'))
    end

    it 'sem crm_export: só os números, sem nenhum nome de cliente' do
      baixar(role_user('crm_view_reports', 'meta_ads_view', 'sales_value_view'), 'pdf', funil: 'todos')
      expect(texto_do_pdf).not_to include('Marina Souza', 'Paulo Lima', 'Rita Alves')

      baixar(role_user('crm_view_reports'), 'planilha', funil: 'todos')
      expect(abas.size).to eq(3)
      expect(abas).not_to include('Clientes')
    end

    it 'planilha leva o gasto só em "Todos os funis" e para quem vê os anúncios' do
      gasto = I18n.t('numeros_origens_report.summary.spend')

      baixar(admin, 'planilha', funil: 'todos')
      expect(celulas(0)).to include(gasto)
      expect(celulas(3)).to include('Marina Souza', 'Paulo Lima', 'Rita Alves')

      baixar(admin, 'planilha')
      expect(celulas(0)).not_to include(gasto)
      expect(celulas(3)).not_to include('Rita Alves')

      baixar(role_user('crm_view_reports', 'crm_export'), 'planilha', funil: 'todos')
      expect(celulas(0)).not_to include(gasto, I18n.t('numeros_origens_report.summary.sales_value'))
    end

    it 'a lista de clientes leva só os cards que a pessoa vê' do
      allow(Crm::CardPolicy::Scope).to receive(:new).and_wrap_original do |original, *args|
        escopo = original.call(*args)
        allow(escopo).to(receive(:resolve).and_wrap_original { |resolve| resolve.call.where.not(title: 'Card de Paulo Lima') })
        escopo
      end

      baixar(admin, 'planilha')

      expect(celulas(3)).to include('Marina Souza')
      expect(celulas(3)).not_to include('Paulo Lima')
    end

    it 'formato desconhecido: 422' do
      baixar(admin, 'docx')

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
