require 'rails_helper'

# #2271 (decisões do Rodrigo, 27/10): a função personalizada sem `meta_ads_view` (nem `meta_ads_manage`) vê no card do CRM
# só que o cliente veio de anúncio, por onde e quando. Título, nomes, prévia, miniatura, endereço, UTMs e id do
# anúncio não saem do servidor: lista, quadro, detalhe e tempo real. Administrador e agente sem função personalizada veem
# tudo, como no valor de venda (#2075). Toque que não é anúncio não muda.
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

    it "#{superficie}: meta_ads_view, meta_ads_manage, administrador e agente sem função veem o anúncio inteiro" do
      [com_view, com_manage, admin, plain_agent].each do |user|
        anuncio = campanhas(superficie, user).find { |toque| toque['source_id'] == '120200000000000001' }

        expect(anuncio).to include('headline' => 'Título do anúncio X', 'ad_name' => 'Anúncio Carrossel',
                                   'campaign_name' => 'Campanha Primavera', 'adset_name' => 'Grupo Sul',
                                   'ad_thumbnail_url' => 'https://thumb.example/ad.jpg',
                                   'ad_preview_url' => 'https://preview.example/ad')
        expect(anuncio).not_to have_key('ad_hidden')
      end
    end
  end

  describe 'planilha' do
    # Mais dois cards: um cujo primeiro toque é o anúncio da Meta com todos os campos, e um cujo primeiro toque é antigo,
    # gravado como link, mas com as UTMs pagas da Meta (o anúncio só aparece pela regra de "pago" refeita). A planilha
    # tem várias linhas e cada uma passa pela regra.
    def card_com_toque(titulo, toque)
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contato)
      outra.update!(additional_attributes: { campaign_touches: [toque] })
      account.crm_cards.create!(pipeline: card.pipeline, stage: card.stage, inbox: inbox, contact: contato, owner: admin,
                                primary_conversation: outra, title: titulo)
    end

    before do
      card_com_toque('Outro negócio com anúncio', conversa.additional_attributes['campaign_touches'][0])
      card_com_toque('Negócio de link antigo', { 'source' => 'tracked_link', 'source_type' => 'tracked_link',
                                                 'source_id' => 'site:AB:1', 'headline' => 'LP · Campanha Primavera',
                                                 'utm_source' => 'facebook', 'utm_medium' => 'cpc',
                                                 'utm_campaign' => 'utm-campanha-x', 'source_url' => 'https://fb.me/anuncio-x',
                                                 'touched_at' => '2026-09-15T12:00:00Z' })
    end

    def planilha_de(user)
      get "#{crm}/cards/export", params: { pipeline_id: card.pipeline_id }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      planilha = Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
      linhas = ((Crm::Cards::XlsxExport::HEADER_ROW + 1)..planilha.last_row).map { |linha| planilha.row(linha) }
      coluna = Crm::Cards::XlsxExport::COLUMNS.index(:campaign)
      [linhas, linhas.to_h { |linha| [linha.first, linha[coluna]] }]
    end

    it 'sem a chave: nenhuma célula de nenhuma linha traz o anúncio; a Origem diz só por onde veio' do
      exportador = pessoa_com(base + %w[crm_export])
      inbox.add_members([exportador.id])
      linhas, origens = planilha_de(exportador)

      expect(origens).to eq('Negócio com anúncio' => 'meta_ctwa', 'Outro negócio com anúncio' => 'meta_ctwa',
                            'Negócio de link antigo' => 'meta_paid')
      expect(linhas.flatten.compact.map(&:to_s).join("\n")).not_to include(*identificadores)
    end

    it 'administrador: a Origem traz o anúncio do primeiro toque de cada card' do
      _linhas, origens = planilha_de(admin)

      expect(origens).to eq('Negócio com anúncio' => 'Anúncio antigo sem origem',
                            'Outro negócio com anúncio' => 'meta_ctwa — Título do anúncio X',
                            'Negócio de link antigo' => 'tracked_link — LP · Campanha Primavera')
    end
  end

  # O toque gravado antes de a regra de "pago" mudar ficou com outra origem; a regra de hoje do próprio
  # Ctwa::CampaignBuilder.source_for, refeita sobre o toque, ainda o reconhece como anúncio.
  it 'toque gravado com outra origem, mas com sinal de anúncio pela regra do código, também é escondido' do
    conversa.update!(additional_attributes: { campaign_touches: [
                       { source: 'tracked_link', source_type: 'tracked_link', source_id: 'site:AB:1', headline: 'LP · Campanha Primavera',
                         utm_source: 'facebook', utm_medium: 'cpc', utm_campaign: 'utm-campanha-x',
                         source_url: 'https://fb.me/anuncio-x', touched_at: '2026-10-01T12:00:00Z' },
                       { source: 'meta_organic', source_type: 'ad', source_id: '120200000000000001',
                         headline: 'Título do anúncio X', touched_at: '2026-10-02T12:00:00Z' },
                       { source: 'tracked_link', source_type: 'tracked_link', source_id: 'site:AB:2', headline: 'Grupo Sul',
                         fbclid: 'fb-1', touched_at: '2026-10-03T12:00:00Z' }
                     ] })

    toques = campanhas(:cards, sem_chave)

    expect(toques.pluck('source', 'ad_hidden')).to eq([['meta_paid', true], ['meta_ctwa', true], ['meta_paid', true]])
    expect(response.body).not_to include(*identificadores)
    expect(campanhas(:cards, admin).pluck('headline')).to eq(['LP · Campanha Primavera', 'Título do anúncio X', 'Grupo Sul'])
  end

  # Origem explícita que não é anúncio fica como foi gravada: a regra de "pago" só é refeita sobre o toque sem origem,
  # link ou publicação. A divulgação clicada a partir do Facebook (fbclid, UTM da Meta paga) continua visível.
  it 'divulgação com fbclid ou UTM da Meta continua visível para quem não tem a chave' do
    conversa.update!(additional_attributes: { campaign_touches: [
                       { source: 'campaign_whatsapp', source_type: 'campaign_whatsapp', source_id: 'divulgacao-1',
                         headline: 'Divulgação de outubro', fbclid: 'fb-1', utm_source: 'facebook', utm_medium: 'cpc',
                         utm_campaign: 'outubro', touched_at: '2026-10-03T12:00:00Z' },
                       { source: 'campaign_email', source_type: 'campaign_email', source_id: 'email-1',
                         headline: 'E-mail de outubro', fbclid: 'fb-2', touched_at: '2026-10-04T12:00:00Z' }
                     ] })

    toques = campanhas(:cards, sem_chave)

    expect(toques.pluck('source', 'headline', 'source_id', 'utm_campaign'))
      .to eq([['campaign_whatsapp', 'Divulgação de outubro', 'divulgacao-1', 'outubro'],
              ['campaign_email', 'E-mail de outubro', 'email-1', nil]])
    expect(toques).to all(satisfy { |toque| !toque.key?('ad_hidden') })
  end

  it 'tempo real: cada destinatário recebe o card com o anúncio que a chave dele permite' do
    enviados = {}
    allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _evento, dados|
      enviados[tokens.first] = dados[:campaigns]
    end

    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)

    expect(enviados.fetch(sem_chave.pubsub_token).pluck(:headline)).to eq([nil, nil, nil, 'Divulgação de outubro'])
    expect(enviados.fetch(sem_chave.pubsub_token).to_json).not_to include(*identificadores)
    [com_view, com_manage, admin, plain_agent].each do |user|
      expect(enviados.fetch(user.pubsub_token).pluck(:headline))
        .to eq(['Anúncio antigo sem origem', 'Título do anúncio X', 'Anúncio do Google Y', 'Divulgação de outubro'])
    end
  end
end
