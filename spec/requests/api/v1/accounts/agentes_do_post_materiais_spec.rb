require 'rails_helper'

# #2487 (PR 3b do #2436): o material só de um post ou anúncio, anexado no cartão do cuidado em Agentes. É do cuidado,
# gravado com o agente da porta; a leitura (IngestJob) é a de sempre e não roda aqui.
RSpec.describe 'Agentes: o material só do post', type: :request do
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
  let(:arquivo) do
    Rack::Test::UploadedFile.new(StringIO.new('Tamanhos P, M e G. Entrega em 3 dias.'), 'text/plain', original_filename: 'Tabela.txt')
  end
  let(:resultado) do
    Autonomia::Agents::AnswerResult.new(reply: 'Temos P, M e G!', confidence: 0.9, handoff: { should: false },
                                        used_knowledge: usados)
  end
  let(:usados) { [] }
  let(:chamadas) { [] }

  def cuidado(kind, target_id, network, inbox: nil)
    create(:crm_meta_ads_comment_care, account: account, target_kind: kind, target_id: target_id, network: network, inbox: inbox)
  end

  def na_porta(inbox, nome, tipo: 'custom')
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: tipo, status: :active, enabled: true)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: inbox).perform(connect: true)
    agente
  end

  def fonte(redes)
    instance_double(Crm::MetaAds::ComentariosIa::Fonte, legenda: 'Camisetas novas', capa: nil, redes: redes,
                                                        ler: { status: 'ready', linhas: [], escondidas: [] })
  end

  def anexar(care, file = arquivo, user: admin)
    post "#{base}/#{care.id}/materiais", params: { file: file }, headers: user.create_new_auth_token
  end

  def material_de(care, agent, nome)
    Autonomia::Agents::Source.create!(account: account, agent: agent, care: care, source_type: 'txt', kind: 'knowledge',
                                      status: :ready, reference: nome)
  end

  before do
    account.enable_features!('seus_posts', 'seus_posts_comentarios', 'meta_ads_comentarios_ia',
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

  describe 'no post do Instagram' do
    let!(:care) { cuidado('post', '1790', 'instagram', inbox: instagram.inbox) }

    before do
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:post).and_return(fonte('instagram' => { inbox_id: instagram.inbox.id, post_id: '1790' }))
    end

    it 'anexa ao cuidado, com o agente da porta, e manda ler; não entra no material do agente' do
      ana = na_porta(instagram.inbox, 'Ana')

      expect { anexar(care) }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)

      expect(response).to have_http_status(:created)
      fonte_nova = care.sources.sole
      expect(fonte_nova).to have_attributes(agent: ana, account: account, source_type: 'txt', kind: 'knowledge', reference: 'Tabela.txt')
      expect(fonte_nova.file).to be_attached
      expect(response.parsed_body).to include('id' => fonte_nova.id, 'reference' => 'Tabela.txt', 'status' => 'pending', 'agente' => 'Ana')
      expect(ana.sources.da_agente).to be_empty
    end

    it 'lista e tira o material do cuidado; tirar leva os trechos' do
      ana = na_porta(instagram.inbox, 'Ana')
      fonte_do_post = material_de(care, ana, 'Tabela.txt')
      Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: ana, source: fonte_do_post, content: 'P, M e G', chunk_index: 0,
                                                metadata: {})

      get "#{base}/#{care.id}/materiais", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['materiais']).to eq([{ 'id' => fonte_do_post.id, 'reference' => 'Tabela.txt', 'source_type' => 'txt',
                                                         'status' => 'ready', 'agente' => 'Ana',
                                                         'review' => { 'status' => nil, 'reviewed_at' => nil } }])

      delete "#{base}/#{care.id}/materiais/#{fonte_do_post.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Autonomia::Agents::Source.exists?(fonte_do_post.id)).to be(false)
      expect(Autonomia::Agents::KnowledgeEntry.where(source_id: fonte_do_post.id)).to be_empty
    end

    it 'sem agente na porta: 422 no_agent, nada gravado' do
      expect { anexar(care) }.not_to change(Autonomia::Agents::Source, :count)

      expect(response.parsed_body['error']).to eq('no_agent')
    end

    it 'a Lia na porta não lê material de comentário: 422 no_agent, nada gravado' do
      na_porta(instagram.inbox, 'Lia', tipo: Crm::MetaAds::ComentariosIa::Porta::LIA)

      expect { anexar(care) }.not_to change(Autonomia::Agents::Source, :count)

      expect(response.parsed_body['error']).to eq('no_agent')
    end

    it 'arquivo de tipo que não se lê (ou foto): 422 invalid_file' do
      na_porta(instagram.inbox, 'Ana')
      foto = Rack::Test::UploadedFile.new(StringIO.new('x'), 'image/png', original_filename: 'foto.png')

      expect { anexar(care, foto) }.not_to change(Autonomia::Agents::Source, :count)

      expect(response.parsed_body['error']).to eq('invalid_file')
    end

    it 'quem só vê lista, mas não anexa nem tira: 403' do
      ana = na_porta(instagram.inbox, 'Ana')
      fonte_do_post = material_de(care, ana, 'Tabela.txt')
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: instagram.inbox)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

      get "#{base}/#{care.id}/materiais", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      anexar(care, user: agente)
      expect(response).to have_http_status(:forbidden)
      delete "#{base}/#{care.id}/materiais/#{fonte_do_post.id}", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(care.sources.count).to eq(1)
    end

    it 'o material de outro cuidado não sai por este: 404' do
      ana = na_porta(instagram.inbox, 'Ana')
      outro = cuidado('post', '1791', 'instagram', inbox: instagram.inbox)
      do_outro = material_de(outro, ana, 'Outro.txt')

      delete "#{base}/#{care.id}/materiais/#{do_outro.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Agents::Source.exists?(do_outro.id)).to be(true)
    end

    it 'cuidado de outra conta: 404' do
      outra = create(:account)
      de_fora = create(:crm_meta_ads_comment_care, account: outra)

      get "#{base}/#{de_fora.id}/materiais", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    describe 'Testar' do
      let(:ana) { na_porta(instagram.inbox, 'Ana') }
      let!(:trecho) do
        Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: ana, source: material_de(care, ana, 'Tabela.txt'),
                                                  content: 'P, M e G', chunk_index: 0, metadata: {})
      end
      let(:usados) { [{ id: trecho.id, content: 'P, M e G', source: 'Tabela.txt' }] }
      # #2510: o Testar decide antes de escrever; aqui, mandar no privado.
      let(:ia) { instance_double(Crm::Ai::ResponsesClient, create: { text: { decision: 'private', certainty: 0.9, reason: 'Quer o G.' }.to_json }) }

      before do
        allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
        allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(ia)
      end

      it 'a resposta lê pelo cuidado e diz de que arquivo dele saiu' do
        post "#{base}/#{care.id}/testar", params: { pergunta: 'Tem G?' }, headers: admin.create_new_auth_token, as: :json

        expect(chamadas.map { |chamada| chamada[:care_id] }.uniq).to eq([care.id])
        expect(response.parsed_body['escrita']).to eq('status' => 'escrito', 'privado' => 'Temos P, M e G!', 'publico' => 'Temos P, M e G!',
                                                      'material' => ['Tabela.txt'])
      end

      it 'o trecho do material do agente não aparece como material do post' do
        do_agente = Autonomia::Agents::Source.create!(account: account, agent: ana, source_type: 'txt', kind: 'knowledge', status: :ready,
                                                      reference: 'Base.txt')
        trecho.update!(source: do_agente)

        post "#{base}/#{care.id}/testar", params: { pergunta: 'Tem G?' }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['escrita']).to eq('status' => 'escrito', 'privado' => 'Temos P, M e G!', 'publico' => 'Temos P, M e G!')
      end
    end
  end

  describe 'no anúncio nas duas redes' do
    let!(:care) { cuidado('ad', '1202', 'both') }
    let(:redes) { { 'instagram' => { post_id: '1790', inbox: instagram.inbox }, 'facebook' => { post_id: '555_777', inbox: pagina.inbox } } }

    before do
      anuncio = instance_double(Crm::MetaAds::ComentariosIa::Anuncio, redes: redes, post?: true,
                                                                      alvo: { 'kind' => 'ad', 'ad_id' => 'ad', 'networks' => redes.keys,
                                                                              'post_ids' => redes.values.pluck(:post_id) })
      allow(Crm::MetaAds::ComentariosIa::Anuncio).to receive(:ler).and_return(anuncio)
      allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:anuncio)
        .and_return(fonte(redes.transform_values { |rede| { inbox_id: rede[:inbox].id, post_id: rede[:post_id] } }))
    end

    it 'sem agente no Instagram, grava com o agente do Facebook' do
      bia = na_porta(pagina.inbox, 'Bia')

      anexar(care)

      expect(response).to have_http_status(:created)
      expect(care.sources.sole.agent).to eq(bia)
    end

    it 'a Lia no Instagram: grava com o agente do Facebook, nunca com ela' do
      na_porta(instagram.inbox, 'Lia', tipo: Crm::MetaAds::ComentariosIa::Porta::LIA)
      bia = na_porta(pagina.inbox, 'Bia')

      anexar(care)

      expect(response).to have_http_status(:created)
      expect(care.sources.sole.agent).to eq(bia)
    end

    it 'quem não vê a caixa de uma das redes não lista nem tira: 403 not_inbox_member' do
      bia = na_porta(pagina.inbox, 'Bia')
      do_anuncio = material_de(care, bia, 'Cupom.txt')
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: instagram.inbox)
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, Crm::MetaAdsConnection)
                                        .and_return(instance_double(Crm::MetaAdsConnectionPolicy, show?: true, update?: true))

      get "#{base}/#{care.id}/materiais", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'not_inbox_member')
      delete "#{base}/#{care.id}/materiais/#{do_anuncio.id}", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Autonomia::Agents::Source.exists?(do_anuncio.id)).to be(true)
    end

    it 'com o detalhe desta pessoa guardado, a lista que se relê não volta à Meta' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      get "#{base}/#{care.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      2.times { get "#{base}/#{care.id}/materiais", headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:ok)
      expect(Crm::MetaAds::ComentariosIa::Anuncio).to have_received(:ler).once
    end
  end

  describe 'o cuidado sai' do
    it 'com a caixa: o material sai pela app, sem deixar fonte nem trecho' do
      care = cuidado('post', '1790', 'instagram', inbox: instagram.inbox)
      ana = na_porta(instagram.inbox, 'Ana')
      fonte_do_post = material_de(care, ana, 'Tabela.txt')
      Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: ana, source: fonte_do_post, content: 'P, M e G', chunk_index: 0,
                                                metadata: {})

      instagram.inbox.destroy!

      expect(Crm::MetaAdsCommentCare.exists?(care.id)).to be(false)
      expect(Autonomia::Agents::Source.exists?(fonte_do_post.id)).to be(false)
      expect(Autonomia::Agents::KnowledgeEntry.where(source_id: fonte_do_post.id)).to be_empty
    end
  end
end
