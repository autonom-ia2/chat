require 'rails_helper'

# #2469 (PR 3a do #2436): o cuidado de cada post ou anúncio como cartão em Agentes, nos 4 casos (post e anúncio, Instagram
# e Facebook). A leitura na Meta é a da Fonte (coberta nas specs dela e das telas do cuidado): aqui ela vem pronta, e a
# spec cobre o que é deste controller: as guardas de cada alvo, a lista, a porta de cada rede, os grupos dos
# comentários, pausar e voltar, e o Testar.
RSpec.describe 'Agentes: os comentários do post', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:base) { "/api/v1/accounts/#{account.id}/agentes_do_post" }
  let!(:instagram) { create(:channel_instagram, account: account, instagram_id: '17841400000000001') }
  let!(:pagina) { create(:inbox, account: account, channel: create(:channel_facebook_page, account: account, inbox: nil)).channel }
  let(:resultado) { Autonomia::Agents::AnswerResult.new(reply: 'Te mandei no direct!', confidence: 0.9, handoff: { should: false }) }
  let(:chamadas) { [] }

  def cuidado(kind, target_id, network, inbox: nil, **extra)
    create(:crm_meta_ads_comment_care, account: account, target_kind: kind, target_id: target_id, network: network, inbox: inbox, **extra)
  end

  def linha(id, kind = nil)
    { id: id, network: 'instagram', author: "pessoa#{id}", text: "comentário #{id}", kind: kind }.compact
  end

  # A Fonte já lida: o que esperam, as escondidas, a legenda, a capa e a caixa e o post de cada rede.
  def fonte(redes)
    instance_double(Crm::MetaAds::ComentariosIa::Fonte, legenda: 'Seguro viagem para a Europa', capa: 'https://cdn.exemplo/capa.jpg',
                                                        redes: redes, ler: { status: 'ready', linhas: [], escondidas: [] })
  end

  def na_porta(inbox, nome)
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: inbox).perform(connect: true)
    agente
  end

  def anuncio_com(redes)
    instance_double(Crm::MetaAds::ComentariosIa::Anuncio, redes: redes, post?: true,
                                                          alvo: { 'kind' => 'ad', 'ad_id' => 'ad', 'networks' => redes.keys,
                                                                  'post_ids' => redes.values.pluck(:post_id) })
  end

  def de_cada_rede(redes)
    redes.transform_values { |rede| { inbox_id: rede[:inbox].id, post_id: rede[:post_id] } }
  end

  before do
    account.enable_features!('seus_posts', 'seus_posts_comentarios', 'meta_ads_comentarios_ia', 'meta_ads_gestao',
                             'meta_ads_comentarios_instagram', 'meta_ads_comentarios_facebook')
    create_meta_ads_insights_connection(account)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      chamadas << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  describe 'a lista' do
    let!(:post_ig) { cuidado('post', '1790', 'instagram', inbox: instagram.inbox) }
    let!(:post_fb) { cuidado('post', '555_777', 'facebook', inbox: pagina.inbox, status: 'paused') }
    let!(:anuncio_ig) { cuidado('ad', '1201', 'instagram') }
    let!(:anuncio_fb) { cuidado('ad', '1202', 'both') }

    it 'sem a flag meta_ads_comentarios_ia: 404' do
      account.disable_features!('meta_ads_comentarios_ia')

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'os 4 casos, só do banco, com o perfil do post e o estado de cada um' do
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:post)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['cuidados']).to eq([
                                                       { 'id' => post_ig.id, 'kind' => 'post', 'target_id' => '1790', 'network' => 'instagram',
                                                         'status' => 'on', 'perfil' => "instagram-#{instagram.id}" },
                                                       { 'id' => post_fb.id, 'kind' => 'post', 'target_id' => '555_777', 'network' => 'facebook',
                                                         'status' => 'paused', 'perfil' => "facebook-#{pagina.id}" },
                                                       { 'id' => anuncio_ig.id, 'kind' => 'ad', 'target_id' => '1201', 'network' => 'instagram',
                                                         'status' => 'on', 'perfil' => nil },
                                                       { 'id' => anuncio_fb.id, 'kind' => 'ad', 'target_id' => '1202', 'network' => 'both',
                                                         'status' => 'on', 'perfil' => nil }
                                                     ])
      expect(Crm::MetaAds::ComentariosIa::Fonte).not_to have_received(:post)
    end

    it 'só o que a pessoa pode ver: sem a chave dos anúncios, só os posts da caixa que ela vê' do
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: instagram.inbox)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

      get base, headers: agente.create_new_auth_token, as: :json

      expect(response.parsed_body['cuidados'].pluck('id')).to eq([post_ig.id])
    end

    it 'sem as flags do alvo, o alvo sai da lista' do
      account.disable_features!('meta_ads_gestao')

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['cuidados'].pluck('kind')).to eq(%w[post post])
    end

    it 'sem a conexão de anúncios ativa, os anúncios saem da lista e não abrem' do
      Crm::MetaAdsConnection.find_by(account_id: account.id).update!(status: 'invalid')

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['cuidados'].pluck('kind')).to eq(%w[post post])

      get "#{base}/#{anuncio_ig.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'not_connected')
    end

    it 'post sem as flags do Seus posts: 404, sem ler a Meta' do
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:post)
      account.disable_features!('seus_posts_comentarios')

      get "#{base}/#{post_ig.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Crm::MetaAds::ComentariosIa::Fonte).not_to have_received(:post)
    end

    it 'cuidado de outra conta nunca aparece nem abre' do
      outro = create(:crm_meta_ads_comment_care, target_kind: 'ad', target_id: '999', network: 'instagram')

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['cuidados'].pluck('id')).not_to include(outro.id)

      get "#{base}/#{outro.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'o cartão do post' do
    let!(:care) { cuidado('post', '1790', 'instagram', inbox: instagram.inbox, note: 'Atendo de segunda a sexta') }
    let(:redes) { { 'instagram' => { inbox_id: instagram.inbox.id, post_id: '1790' } } }
    let(:lida) { fonte(redes) }

    before do
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:post).with(instagram, '1790').and_return(lida)
      Crm::MetaAdsPostReading.create!(account: account, network: 'instagram', post_id: '1790', description: 'Uma mala e um avião')
    end

    it 'post do Instagram: a legenda, a capa, a foto, a nota e a porta com o agente, que escreve' do
      agente = na_porta(instagram.inbox, 'Ana')

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'kind' => 'post', 'legenda' => 'Seguro viagem para a Europa', 'capa' => 'https://cdn.exemplo/capa.jpg',
        'foto' => 'Uma mala e um avião', 'nota' => 'Atendo de segunda a sexta', 'can_manage' => true,
        'portas' => [{ 'network' => 'instagram', 'inbox_id' => instagram.inbox.id, 'caixa' => instagram.inbox.name, 'private' => true,
                       'motivo' => nil, 'agente' => { 'id' => agente.id, 'name' => 'Ana' } }]
      )
    end

    it 'os comentários nos grupos da tela: "não era o caso" e escondido em "não respondo", o resto esperando você' do
      painel = instance_double(Crm::MetaAds::ComentariosIa::Painel, payload: {
                                 status: 'ready', results: { sent: 3, replied: 1, skipped: 1 },
                                 to_see: [linha('1', 'complaint'), linha('2', 'skipped'), linha('3', 'waiting')], hidden: [linha('4')]
                               })
      allow(Crm::MetaAds::ComentariosIa::Painel).to receive(:new).and_return(painel)

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      comentarios = response.parsed_body['comentarios']
      expect(comentarios['esperando'].pluck('id')).to eq(%w[1 3])
      expect(comentarios['nao_respondo'].map { |item| [item['id'], item['kind']] }).to eq([%w[2 skipped], %w[4 hidden]])
      expect(comentarios['results']).to eq('sent' => 3, 'replied' => 1, 'skipped' => 1)
    end

    it 'abrir de novo dentro de 2 minutos não volta à Meta; pausar troca a leitura guardada' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      2.times { get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json }
      expect(Crm::MetaAds::ComentariosIa::Fonte).to have_received(:post).once
      expect(response.parsed_body).to include('legenda' => 'Seguro viagem para a Europa', 'can_manage' => true)

      put "#{base}/#{care.id}/estado", params: { status: 'paused' }, headers: admin.create_new_auth_token, as: :json
      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['status']).to eq('paused')

      travel 3.minutes do
        get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json
      end
      expect(Crm::MetaAds::ComentariosIa::Fonte).to have_received(:post).exactly(4).times
    end

    it 'a leitura guardada é de cada pessoa: quem perde a caixa não abre pelo que outra leu' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      agente = create(:user, account: account, role: :agent)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json
      get "#{base}/#{care.id}", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'sem agente na porta: a porta vem sem agente e com o motivo' do
      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      sem_agente = { 'network' => 'instagram', 'inbox_id' => instagram.inbox.id, 'caixa' => instagram.inbox.name, 'private' => true,
                     'motivo' => 'sem_porta', 'agente' => nil }
      expect(response.parsed_body['portas']).to eq([sem_agente])
    end

    it 'post do Facebook: a porta da Página, sem o privado (F4)' do
      care_fb = cuidado('post', '555_777', 'facebook', inbox: pagina.inbox)
      da_pagina = fonte({ 'facebook' => { inbox_id: pagina.inbox.id, post_id: '555_777' } })
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:post).with(pagina, '555_777').and_return(da_pagina)
      agente = na_porta(pagina.inbox, 'Bia')

      get "#{base}/#{care_fb.id}", headers: admin.create_new_auth_token, as: :json

      da_pagina = { 'network' => 'facebook', 'inbox_id' => pagina.inbox.id, 'caixa' => pagina.inbox.name, 'private' => false, 'motivo' => nil,
                    'agente' => { 'id' => agente.id, 'name' => 'Bia' } }
      expect(response.parsed_body['portas']).to eq([da_pagina])
    end

    it 'agente que não vê a caixa do post: 403, sem ler a Meta' do
      agente = create(:user, account: account, role: :agent)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: true))

      get "#{base}/#{care.id}", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAds::ComentariosIa::Fonte).not_to have_received(:post)
    end

    it 'pausar e voltar a cuidar: só o estado muda, e voltar recomeça a contar daqui' do
      care.update!(read_old_at: 1.day.ago, started_at: 2.days.ago)

      put "#{base}/#{care.id}/estado", params: { status: 'paused' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('status' => 'paused')
      expect(care.reload).to have_attributes(status: 'paused', message: care.message, para_quem: care.para_quem)

      put "#{base}/#{care.id}/estado", params: { status: 'on' }, headers: admin.create_new_auth_token, as: :json
      expect(care.reload).to have_attributes(status: 'on', read_old_at: nil)
      expect(care.started_at).to be > 1.minute.ago

      put "#{base}/#{care.id}/estado", params: { status: 'off' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('error' => 'invalid_status')
    end

    it 'pausar o que já está pausado não muda nada nem vai para a Auditoria' do
      care.update!(status: 'paused')

      expect do
        put "#{base}/#{care.id}/estado", params: { status: 'paused' }, headers: admin.create_new_auth_token, as: :json
      end.not_to change(Audited.audit_class, :count)
      expect(response.parsed_body['status']).to eq('paused')
    end

    it 'quem só vê não pausa nem testa: 403, sem ler a Meta nem chamar a IA' do
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: instagram.inbox)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

      put "#{base}/#{care.id}/estado", params: { status: 'paused' }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico' }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      get "#{base}/#{care.id}", headers: agente.create_new_auth_token, as: :json
      expect(response.parsed_body['can_manage']).to be(false)
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(care.reload.status).to eq('on')
    end

    describe 'Testar' do
      before { na_porta(instagram.inbox, 'Ana') }

      it 'o agente da porta escreve de verdade, no formato pedido, com a pergunta como comentário; nada é gravado' do
        expect do
          post "#{base}/#{care.id}/testar", params: { pergunta: ' Quanto custa? ', formato: 'privado' }, headers: admin.create_new_auth_token,
                                            as: :json
        end.not_to(change { [Crm::MetaAdsCommentAction.count, Conversation.count, Message.count] })

        expect(response.parsed_body).to eq('status' => 'escrito', 'texto' => 'Te mandei no direct!')
        chamada = chamadas.sole
        expect(chamada).to include(formato: Autonomia::Agents::Answerer::FormatoDoComentario::PRIVADO, retrieval_query: 'Quanto custa?',
                                   delivery: nil, allow_web_search: false, trust_instruction: false)
        expect(chamada[:contexto_do_turno]).to include('Atendo de segunda a sexta')
      end

      it 'a pergunta não vai para o log' do
        post "#{base}/#{care.id}/testar", params: { pergunta: 'Meu CPF é 123', formato: 'publico' }, headers: admin.create_new_auth_token,
                                          as: :json

        expect(request.filtered_parameters['pergunta']).to eq('[FILTERED]')
      end

      it 'o agente não sabe: fica com o dono, com o motivo' do
        allow(resultado).to receive_messages(reply: 'fallback', handoff: { should: true, reason: 'no_knowledge' })

        post "#{base}/#{care.id}/testar", params: { pergunta: 'Tem para Marte?', formato: 'publico' }, headers: admin.create_new_auth_token,
                                          as: :json

        expect(response.parsed_body).to eq('status' => 'fica_com_o_dono', 'motivo' => 'no_knowledge')
      end

      it 'IA fora do ar: 422 ai_unavailable' do
        allow(resultado).to receive(:error).and_return('timeout')

        post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico' }, headers: admin.create_new_auth_token,
                                          as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq('error' => 'ai_unavailable')
      end

      it 'recusa pergunta vazia, longa demais ou que não é texto, formato desconhecido e rede que o cuidado não tem' do
        [{ pergunta: ' ', formato: 'publico' }, { pergunta: 'a' * 1001, formato: 'publico' }, { pergunta: ['x'], formato: 'publico' },
         { pergunta: 'Oi', formato: 'dm' }].each do |errado|
          post "#{base}/#{care.id}/testar", params: errado, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_content)
        end
        post "#{base}/#{care.id}/testar", params: { pergunta: 'Oi', formato: 'publico', network: 'facebook' }, headers: admin.create_new_auth_token,
                                          as: :json
        expect(response.parsed_body).to eq('status' => 'invalid_network')
        expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      end
    end
  end

  describe 'o cartão do anúncio' do
    let!(:care) { cuidado('ad', '1202', 'both') }
    let(:redes) { { 'instagram' => { post_id: '1790', inbox: instagram.inbox }, 'facebook' => { post_id: '555_777', inbox: pagina.inbox } } }

    before do
      allow(Crm::MetaAds::ComentariosIa::Anuncio).to receive(:ler).and_return(anuncio_com(redes))
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:anuncio).and_return(fonte(de_cada_rede(redes)))
    end

    it 'anúncio nas duas redes: uma porta por rede, cada uma com o seu agente' do
      ana = na_porta(instagram.inbox, 'Ana')
      bia = na_porta(pagina.inbox, 'Bia')

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      ana_ig = { 'network' => 'instagram', 'inbox_id' => instagram.inbox.id, 'caixa' => instagram.inbox.name, 'private' => true,
                 'motivo' => nil, 'agente' => { 'id' => ana.id, 'name' => 'Ana' } }
      bia_fb = { 'network' => 'facebook', 'inbox_id' => pagina.inbox.id, 'caixa' => pagina.inbox.name, 'private' => false,
                 'motivo' => nil, 'agente' => { 'id' => bia.id, 'name' => 'Bia' } }
      expect(response.parsed_body['portas']).to eq([ana_ig, bia_fb])
    end

    it 'anúncio só no Instagram: uma porta só' do
      so_ig = redes.slice('instagram')
      allow(Crm::MetaAds::ComentariosIa::Anuncio).to receive(:ler).and_return(anuncio_com(so_ig))
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:anuncio).and_return(fonte(de_cada_rede(so_ig)))

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['portas'].pluck('network')).to eq(%w[instagram])
    end

    it 'no Testar o dono escolhe a rede: com as duas, sem a rede é recusado; o privado do Facebook não sai (F4)' do
      na_porta(instagram.inbox, 'Ana')
      na_porta(pagina.inbox, 'Bia')

      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('status' => 'invalid_network')

      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'privado', network: 'facebook' },
                                        headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('status' => 'no_private')
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)

      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico', network: 'facebook' },
                                        headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('status' => 'escrito', 'texto' => 'Te mandei no direct!')
      expect(chamadas.sole[:agent].name).to eq('Bia')
    end

    it 'a porta do Facebook sem agente: o Testar nessa rede fica nas frases fixas, com o motivo' do
      na_porta(instagram.inbox, 'Ana')

      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico', network: 'facebook' },
                                        headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('status' => 'frases_fixas', 'motivo' => 'sem_porta')
    end

    it 'quem não vê a caixa de uma das redes: 403 not_inbox_member' do
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: instagram.inbox)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, Crm::MetaAdsConnection)
                                        .and_return(instance_double(Crm::MetaAdsConnectionPolicy, show?: true, update?: true))

      get "#{base}/#{care.id}", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'not_inbox_member')
    end

    it 'quem só vê o anúncio não testa nem pausa: 403, sem ler a Meta nem chamar a IA' do
      agente = create(:user, account: account, role: :agent)
      [instagram.inbox, pagina.inbox].each { |caixa| create(:inbox_member, user: agente, inbox: caixa) }
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, Crm::MetaAdsConnection)
                                        .and_return(instance_double(Crm::MetaAdsConnectionPolicy, show?: true, update?: false))

      post "#{base}/#{care.id}/testar", params: { pergunta: 'Quanto custa?', formato: 'publico', network: 'instagram' },
                                        headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{base}/#{care.id}/estado", params: { status: 'paused' }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      expect(Crm::MetaAds::ComentariosIa::Anuncio).not_to have_received(:ler)
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    end

    it 'o anúncio sumiu da conta de anúncios: 404' do
      allow(Crm::MetaAds::ComentariosIa::Anuncio).to receive(:ler).and_return(nil)

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'ad_not_found')
    end
  end
end
