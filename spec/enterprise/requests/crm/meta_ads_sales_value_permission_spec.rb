require 'rails_helper'

# Valores de venda em R$ nos Anúncios e na CTWA (#2075, lote 13): seguem `sales_value_view` (Crm::ValorDeVenda).
# - Painel e relatório baixado: sem a chave, o dinheiro dos cards sai; gasto, custo e contagens ficam.
# - Resumo no WhatsApp: ligar/mudar e testar pedem a chave (o texto leva o valor vendido).
# - Links de página: as vendas contam só os cards que a pessoa vê no CRM; o valor, só com a chave.
# - De onde vieram (Números): o valor por origem só com a chave; a contagem fica.
RSpec.describe 'Valores de venda nos Anúncios com funções personalizadas', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  def pessoa_com(account, permissions, caixas: [])
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixas.each { |caixa| caixa.add_members([user.id]) }
    user
  end

  describe 'painel e relatório de Anúncios' do
    let(:now) { Time.zone.parse('2026-10-07T15:00:00-03:00') }
    let!(:setup) { advisor_setup }
    let(:account) { setup.first }
    let(:connection) { setup.last }
    let(:inbox) { account.inboxes.sole }
    let(:admin) { AccountUser.find_by!(account: account, role: :administrator).user }
    let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }

    around { |example| travel_to(now) { example.run } }

    before do
      advisor_insights(ad_id: 'A', adset_id: 'SA', from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 6), spend: 60, impressions: 6_000,
                       link_clicks: 60)
      chats = advisor_conversations(ad_id: 'A', count: 2, from: Date.new(2026, 10, 5), to: Date.new(2026, 10, 6))
      advisor_stalled_quote(chats[0], waiting_days: 5)
      advisor_sale(chats[1])
      Redis::Alfred.delete(advisor_facts_key(connection, connection.ad_account_today))
    end

    after { Crm::MetaAds::Insights::Refresh.release(connection.id, 'today') }

    def totais(user)
      get "#{path}/panel", params: { period: '30d' }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      response.parsed_body.dig('panel', 'totals')
    end

    def planilha(user)
      get "#{path}/report", params: { formato: 'planilha', period: '30d' }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      arquivo = Roo::Excelx.new(StringIO.new(response.body))
      arquivo.sheets.flat_map { |aba| (1..arquivo.sheet(aba).last_row.to_i).flat_map { |linha| arquivo.sheet(aba).row(linha) } }
    end

    it 'meta_ads_view sem a chave: os totais sem o dinheiro dos cards, com gasto e contagens' do
      marketing = pessoa_com(account, %w[meta_ads_view], caixas: [inbox])

      expect(totais(marketing)).to include('sales' => 1, 'sales_value' => nil, 'return_per_real' => nil, 'open_value' => nil,
                                           'value_hidden' => true, 'spend' => 60.0, 'cost_per_sale' => 60.0)
      expect(response.parsed_body.dig('panel', 'ads').sole).to include('sales_value' => nil, 'value_hidden' => true, 'spend' => 60.0)
      stalled = response.parsed_body.dig('panel', 'advice', 'actions').find { |action| action['kind'] == 'stalled_quotes' }
      expect(stalled['facts']).not_to have_key('value')
    end

    it 'com sales_value_view, e o administrador, veem o valor' do
      com_chave = pessoa_com(account, %w[meta_ads_view sales_value_view], caixas: [inbox])

      [com_chave, admin].each do |user|
        expect(totais(user)).to include('sales_value' => 1000.0, 'return_per_real' => 16.67, 'open_value' => 1500.0)
        expect(totais(user)).not_to have_key('value_hidden')
      end
    end

    it 'a planilha sem a chave não traz o valor vendido nem a coluna de valor; com a chave, traz' do
      sem_chave = pessoa_com(account, %w[meta_ads_view conversation_manage crm_view crm_export], caixas: [inbox])
      com_chave = pessoa_com(account, %w[meta_ads_view conversation_manage crm_view crm_export sales_value_view], caixas: [inbox])
      rotulos = [I18n.t('meta_ads_report.summary.sales_value'), I18n.t('meta_ads_report.columns.sales_value'),
                 I18n.t('meta_ads_report.columns.value')]

      expect(planilha(sem_chave)).not_to include(*rotulos)
      expect(planilha(sem_chave)).to include(I18n.t('meta_ads_report.summary.sales'), I18n.t('meta_ads_report.summary.spend'))
      expect(planilha(com_chave)).to include(*rotulos)
    end

    it 'o PDF sem a chave não traz o valor vendido' do
      sem_chave = pessoa_com(account, %w[meta_ads_view], caixas: [inbox])

      get "#{path}/report", params: { formato: 'pdf', period: '30d' }, headers: auth_headers(sem_chave)
      texto = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")

      expect(response).to have_http_status(:ok)
      expect(texto).not_to include('1.000', '1,000')
      expect(texto).to include('60')
    end
  end

  describe 'resumo no WhatsApp' do
    let(:account) { create(:account) }
    let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/whatsapp_report" }

    before do
      account.enable_features!('meta_ads_hub')
      create_meta_ads_insights_connection(account)
    end

    it 'meta_ads_manage sem a chave lê, mas não liga nem testa (403)' do
      gestor = pessoa_com(account, %w[meta_ads_manage])

      get path, headers: auth_headers(gestor), as: :json
      expect(response).to have_http_status(:ok)

      patch path, params: { whatsapp_report: { alert_enabled: false } }, headers: auth_headers(gestor), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'sales_value_forbidden')

      post "#{path}/test", headers: auth_headers(gestor), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'sales_value_forbidden')
    end

    it 'com a chave, muda a configuração' do
      gestor = pessoa_com(account, %w[meta_ads_manage sales_value_view])

      patch path, params: { whatsapp_report: { alert_enabled: false } }, headers: auth_headers(gestor), as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'links de página (CTWA)' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, :administrator, account: account) }
    let(:dela) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
    let(:alheia) { create(:inbox, account: account) }
    let(:tracked_link) do
      Ctwa::TrackedLink.create!(account: account, inbox: dela, name: 'LP', code: 'ABC234', usage: 'website',
                                allowed_origins: ['https://placement.com.br'])
    end

    before do
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      [[dela, 37_780], [alheia, 113_340]].each do |caixa, cents|
        conversation = create(:conversation, account: account, inbox: caixa)
        create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, params: { 'utm_id' => '1' }, campaign_key: '1',
                                         conversation: conversation)
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', conversation_id: conversation.id, inbox_id: caixa.id,
                                  contact_id: conversation.contact_id, status: :won, value_cents: cents, currency: 'BRL')
      end
    end

    def campanha(user)
      get "/api/v1/accounts/#{account.id}/ctwa_tracked_links", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      response.parsed_body['payload'].find { |link| link['id'] == tracked_link.id }['campaigns'].sole
    end

    it 'sem a chave: conta só as vendas dos cards que vê no CRM, sem o valor' do
      campanha = campanha(pessoa_com(account, %w[campaign_view], caixas: [dela]))

      expect(campanha).to include('conversations' => 2, 'won_cards' => 1)
      expect(campanha).not_to have_key('won_value_by_currency')
    end

    it 'com a chave: o valor só dos cards que vê no CRM' do
      campanha = campanha(pessoa_com(account, %w[campaign_view sales_value_view], caixas: [dela]))

      expect(campanha).to include('won_cards' => 1, 'won_value_by_currency' => { 'BRL' => 37_780 })
    end

    it 'o administrador vê todas as vendas e o valor' do
      expect(campanha(admin)).to include('won_cards' => 2, 'won_value_by_currency' => { 'BRL' => 151_120 })
    end
  end

  describe 'de onde vieram (Números)' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, :administrator, account: account) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      conversation = create(:conversation, account: account, inbox: inbox)
      touch = { 'source_id' => 'ad-a', 'source' => 'meta_ctwa', 'touched_at' => 2.days.ago.utc.iso8601 }
      conversation.update!(additional_attributes: { 'campaign' => touch, 'campaign_touches' => [touch] })
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Venda', primary_conversation: conversation, inbox: inbox,
                                       contact: conversation.contact, value_cents: 12_000, currency: 'BRL')
      card.update!(status: :won)
    end

    def origens(user)
      get "/api/v1/accounts/#{account.id}/ctwa_campaigns", params: { include_origin_metrics: true }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      response.parsed_body['origin_metrics']
    end

    it 'sem a chave, a contagem fica e o valor vem nil; com a chave, o valor' do
      sem_chave = pessoa_com(account, %w[crm_view crm_view_reports conversation_manage], caixas: [inbox])
      com_chave = pessoa_com(account, %w[crm_view crm_view_reports conversation_manage sales_value_view], caixas: [inbox])

      expect(origens(sem_chave)).to eq([{ 'source' => 'meta_ctwa', 'won_count' => 1, 'won_value_by_currency' => nil }])
      expect(origens(com_chave)).to eq([{ 'source' => 'meta_ctwa', 'won_count' => 1,
                                          'won_value_by_currency' => [{ 'currency' => 'BRL', 'value_cents' => 12_000 }] }])
    end
  end
end
