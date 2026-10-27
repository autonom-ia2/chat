require 'rails_helper'

# #2271 (decisões do Rodrigo, 27/10), fora do card: a função personalizada sem `meta_ads_view` (nem `meta_ads_manage`)
# não recebe o anúncio de origem também
# - na conversa (additional_attributes.campaign, campaign_touches e o espelho campaign_source_ids), em lista, detalhe,
#   mensagens, busca, notificações, "Origem e campanhas" do contato e tempo real;
# - nas opções do filtro por campanha (GET /ctwa_campaigns, que serve ao CRM e às Conversas);
# - nos filtros campaign_source_ids do CRM e de Conversas, que descartam só os ids de anúncio e continuam filtrando pela
#   divulgação. Um id que foi anúncio em qualquer toque conta como anúncio. O robô (token do AgentBot) vê tudo.
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

    it 'robô (token do AgentBot) vê a conversa inteira; a pessoa sem a chave, não' do
      robo = create(:agent_bot, account: account)
      get "#{api}/conversations/#{conversa_anuncio.display_id}", headers: { api_access_token: robo.access_token.token }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['additional_attributes']['campaign_touches'].first).to eq(toque_anuncio)

      expect(ler("conversations/#{conversa_anuncio.display_id}", sem_chave)['additional_attributes']).to include(atributos_oculto)
    end

    # O token de API de uma pessoa só preenche o Current (o `current_user` do Devise vem vazio): a regra vale igual.
    it 'pessoa sem a chave pelo token de API: não vê o anúncio na conversa nem filtra por ele' do
      token = { api_access_token: sem_chave.access_token.token }
      get "#{api}/conversations/#{conversa_anuncio.display_id}", headers: token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['additional_attributes']).to include(atributos_oculto)

      post "#{api}/conversations/filter", headers: token, as: :json,
                                          params: { payload: [{ attribute_key: 'campaign_source_ids', filter_operator: 'contains',
                                                                values: ['"120200000000000001"'], query_operator: nil }] }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to match_array(todas_as_conversas(sem_chave))
      expect(response.body).not_to include(*fora_do_referral)
    end
  end

  # Sem identidade não vê (fail-closed); a chamada interna diz que é interna.
  describe 'quem lê' do
    it 'sem usuário nem account_user não vê; interno: true vê; o robô vê' do
      expect(Crm::AnuncioDeOrigem.ve_no_contexto?(nil, nil)).to be(false)
      expect(Crm::AnuncioDeOrigem.ve_no_contexto?(nil, nil, interno: true)).to be(true)
      expect(Crm::AnuncioDeOrigem.ve_no_contexto?(create(:agent_bot, account: account), nil)).to be(true)
      expect(Crm::AnuncioDeOrigem.ve_no_contexto?(create(:user), nil)).to be(false)
    end
  end

  # O ActionCableBroadcastJob busca a conversa de novo (prepare_broadcast_data) e aplica a visão por destinatário no
  # próprio job: vale para o ActionCableListener, o Crm::Access::VisibilitySync e qualquer outro chamador.
  describe 'tempo real (ActionCableBroadcastJob de verdade)' do
    def entregas
      recebidos = Hash.new { |hash, token| hash[token] = [] }
      allow(ActionCable.server).to receive(:broadcast) { |token, mensagem| recebidos[token] << mensagem[:data] }
      yield
      recebidos
    end

    def tokens = [sem_chave, plain_agent, admin, com_view, com_manage].map(&:pubsub_token)

    it 'CONVERSATION_UPDATED com a conversa buscada de novo: inteira para quem vê, sem o anúncio para quem não vê' do
      recebidos = entregas do
        # Dado velho de propósito: o job busca a conversa de novo e é essa que sai.
        ActionCableBroadcastJob.perform_now(tokens, Events::Types::CONVERSATION_UPDATED,
                                            { id: conversa_anuncio.display_id, account_id: account.id, additional_attributes: {} })
      end

      oculto = recebidos.fetch(sem_chave.pubsub_token).sole
      expect(oculto[:additional_attributes]).to include(atributos_oculto)
      expect(oculto[:additional_attributes].to_json).not_to include(*identificadores)
      expect(oculto.to_json).not_to include(*fora_do_referral)
      [plain_agent, admin, com_view, com_manage].each do |user|
        expect(recebidos.fetch(user.pubsub_token).sole[:additional_attributes]['campaign_touches'].first).to eq(toque_anuncio)
      end
    end

    it 'conversa sem toque de anúncio: um envio igual para todos, sem consultar quem vê' do
      recebidos = entregas do
        expect(AccountUser).not_to receive(:where)
        ActionCableBroadcastJob.perform_now(tokens, Events::Types::CONVERSATION_UPDATED,
                                            { id: conversa_divulgacao.display_id, account_id: account.id })
      end

      expect(recebidos.values.map(&:sole).uniq.size).to eq(1)
      expect(recebidos.keys).to match_array(tokens)
    end

    it 'se achar quem vê falhar, todos recebem a conversa sem o anúncio e o erro vai para o log' do
      allow(User).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Rails.logger).to receive(:error)
      recebidos = entregas do
        ActionCableBroadcastJob.perform_now(tokens, Events::Types::CONVERSATION_UPDATED,
                                            { id: conversa_anuncio.display_id, account_id: account.id })
      end

      expect(recebidos.keys).to match_array(tokens)
      recebidos.each_value do |mensagens|
        expect(mensagens.sole[:additional_attributes]).to include(atributos_oculto)
        expect(mensagens.sole.to_json).not_to include(*fora_do_referral)
      end
      expect(Rails.logger).to have_received(:error).with(include('ActiveRecord::ConnectionNotEstablished'))
    end

    it 'VisibilitySync: o evento que ele manda direto pelo job também sai sem o anúncio para quem não vê' do
      recebidos = entregas do
        perform_enqueued_jobs do
          Crm::Access::VisibilitySync.broadcast(conversa_anuncio, tokens, Events::Types::CONVERSATION_UPDATED) do
            conversa_anuncio.push_event_data
          end
        end
      end

      expect(recebidos.fetch(sem_chave.pubsub_token).sole[:additional_attributes]).to include(atributos_oculto)
      expect(recebidos.fetch(plain_agent.pubsub_token).sole[:additional_attributes]['campaign_touches'].first).to eq(toque_anuncio)
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

      it "#{superficie}: sem a chave, mais de #{Crm::AnuncioDeOrigem::Ids::MAX_IDS} ids dá 422" do
        ids = Array.new(Crm::AnuncioDeOrigem::Ids::MAX_IDS + 1) { |indice| "id-#{indice}" }.join(',')
        get "#{api}/crm/#{superficie}", params: { pipeline_id: pipeline_and_stage.first.id, campaign_source_ids: ids },
                                        headers: auth_headers(sem_chave)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.custom_filters.too_many_campaigns', limit: 50))
      end

      it "#{superficie}: com a chave, administrador e agente sem função filtram pelo anúncio" do
        [com_view, com_manage, admin, plain_agent].each do |user|
          expect(titulos(superficie, user, '120200000000000001')).to contain_exactly('Card do anúncio', 'Card só do anúncio')
        end
      end
    end
  end

  # Id misto: o mesmo id é anúncio numa conversa (que a pessoa nem vê) e divulgação em outra. Conta como anúncio no
  # picker e nos dois filtros, e o título não aparece para quem não vê.
  describe 'id misto (anúncio numa conversa, divulgação em outra)' do
    before do
      escondida = create_crm_inbox(account: account, name: 'Caixa sem a pessoa', members: [])
      conversa = create_crm_conversation(account: account, inbox: escondida, contact: contato)
      conversa.update!(additional_attributes: {
                         'campaign_touches' => [toque_anuncio.merge('source_id' => 'misto-1', 'headline' => 'Título do misto')],
                         'campaign_source_ids' => %w[misto-1]
                       })
      conversa_divulgacao.update!(additional_attributes: {
                                    'campaign_touches' => [toque_divulgacao, toque_divulgacao.merge('source_id' => 'misto-1')],
                                    'campaign_source_ids' => %w[divulgacao-1 misto-1]
                                  })
    end

    it 'picker: sem a chave, o id misto não aparece; com a chave, aparece' do
      expect(ler('ctwa_campaigns', sem_chave)['payload'].pluck('source_id')).to eq(['divulgacao-1'])
      expect(response.body).not_to include('Título do misto', 'misto-1')
      expect(ler('ctwa_campaigns', com_view)['payload'].pluck('source_id')).to include('misto-1')
    end

    it 'filtro de Conversas: sem a chave, o id misto sai da condição' do
      expect(filtrar_conversas(sem_chave, ['"misto-1"'])).to match_array(todas_as_conversas(sem_chave))
      expect(filtrar_conversas(com_view, ['"misto-1"'])).to eq([conversa_divulgacao.display_id])
    end
  end

  describe 'filtro de Conversas (POST conversations/filter)' do
    def todas = todas_as_conversas(sem_chave)

    it 'filtro misto sem a chave: o anúncio sai e a divulgação continua filtrando' do
      resultado = filtrar_conversas(sem_chave, ['"120200000000000001"', '"divulgacao-1"'])

      expect(resultado).to contain_exactly(conversa_anuncio.display_id, conversa_divulgacao.display_id)
      sozinho = create_crm_conversation(account: account, inbox: inbox, contact: contato)
      sozinho.update!(additional_attributes: { 'campaign_touches' => [toque_anuncio], 'campaign_source_ids' => %w[120200000000000001] })
      expect(filtrar_conversas(sem_chave, ['"120200000000000001"', '"divulgacao-1"'])).not_to include(sozinho.display_id)
    end

    it 'só o anúncio, sem a chave: a condição é ignorada' do
      expect(filtrar_conversas(sem_chave, ['"120200000000000001"'])).to match_array(todas)
    end

    it 'um pedaço do id digitado à mão não sonda o anúncio' do
      expect(filtrar_conversas(sem_chave, ['1202'])).to match_array(todas)
    end

    it 'com a chave, agente sem função e administrador filtram pelo anúncio' do
      [com_view, plain_agent, admin].each do |user|
        expect(filtrar_conversas(user, ['"120200000000000001"'])).to eq([conversa_anuncio.display_id])
      end
    end

    it "mais de #{Crm::AnuncioDeOrigem::Ids::MAX_IDS} ids: 422 com a mensagem do limite" do
      valores = Array.new(Crm::AnuncioDeOrigem::Ids::MAX_IDS + 1) { |indice| "\"id-#{indice}\"" }
      post "#{api}/conversations/filter", headers: auth_headers(sem_chave), as: :json,
                                          params: { payload: [{ attribute_key: 'campaign_source_ids', filter_operator: 'contains',
                                                                values: valores, query_operator: nil }] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.custom_filters.too_many_campaigns', limit: 50))
    end

    # O toque antigo, gravado só em `campaign` (sem lista nem espelho), conta igual com poucos e com muitos ids.
    it 'toque antigo só em campaign: o id é anúncio com 1 e com 25 ids' do
      antiga = create_crm_conversation(account: account, inbox: inbox, contact: contato)
      antiga.update!(additional_attributes: { 'campaign' => toque_anuncio.merge('source' => '', 'source_id' => 'legado-1') })
      conversa_divulgacao.update!(additional_attributes: {
                                    'campaign_touches' => [toque_divulgacao, toque_divulgacao.merge('source_id' => 'legado-1')],
                                    'campaign_source_ids' => %w[divulgacao-1 legado-1]
                                  })
      muitos = ['"legado-1"'] + Array.new(24) { |indice| "\"inexistente-#{indice}\"" }

      expect(filtrar_conversas(sem_chave, ['"legado-1"'])).to match_array(todas)
      expect(filtrar_conversas(sem_chave, muitos)).to match_array(todas)
      expect(filtrar_conversas(com_view, ['"legado-1"'])).to eq([conversa_divulgacao.display_id])
    end

    it 'is_present continua valendo (diz só que veio de campanha, o que a conversa já mostra)' do
      expect(filtrar_conversas(sem_chave, nil, 'is_present'))
        .to contain_exactly(conversa_anuncio.display_id, conversa_divulgacao.display_id)
    end
  end

  def filtrar_conversas(user, valores, operador = 'contains')
    post "#{api}/conversations/filter", headers: auth_headers(user), as: :json,
                                        params: { payload: [{ attribute_key: 'campaign_source_ids', filter_operator: operador,
                                                              values: valores, query_operator: nil }] }
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].pluck('id')
  end

  def todas_as_conversas(user)
    post "#{api}/conversations/filter", headers: auth_headers(user), as: :json,
                                        params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to',
                                                              values: %w[open], query_operator: nil }] }
    response.parsed_body['payload'].pluck('id')
  end
end
