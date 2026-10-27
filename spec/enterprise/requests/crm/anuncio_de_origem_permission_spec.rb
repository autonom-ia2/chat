require 'rails_helper'

# #2271 (decisão do Rodrigo, 27/10): sem `meta_ads_view` (ou `meta_ads_manage`; administrador vê tudo), o card do CRM
# diz só que o cliente veio de anúncio, por onde e quando. Título, nomes, prévia, miniatura, endereço, UTMs e id do
# anúncio não saem do servidor: lista, quadro, detalhe e tempo real. Toque que não é anúncio não muda.
RSpec.describe 'Anúncio de origem no card com meta_ads_view (#2271)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:sem_chave) { pessoa_com(base) }
  let(:com_view) { pessoa_com(base + %w[meta_ads_view]) }
  let(:com_manage) { pessoa_com(base + %w[meta_ads_manage]) }
  let(:plain_agent) { create_crm_agent(account: account).first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_view, com_manage, plain_agent]) }
  let(:contato) { account.contacts.create!(name: 'Cliente Teste', phone_number: '+5511900001111') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let!(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, inbox: inbox, contact: contato,
                              owner: admin, primary_conversation: conversa, title: 'Negócio com anúncio')
  end

  # Textos que identificam o anúncio: nenhum pode aparecer na resposta de quem não tem a chave.
  let(:identificadores) do
    [
      'Título do anúncio X', 'Campanha Primavera', 'Grupo Sul', 'Anúncio Carrossel', '120200000000000001',
      'https://fb.me/anuncio-x', 'https://preview.example/ad', 'https://thumb.example/ad.jpg', 'utm-campanha-x',
      'Anúncio antigo sem origem', 'Anúncio do Google Y'
    ]
  end

  before do
    conversa.update!(additional_attributes: { campaign_touches: [
                       { source: 'meta_ctwa', source_id: '120200000000000001', source_type: 'ad', headline: 'Título do anúncio X',
                         source_url: 'https://fb.me/anuncio-x', campaign_name: 'Campanha Primavera', adset_name: 'Grupo Sul',
                         ad_name: 'Anúncio Carrossel', ad_preview_url: 'https://preview.example/ad',
                         ad_thumbnail_url: 'https://thumb.example/ad.jpg', utm_campaign: 'utm-campanha-x', ctwa_clid: 'clid-1',
                         touched_at: '2026-10-01T12:00:00Z' },
                       # Toque antigo, gravado antes de `source` existir: a origem sai da regra do próprio toque.
                       { source_id: 'antigo-1', source_type: 'ad', headline: 'Anúncio antigo sem origem', ctwa_clid: 'clid-0',
                         touched_at: '2026-09-01T12:00:00Z' },
                       { source: 'google_ads', source_id: 'g-1', headline: 'Anúncio do Google Y', gclid: 'g',
                         touched_at: '2026-10-02T12:00:00Z' },
                       { source: 'campaign_whatsapp', source_id: 'divulgacao-1', headline: 'Divulgação de outubro',
                         touched_at: '2026-10-03T12:00:00Z' }
                     ] })
  end

  def base = %w[crm_view crm_manage_cards contact_view conversation_manage]
  def crm = "/api/v1/accounts/#{account.id}/crm"

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def ler(path, user)
    get "#{crm}/#{path}", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload']
  end

  def campanhas(superficie, user)
    payload = ler(superficie == :detalhe ? "cards/#{card.id}" : superficie.to_s, user)
    linha = case superficie
            when :detalhe then payload
            when :cards then payload.find { |item| item['id'] == card.id }
            else payload['stages'].flat_map { |coluna| coluna['cards'] }.find { |item| item['id'] == card.id }
            end
    linha.fetch('campaigns')
  end

  def anuncio_oculto(source, touched_at)
    {
      'source' => source, 'source_type' => 'ad', 'touched_at' => touched_at, 'conversation_id' => conversa.id,
      'ad_hidden' => true, 'source_id' => nil, 'headline' => nil, 'source_url' => nil, 'campaign_name' => nil,
      'adset_name' => nil, 'ad_name' => nil, 'ad_preview_url' => nil, 'ad_thumbnail_url' => nil, 'utm_campaign' => nil
    }
  end

  %i[cards kanban detalhe].each do |superficie|
    it "#{superficie}: sem a chave, o toque de anúncio diz só que veio de anúncio; a divulgação continua com o nome" do
      toques = campanhas(superficie, sem_chave)

      expect(toques.size).to eq(4)
      expect(toques[0]).to include(anuncio_oculto('meta_ctwa', '2026-09-01T12:00:00Z'))
      expect(toques[1]).to include(anuncio_oculto('meta_ctwa', '2026-10-01T12:00:00Z'))
      expect(toques[2]).to include(anuncio_oculto('google_ads', '2026-10-02T12:00:00Z').merge('source_type' => nil))
      expect(toques[3]).to include('source' => 'campaign_whatsapp', 'headline' => 'Divulgação de outubro')
      expect(toques[3]).not_to have_key('ad_hidden')
      expect(response.body).not_to include(*identificadores)
    end

    it "#{superficie}: agente sem função também não vê o anúncio" do
      campanhas(superficie, plain_agent)

      expect(response.body).not_to include(*identificadores)
    end

    it "#{superficie}: meta_ads_view, meta_ads_manage e administrador veem o anúncio inteiro" do
      [com_view, com_manage, admin].each do |user|
        anuncio = campanhas(superficie, user).find { |toque| toque['source_id'] == '120200000000000001' }

        expect(anuncio).to include('headline' => 'Título do anúncio X', 'ad_name' => 'Anúncio Carrossel',
                                   'campaign_name' => 'Campanha Primavera', 'adset_name' => 'Grupo Sul',
                                   'ad_thumbnail_url' => 'https://thumb.example/ad.jpg',
                                   'ad_preview_url' => 'https://preview.example/ad')
        expect(anuncio).not_to have_key('ad_hidden')
      end
    end
  end

  it 'planilha: sem a chave, a coluna Origem traz só por onde veio' do
    exportador = pessoa_com(base + %w[crm_export])
    inbox.add_members([exportador.id])
    get "#{crm}/cards/export", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(exportador)

    expect(response).to have_http_status(:ok)
    planilha = Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
    coluna = Crm::Cards::XlsxExport::COLUMNS.index(:campaign) + 1
    expect(planilha.cell(Crm::Cards::XlsxExport::HEADER_ROW + 1, coluna)).to eq('meta_ctwa')
  end

  it 'tempo real: cada destinatário recebe o card com o anúncio que a chave dele permite' do
    enviados = {}
    allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _evento, dados|
      enviados[tokens.first] = dados[:campaigns]
    end

    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)

    [sem_chave, plain_agent].each do |user|
      expect(enviados.fetch(user.pubsub_token).pluck(:headline)).to eq([nil, nil, nil, 'Divulgação de outubro'])
      expect(enviados.fetch(user.pubsub_token).to_json).not_to include(*identificadores)
    end
    [com_view, com_manage, admin].each do |user|
      expect(enviados.fetch(user.pubsub_token).pluck(:headline))
        .to eq(['Anúncio antigo sem origem', 'Título do anúncio X', 'Anúncio do Google Y', 'Divulgação de outubro'])
    end
  end
end
