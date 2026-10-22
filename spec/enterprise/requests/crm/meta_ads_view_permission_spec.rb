require 'rails_helper'

# Funções personalizadas, lote 2 (#1794): `meta_ads_view` vê os Anúncios da Meta sem ser administrador.
# - Ver: conexão, painel, anúncio por dentro, listas do caminho, IA do dia e o resumo no WhatsApp.
# - Conectar, configurar, desconectar e os gestos do consultor pedem meta_ads_manage (#2070, meta_ads_manage_permission_spec).
# - As listas que levam a uma conversa mostram só as conversas que a pessoa já veria (caixa, funil e função).
RSpec.describe 'Anúncios da Meta com meta_ads_view', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:dela) { create(:inbox, account: account) }
  let(:alheia) { create(:inbox, account: account) }
  let(:marketing) { pessoa_com(%w[meta_ads_view]) }

  before { enable_test_encryption! }

  def pessoa_com(permissions, caixas: [dela])
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixas.each { |caixa| caixa.add_members([user.id]) }
    user
  end

  describe 'antes: sem a chave' do
    it 'recusa ver a conexão' do
      get path, headers: auth_headers(pessoa_com(%w[crm_view campaign_manage])), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'o que meta_ads_view vê' do
    it 'vê a conexão sem o token' do
      create_meta_ads_connection(account)

      get path, headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => true, 'status' => 'active')
      expect(response.body).not_to include(MetaAdsHelpers::TEST_TOKEN)
    end

    it 'vê o painel com o consultor' do
      connection = create_meta_ads_insights_connection(account)
      connection.update!(insights_backfilled_at: 1.day.ago, links_backfilled_at: 1.day.ago)

      get "#{path}/panel", params: { days: 7 }, headers: auth_headers(marketing)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('panel', 'advice', 'actions')).to be_present
    ensure
      Crm::MetaAds::Insights::Refresh.release(connection.id, 'today')
    end

    it 'pede a IA do dia' do
      post "#{path}/daily_action", headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('daily_action' => nil)
    end
  end

  describe 'o que pede meta_ads_manage' do
    before { create_meta_ads_insights_connection(account) }

    it 'não conecta' do
      put path, params: { access_token: 'EAAGoutro' }, headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'não desconecta' do
      delete path, headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to exist
    end

    it 'não troca para onde os anúncios levam' do
      patch "#{path}/destinations", params: { whatsapp: true }, headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'não lê nem configura o resumo no WhatsApp (traz o telefone de quem recebe)' do
      get "#{path}/whatsapp_report", headers: auth_headers(marketing), as: :json
      expect(response).to have_http_status(:forbidden)

      patch "#{path}/whatsapp_report", params: { enabled: true }, headers: auth_headers(marketing), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'não lista contas, Pixels e funis nem pede a leitura avulsa' do
      [[:get, 'ad_accounts?mode=token'], [:get, 'pixels?mode=token&ad_account_id=1'], [:get, 'funnels'], [:post, 'insights']].each do |verbo, rota|
        public_send(verbo, "#{path}/#{rota}", headers: auth_headers(marketing), as: :json)

        expect(response).to have_http_status(:forbidden), rota
      end
    end

    it 'não age sobre o consultor' do
      %w[open accept dismiss].each do |gesto|
        post "#{path}/advisor_actions/1/#{gesto}", headers: auth_headers(marketing), as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'listas que levam a uma conversa' do
    let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
    let(:quote_stage) do
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1, metadata: { 'funnel_stage_type' => 'opportunity' })
    end
    let(:atende) { pessoa_com(%w[meta_ads_view conversation_manage]) }

    def proposta(connection, caixa, titulo, touch_key)
      conversation = create(:conversation, account: account, inbox: caixa)
      Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: touch_key, origin: 'whatsapp', certainty: 'ad',
                              ad_id: '1', ad_account_id: connection.ad_account_id, touched_at: 2.days.ago)
      Crm::Card.create!(account: account, pipeline: pipeline, stage: quote_stage, title: titulo, currency: 'BRL',
                        primary_conversation: conversation, value_cents: 150_000, last_message_at: 5.days.ago)
      conversation
    end

    it 'o caminho do dinheiro mostra só as conversas da caixa da pessoa; o administrador vê todas' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        da_caixa = proposta(connection, dela, 'Cotação Ana', 'k1')
        proposta(connection, alheia, 'Cotação Bruno', 'k2')

        get "#{path}/panel_list", params: { step: 'quotes', days: 7 }, headers: auth_headers(atende)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['list']).to include('total' => 1)
        expect(response.parsed_body['list']['items'].pluck('conversation_id')).to eq([da_caixa.id])

        get "#{path}/panel_list", params: { step: 'quotes', days: 7 }, headers: auth_headers(admin)

        expect(response.parsed_body['list']['items'].pluck('title')).to contain_exactly('Cotação Ana', 'Cotação Bruno')
      end
    end

    it 'sem chave de conversa, a lista vem vazia, como na lista de conversas' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        proposta(connection, dela, 'Cotação Ana', 'k1')

        get "#{path}/panel_list", params: { step: 'quotes', days: 7 }, headers: auth_headers(marketing)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['list']).to include('total' => 0, 'items' => [])
      end
    end

    it 'na caixa "só as atribuídas" do CRM, só as conversas atribuídas à pessoa' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        Crm::InboxSetting.create!(account: account, inbox: dela, visibility_mode: :assigned_only)
        minha = proposta(connection, dela, 'Cotação Ana', 'k1')
        minha.update!(assignee: atende)
        proposta(connection, dela, 'Cotação Carla', 'k2')

        get "#{path}/panel_list", params: { step: 'quotes', days: 7 }, headers: auth_headers(atende)

        expect(response.parsed_body['list']['items'].pluck('conversation_id')).to eq([minha.id])
      end
    end

    it 'o anúncio por dentro lista só as propostas da caixa da pessoa' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        da_caixa = proposta(connection, dela, 'Cotação Ana', 'k1')
        proposta(connection, alheia, 'Cotação Bruno', 'k2')

        get "#{path}/panel_ad", params: { ad_id: '1', days: 7 }, headers: auth_headers(atende)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('ad', 'quotes_list').pluck('conversation_id')).to eq([da_caixa.id])
        expect(response.parsed_body.dig('ad', 'conversations')).to eq(2)
      end
    end
  end

  # Anúncios sem login (#1960): o painel do WhatsApp segue as mesmas regras de quem só olha.
  describe 'sem login' do
    def de_anuncio(caixa)
      conversation = create(:conversation, account: account, inbox: caixa)
      click = { 'source' => 'meta_ctwa', 'source_id' => '120254710362980416', 'touched_at' => 1.day.ago.utc.iso8601 }
      conversation.update_columns(additional_attributes: { 'campaign_touches' => [click] }) # rubocop:disable Rails/SkipsModelValidations
      conversation
    end

    before do
      account.enable_features!('anuncios_sem_login')
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    end

    it 'vê o resultado e, nas listas, só as conversas da caixa dela' do
      atende = pessoa_com(%w[meta_ads_view conversation_manage])
      minha = de_anuncio(dela)
      de_anuncio(alheia)

      get "#{path}/panel", headers: auth_headers(atende)
      expect(response.parsed_body.dig('panel', 'source')).to eq('whatsapp')

      get "#{path}/panel_list", params: { step: 'conversations' }, headers: auth_headers(atende)
      expect(response.parsed_body['list']['items'].pluck('conversation_id')).to eq([minha.id])

      get "#{path}/panel_ad", params: { ad_id: '120254710362980416' }, headers: auth_headers(atende)
      expect(response.parsed_body.dig('ad', 'people').pluck('conversation_id')).to eq([minha.id])
    end

    it 'com crm_export, baixa o relatório com os totais da conta e, na lista de conversas, só as da caixa dela' do
      atende = pessoa_com(%w[meta_ads_view conversation_manage crm_view crm_export])
      de_anuncio(dela).contact.update!(name: 'Pessoa da caixa dela')
      de_anuncio(alheia).contact.update!(name: 'Pessoa da outra caixa')

      get "#{path}/report", params: { formato: 'planilha' }, headers: auth_headers(atende)

      expect(response).to have_http_status(:ok)
      planilha = Roo::Excelx.new(StringIO.new(response.body))
      celulas = ->(aba) { (1..planilha.sheet(aba).last_row).flat_map { |linha| planilha.sheet(aba).row(linha) } }
      expect(celulas.call(0)).to include(I18n.t('meta_ads_report.summary.conversations'), 2)
      expect(celulas.call(2)).to include('Pessoa da caixa dela')
      expect(celulas.call(2)).not_to include('Pessoa da outra caixa')
    end

    # Lista de pessoas no arquivo é dado pessoal em lote: pede crm_export, como a planilha da Lista do CRM.
    it 'sem crm_export, baixa só os números: nenhuma aba nem nome de contato' do
      atende = pessoa_com(%w[meta_ads_view conversation_manage])
      de_anuncio(dela).contact.update!(name: 'Pessoa da caixa dela')

      get "#{path}/report", params: { formato: 'planilha' }, headers: auth_headers(atende)
      planilha = Roo::Excelx.new(StringIO.new(response.body))
      celulas = planilha.sheets.flat_map do |aba|
        (1..planilha.sheet(aba).last_row.to_i).flat_map { |linha| planilha.sheet(aba).row(linha) }
      end
      expect(planilha.sheets.size).to eq(3)
      expect(celulas).to include(I18n.t('meta_ads_report.summary.conversations'), 1)
      expect(celulas).not_to include('Pessoa da caixa dela')

      get "#{path}/report", params: { formato: 'pdf' }, headers: auth_headers(atende)
      texto = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(response).to have_http_status(:ok)
      expect(texto).not_to include('Pessoa da caixa dela')
    end
  end
end
