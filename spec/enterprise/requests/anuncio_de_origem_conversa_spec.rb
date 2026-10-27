require 'rails_helper'

# #2271 (decisões do Rodrigo, 27/10), fora do card: a função personalizada sem `meta_ads_view` (nem `meta_ads_manage`)
# não recebe o anúncio de origem também
# - na conversa (additional_attributes.campaign, campaign_touches e o espelho campaign_source_ids), em lista, detalhe,
#   mensagens, busca, notificações, "Origem e campanhas" do contato e tempo real;
# - nas opções do filtro por campanha (GET /ctwa_campaigns, que serve ao CRM e às Conversas);
# - no filtro campaign_source_ids do CRM, que descarta só os ids de anúncio e continua filtrando pela divulgação.
# Administrador, agente sem função e função com a chave veem tudo. O referral da MENSAGEM (balão) continua igual.
RSpec.describe 'Anúncio de origem na conversa, no picker e no filtro (#2271)', :aggregate_failures, type: :request do
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
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_view, com_manage, plain_agent]) }
  let(:contato) { account.contacts.create!(name: 'Cliente Teste', phone_number: '+5511900003333') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }

  let!(:conversa_anuncio) do
    conversa = create_crm_conversation(account: account, inbox: inbox, contact: contato)
    conversa.update!(additional_attributes: {
                       'campaign' => toque_anuncio.merge('body' => 'Texto do anúncio'),
                       'campaign_touches' => [toque_anuncio, toque_divulgacao],
                       'campaign_source_ids' => %w[120200000000000001 divulgacao-1]
                     })
    conversa
  end
  let!(:conversa_divulgacao) do
    outro = account.contacts.create!(name: 'Outra Pessoa', phone_number: '+5511900004444')
    conversa = create_crm_conversation(account: account, inbox: inbox, contact: outro)
    conversa.update!(additional_attributes: { 'campaign_touches' => [toque_divulgacao], 'campaign_source_ids' => %w[divulgacao-1] })
    conversa
  end
  # O balão do anúncio na mensagem fica como está.
  let!(:mensagem) do
    conversa_anuncio.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: contato, content: 'Olá',
                                      content_attributes: { 'referral' => { 'headline' => 'Título do anúncio X',
                                                                            'source_url' => 'https://fb.me/anuncio-x' } })
  end

  def toque_anuncio
    { 'source' => 'meta_ctwa', 'source_id' => '120200000000000001', 'source_type' => 'ad', 'headline' => 'Título do anúncio X',
      'source_url' => 'https://fb.me/anuncio-x', 'campaign_name' => 'Campanha Primavera', 'ad_name' => 'Anúncio Carrossel',
      'ad_thumbnail_url' => 'https://thumb.example/ad.jpg', 'ctwa_clid' => 'clid-secreto', 'touched_at' => '2026-10-01T12:00:00Z' }
  end

  def toque_divulgacao
    { 'source' => 'campaign_whatsapp', 'source_id' => 'divulgacao-1', 'source_type' => 'campaign_whatsapp',
      'headline' => 'Divulgação de outubro', 'touched_at' => '2026-10-02T12:00:00Z' }
  end

  def identificadores
    ['Título do anúncio X', '120200000000000001', 'https://fb.me/anuncio-x', 'Campanha Primavera', 'Anúncio Carrossel',
     'https://thumb.example/ad.jpg', 'clid-secreto', 'Texto do anúncio']
  end

  # O referral da mensagem (o balão) leva o título e o endereço do anúncio e fica como está: na resposta inteira, o resto
  # do anúncio não pode aparecer; nos additional_attributes, nada.
  def fora_do_referral = identificadores - ['Título do anúncio X', 'https://fb.me/anuncio-x']

  def base = %w[crm_view crm_manage_cards contact_view conversation_manage]
  def api = "/api/v1/accounts/#{account.id}"

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def ler(path, user, params = {})
    get "#{api}/#{path}", params: params, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def atributos_oculto
    {
      'campaign' => { 'source' => 'meta_ctwa', 'source_type' => 'ad', 'touched_at' => '2026-10-01T12:00:00Z', 'ad_hidden' => true },
      'campaign_touches' => [
        { 'source' => 'meta_ctwa', 'source_type' => 'ad', 'touched_at' => '2026-10-01T12:00:00Z', 'ad_hidden' => true },
        toque_divulgacao
      ],
      'campaign_source_ids' => %w[divulgacao-1]
    }
  end

  def atributos_da_lista(user)
    ler('conversations', user)['data']['payload'].find { |item| item['id'] == conversa_anuncio.display_id }['additional_attributes']
  end

  describe 'conversa' do
    it 'lista, detalhe e mensagens: sem a chave, a conversa vem sem o anúncio; o referral da mensagem fica' do
      atributos = atributos_da_lista(sem_chave)
      expect(atributos).to include(atributos_oculto)
      expect(atributos.to_json).not_to include(*identificadores)
      expect(response.body).not_to include(*fora_do_referral)

      expect(ler("conversations/#{conversa_anuncio.display_id}", sem_chave)['additional_attributes']).to include(atributos_oculto)
      expect(response.body).not_to include(*fora_do_referral)

      corpo = ler("conversations/#{conversa_anuncio.display_id}/messages", sem_chave)
      expect(corpo['meta']['additional_attributes']).to include(atributos_oculto)
      referral = corpo['payload'].find { |item| item['id'] == mensagem.id }['content_attributes']['referral']
      expect(referral).to eq('headline' => 'Título do anúncio X', 'source_url' => 'https://fb.me/anuncio-x')
    end

    it 'administrador, agente sem função, meta_ads_view e meta_ads_manage veem a conversa inteira' do
      [admin, plain_agent, com_view, com_manage].each do |user|
        atributos = atributos_da_lista(user)

        expect(atributos['campaign']).to include('headline' => 'Título do anúncio X', 'body' => 'Texto do anúncio')
        expect(atributos['campaign_touches'].first).to eq(toque_anuncio)
        expect(atributos['campaign_source_ids']).to eq(%w[120200000000000001 divulgacao-1])
      end
    end

    it 'busca: sem a chave, a conversa achada vem sem o anúncio' do
      corpo = ler('search/conversations', sem_chave, q: 'Cliente Teste')
      achada = corpo['payload']['conversations'].find { |item| item['id'] == conversa_anuncio.display_id }

      expect(achada['additional_attributes']).to include(atributos_oculto)
      expect(achada['additional_attributes'].to_json).not_to include(*identificadores)
      expect(response.body).not_to include(*fora_do_referral)
    end

    it 'notificações: sem a chave, a conversa da notificação vem sem o anúncio' do
      create(:notification, account: account, user: sem_chave, primary_actor: conversa_anuncio)
      create(:notification, account: account, user: com_view, primary_actor: conversa_anuncio)

      atributos = ler('notifications', sem_chave)['data']['payload'].first['primary_actor']['additional_attributes']
      expect(atributos).to include(atributos_oculto)
      expect(atributos.to_json).not_to include(*identificadores)
      expect(response.body).not_to include(*fora_do_referral)

      atributos = ler('notifications', com_view)['data']['payload'].first['primary_actor']['additional_attributes']
      expect(atributos['campaign_touches'].first).to eq(toque_anuncio)
    end

    it 'Origem e campanhas do contato: sem a chave, a marca do anúncio vem sem o anúncio' do
      marcas = ler("campaign_journey/contact_origins/#{contato.id}", sem_chave)['payload']['marks']

      expect(marcas.map { |marca| marca.except('conversation_display_id') }).to eq([
                                                                                     { 'source' => 'meta_ctwa', 'source_type' => 'ad',
                                                                                       'touched_at' => '2026-10-01T12:00:00Z', 'ad_hidden' => true },
                                                                                     toque_divulgacao
                                                                                   ])
      expect(response.body).not_to include(*identificadores)

      marcas = ler("campaign_journey/contact_origins/#{contato.id}", plain_agent)['payload']['marks']
      expect(marcas.first).to include('headline' => 'Título do anúncio X', 'source_id' => '120200000000000001')
    end

    it 'tempo real: o evento da conversa sai inteiro para quem vê e sem o anúncio para quem não vê' do
      envios = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) { |tokens, _evento, dados| envios << [tokens, dados] }

      ActionCableListener.instance.conversation_updated(
        Events::Base.new('conversation.updated', Time.zone.now, conversation: conversa_anuncio)
      )

      oculto = envios.find { |tokens, _dados| tokens.include?(sem_chave.pubsub_token) }
      inteiro = envios.find { |tokens, _dados| tokens.include?(plain_agent.pubsub_token) }
      expect(envios.size).to eq(2)
      expect(oculto.first).to eq([sem_chave.pubsub_token])
      expect(oculto.last[:additional_attributes]).to include(atributos_oculto)
      expect(oculto.last[:additional_attributes].to_json).not_to include(*identificadores)
      expect(oculto.last.to_json).not_to include(*fora_do_referral)
      expect(inteiro.first).to include(admin.pubsub_token, com_view.pubsub_token, com_manage.pubsub_token)
      expect(inteiro.last[:additional_attributes]['campaign_touches'].first).to eq(toque_anuncio)
    end

    it 'tempo real: conversa sem toque sai num envio só, como antes' do
      sem_toque = create_crm_conversation(account: account, inbox: inbox, contact: contato)
      envios = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) { |tokens, _evento, dados| envios << [tokens, dados] }

      ActionCableListener.instance.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now, conversation: sem_toque))

      expect(envios.size).to eq(1)
      expect(envios.first.first).to include(sem_chave.pubsub_token, plain_agent.pubsub_token)
    end
  end

  describe 'opções do filtro por campanha (GET /ctwa_campaigns)' do
    def opcoes(user)
      ler('ctwa_campaigns', user)['payload'].pluck('source_id')
    end

    it 'sem a chave: só a divulgação, sem nada do anúncio' do
      expect(opcoes(sem_chave)).to eq(['divulgacao-1'])
      expect(response.body).not_to include('Título do anúncio X', '120200000000000001')
    end

    it 'administrador, agente sem função e quem tem a chave: anúncio e divulgação' do
      [admin, plain_agent, com_view, com_manage].each do |user|
        expect(opcoes(user)).to contain_exactly('120200000000000001', 'divulgacao-1')
      end
    end
  end

  describe 'filtro campaign_source_ids do CRM' do
    before do
      criar_card('Card do anúncio', conversa_anuncio)
      criar_card('Card da divulgação', conversa_divulgacao)
      criar_card('Card sem origem', create_crm_conversation(account: account, inbox: inbox, contact: contato))
      so_anuncio = create_crm_conversation(account: account, inbox: inbox, contact: contato)
      so_anuncio.update!(additional_attributes: { 'campaign_touches' => [toque_anuncio], 'campaign_source_ids' => %w[120200000000000001] })
      criar_card('Card só do anúncio', so_anuncio)
    end

    def criar_card(titulo, conversa)
      account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, inbox: inbox,
                                contact: conversa.contact, owner: admin, primary_conversation: conversa, title: titulo)
    end

    def titulos(superficie, user, ids)
      corpo = ler("crm/#{superficie}", user, pipeline_id: pipeline_and_stage.first.id, campaign_source_ids: ids)['payload']
      cards = superficie == 'kanban' ? corpo['stages'].flat_map { |coluna| coluna['cards'] } : corpo
      cards.pluck('title')
    end

    %w[cards kanban].each do |superficie|
      it "#{superficie}: filtro misto sem a chave descarta o anúncio e continua filtrando pela divulgação" do
        # O card do anúncio também tem o toque da divulgação e bate por ela; o card só do anúncio sai.
        expect(titulos(superficie, sem_chave, '120200000000000001,divulgacao-1'))
          .to contain_exactly('Card do anúncio', 'Card da divulgação')
        expect(titulos(superficie, sem_chave, 'divulgacao-1')).to contain_exactly('Card do anúncio', 'Card da divulgação')
      end

      it "#{superficie}: só o anúncio, sem a chave, o filtro é ignorado (não revela qual card veio dele)" do
        expect(titulos(superficie, sem_chave, '120200000000000001'))
          .to contain_exactly('Card do anúncio', 'Card da divulgação', 'Card sem origem', 'Card só do anúncio')
      end

      it "#{superficie}: com a chave, administrador e agente sem função filtram pelo anúncio" do
        [com_view, com_manage, admin, plain_agent].each do |user|
          expect(titulos(superficie, user, '120200000000000001')).to contain_exactly('Card do anúncio', 'Card só do anúncio')
        end
      end
    end
  end
end
