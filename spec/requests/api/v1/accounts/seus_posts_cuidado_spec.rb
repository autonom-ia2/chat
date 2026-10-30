require 'rails_helper'

# IA cuida dos comentários do post (#2212, B1): o painel, ligar e pausar, a prévia, o "Ler e mandar", o resumo e o selo
# da lista. As mesmas guardas do post do F2, mais a flag meta_ads_comentarios_ia.
RSpec.describe 'Seus posts: IA cuida dos comentários do post', type: :request do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:ig_id) { '17841400000000001' }
  let(:post_id) { '17900000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo') }
  let(:base) { "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_id}" }
  let(:perfil) { "instagram-#{canal.id}" }
  let(:corpo) do
    { perfil: perfil, message: 'Oi! O e-book sai por R$ 29. Te mando o link?', para_quem: 'Quem pedir o e-book',
      phrases: ['Te chamei no privado'], status: 'on' }
  end

  def comentario(id, text, horas: 1, **extra)
    { id: id, text: text, timestamp: horas.hours.ago.iso8601, from: { id: "f#{id}", username: "pessoa#{id}" } }.merge(extra)
  end

  def stub_comentarios(*data)
    stub_request(:get, %r{#{ig}/#{post_id}/comments}).to_return(status: 200, headers: json, body: { data: data }.to_json)
    stub_request(:get, %r{#{ig}/#{post_id}\?.*fields=comments_count})
      .to_return(status: 200, headers: json, body: { comments_count: data.size }.to_json)
  end

  before do
    Rails.cache.clear
    account.enable_features!('seus_posts', 'seus_posts_comentarios', 'meta_ads_comentarios_ia')
    allow(SeusPosts::Posts).to receive(:para).and_return(
      instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [{ id: post_id, created_time: 1.day.ago.iso8601 }], normal: {} })
    )
    stub_comentarios(comentario('101', 'Quero o e-book'), comentario('102', 'Lindo!'), comentario('103', 'Valor?', horas: 24 * 9),
                     comentario('104', 'Compre seguidores', hidden: true))
  end

  it 'sem a flag meta_ads_comentarios_ia: 404' do
    account.disable_features!('meta_ads_comentarios_ia')

    get "#{base}/cuidado", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'antes de ligar: cuidado desligado, o que espera o dono e o privado liberado no Instagram' do
    get "#{base}/cuidado", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('status' => 'ready', 'network' => 'instagram', 'private_available' => true, 'care' => 'off',
                            'unanswered' => 2, 'older' => 1, 'read_old' => false, 'hidden' => [])
    expect(body['to_see'].map { |item| [item['id'], item['kind']] }).to eq([%w[101 waiting], %w[102 waiting], %w[103 older]])
  end

  it 'liga com as palavras do dono, grava o cuidado do post e devolve o painel' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('care' => 'on', 'para_quem' => 'Quem pedir o e-book', 'phrases' => ['Te chamei no privado'])
    expect(Crm::MetaAdsCommentCare.sole).to have_attributes(target_kind: 'post', target_id: post_id, network: 'instagram',
                                                            status: 'on', created_by_id: admin.id, offer: nil,
                                                            inbox_id: canal.inbox.id)
  end

  it 'pausa e volta' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json
    put "#{base}/cuidado", params: corpo.merge(status: 'paused'), headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['care']).to eq('paused')
    expect(Crm::MetaAdsCommentCare.sole.status).to eq('paused')
  end

  it 'recusa sem "para quem", com status desconhecido, mensagem longa demais ou texto que não é texto' do
    [corpo.merge(para_quem: ' '), corpo.merge(status: 'off'), corpo.merge(message: 'a' * 1001), corpo.merge(message: ['x']),
     corpo.merge(phrases: [])].each do |errado|
      put "#{base}/cuidado", params: errado, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(Crm::MetaAdsCommentCare.count).to eq(0)
  end

  it '"Ler e mandar": uma vez, só com o cuidado ligado, e põe os comentários de até 7 dias na fila do motor' do
    post "#{base}/cuidado/ler_antigos", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('not_on')

    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json
    perform_enqueued_jobs(only: Crm::MetaAds::ComentariosIa::LerAntigosJob) do
      post "#{base}/cuidado/ler_antigos", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:ok)
    cuidar = enqueued_jobs.select { |job| job['job_class'] == 'Crm::MetaAds::ComentariosIa::CuidarJob' }
    expect(cuidar.map { |job| job['arguments'].first['comment_id'] }).to eq(%w[101 102])
    expect(cuidar.first['arguments'].first).to include('network' => 'instagram', 'inbox_id' => canal.inbox.id, 'post_id' => post_id)
    expect(cuidar.first['arguments'].first.keys).not_to include('text', 'from_name')

    post "#{base}/cuidado/ler_antigos", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('already_read')
  end

  it 'prévia: decide com o "para quem" do dono' do
    classificador = instance_double(Crm::MetaAds::ComentariosIa::Classificador)
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:decidir!) { |texto| { 'Quero o e-book' => 'private', 'Lindo!' => 'no_reply' }[texto] }

    post "#{base}/cuidado/previa", params: { perfil: perfil, para_quem: 'Quem pedir o e-book' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('recebe' => include('text' => 'Quero o e-book'), 'nao' => include('text' => 'Lindo!'))
  end

  it 'prévia: Jev fora do ar é falha (422 ai_unavailable), nunca uma prévia vazia' do
    classificador = instance_double(Crm::MetaAds::ComentariosIa::Classificador)
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:decidir!).and_raise(TypesafeAi::Decisor::Error.new('typesafe_unavailable'))

    post "#{base}/cuidado/previa", params: { perfil: perfil, para_quem: 'Quem pedir o e-book' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'ai_unavailable')
  end

  it 'prévia: "para quem" acima do limite do cuidado é recusado antes de perguntar à IA' do
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new)
    longo = 'a' * (Crm::MetaAdsCommentCare::NOTE_LIMIT + 1)

    post "#{base}/cuidado/previa", params: { perfil: perfil, para_quem: longo }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'invalid_para_quem')
    expect(Crm::MetaAds::ComentariosIa::Classificador).not_to have_received(:new)
  end

  it 'resumo: Jev fora do ar é falha (422 ai_unavailable)' do
    allow(Crm::MetaAds::ComentariosIa::Resumo).to receive(:new)
      .and_return(instance_double(Crm::MetaAds::ComentariosIa::Resumo, call: { status: 'ai_unavailable' }))

    get "#{base}/resumo", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'ai_unavailable')
  end

  it 'o painel também confere que o post é do perfil: post de outro perfil é 404, sem ler os comentários dele' do
    outro_post = "/api/v1/accounts/#{account.id}/seus_posts/posts/17900000000000002/cuidado"
    get outro_post, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'post_not_found')
  end

  it 'agente sem posts_manage recebe 403 antes de qualquer leitura na Meta' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: canal.inbox)
    allow(Pundit).to receive(:policy!).and_call_original
    allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

    put "#{base}/cuidado", params: corpo, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{base}/cuidado/previa", params: { perfil: perfil, para_quem: 'x' }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{base}/cuidado/ler_antigos", params: { perfil: perfil }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(SeusPosts::Posts).not_to have_received(:para)
  end

  it '"Pausar todos" muda tudo de uma vez, mesmo cuidado antigo que não passaria na validação de hoje, e audita depois' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json
    antigo = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '17900000000000008',
                                                network: 'instagram', inbox: canal.inbox, status: 'on')
    antigo.update_column(:message, 'ã' * 600) # rubocop:disable Rails/SkipsModelValidations

    put "/api/v1/accounts/#{account.id}/seus_posts/cuidados", params: { perfil: perfil, status: 'paused' },
                                                              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsCommentCare.pluck(:status)).to all(eq('paused'))
    auditoria = Audited.audit_class.where(action: 'seus_posts_comment_care').order(:id).last
    expect(auditoria.audited_changes).to include('action' => 'all', 'status' => 'paused',
                                                 'post_ids' => contain_exactly(post_id, '17900000000000008'))
  end

  it 'resumo: na primeira vez, está lendo' do
    get "#{base}/resumo", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('status' => 'reading')
  end

  it 'a lista: o estado do cuidado de cada post, para o selo "Cuidando"' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json

    get "/api/v1/accounts/#{account.id}/seus_posts/cuidados", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['cuidados']).to eq([{ 'post_id' => post_id, 'care' => 'on', 'network' => 'instagram',
                                                      'results' => { 'sent' => 0, 'replied' => 0 } }])
  end

  it 'a lista é só do perfil: o cuidado de outro perfil da conta não aparece nem é pausado' do
    outro = create(:channel_instagram, account: account, instagram_id: '17841400000000002', provider_name: 'outraloja')
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '17900000000000009', network: 'instagram',
                                       inbox: outro.inbox, message: 'Oi', status: 'on')
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json

    put "/api/v1/accounts/#{account.id}/seus_posts/cuidados", params: { perfil: perfil, status: 'paused' },
                                                              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['cuidados'].map { |item| [item['post_id'], item['care']] }).to eq([[post_id, 'paused']])
    expect(Crm::MetaAdsCommentCare.find_by(target_id: '17900000000000009').status).to eq('on')
  end

  it '"Pausar todos": recusa status desconhecido e agente sem posts_manage' do
    put "/api/v1/accounts/#{account.id}/seus_posts/cuidados", params: { perfil: perfil, status: 'off' },
                                                              headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: canal.inbox)
    put "/api/v1/accounts/#{account.id}/seus_posts/cuidados", params: { perfil: perfil, status: 'paused' },
                                                              headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'agente que vê a caixa, sem posts_manage: vê o painel, mas não liga' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: canal.inbox)
    allow(Pundit).to receive(:policy!).and_call_original
    allow(Pundit).to receive(:policy!).with(anything, :seus_posts).and_return(instance_double(SeusPostsPolicy, index?: true, manage?: false))

    get "#{base}/cuidado", params: { perfil: perfil }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    put "#{base}/cuidado", params: corpo, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
