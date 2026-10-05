require 'rails_helper'

RSpec.describe 'Central de Ajuda (leitura)', type: :request do
  let(:dona) { create(:account) }
  let(:conta) { create(:account) }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:agente) { create(:user, account: conta, role: :agent) }
  let(:portal) do
    create(:portal, account: dona, slug: 'plataforma', config: { 'allowed_locales' => ['pt_BR'], 'default_locale' => 'pt_BR' })
  end
  let(:autor) { create(:user, account: dona, role: :administrator) }

  def categoria(id, nome)
    create(:category, portal: portal, account: dona, slug: "capitulo-#{id}", name: nome, locale: 'pt_BR', position: id.to_i)
  end

  def artigo(id, titulo, cat, opcoes = {})
    create(:article, portal: portal, account: dona, author: autor, category: cat, slug: "plataforma-#{id.tr('.', '-')}",
                     title: titulo, description: "Sobre #{titulo}", content: opcoes.fetch(:texto, 'Texto do artigo.'),
                     status: opcoes.fetch(:status, :published), locale: 'pt_BR', position: id.split('.').last.to_i * 10,
                     meta: { 'central' => { 'id' => id, 'publico' => opcoes.fetch(:publico, 'ambos'), 'requer' => opcoes[:requer],
                                            'me_leve_ate_la' => { 'rota' => 'profile_settings_index', 'destaque' => nil },
                                            'video' => opcoes[:video] } })
  end

  before do
    allow(Autonomia::CentralDeAjuda::Publicador).to receive(:garantir_async)
    pessoais = categoria('02', 'Configurações pessoais')
    conceitos = categoria('18', 'Entenda os conceitos')
    artigo('02.01', 'Onde ficam suas configurações', pessoais)
    artigo('02.02', 'Seu nome e sua foto', pessoais, texto: 'Troque a foto do perfil. Cotação não entra aqui.')
    artigo('02.03', 'Configurar a conta', pessoais, publico: 'admin')
    artigo('02.04', 'Seus avisos', pessoais, texto: 'A janela de atendimento importa aqui.')
    artigo('18.01', 'A janela de 24 horas', conceitos, texto: 'A cotação do cliente trava depois de 24 horas.')
    artigo('18.02', 'Funil com IA', conceitos, requer: 'crm')
    artigo('18.03', 'Rascunho', conceitos, status: :draft)
  end

  def get_json(caminho, usuario, params = {})
    get "/api/v1/accounts/#{conta.id}/central-de-ajuda#{caminho}", headers: usuario.create_new_auth_token, params: params, as: :json
    response.body.present? ? response.parsed_body : nil
  end

  describe 'GET /central-de-ajuda' do
    it 'lista os capítulos na ordem, só com o que a pessoa pode ler, e garante a publicação' do
      corpo = get_json('', agente)

      expect(response).to have_http_status(:ok)
      expect(corpo['preparando']).to be(false)
      expect(corpo['capitulos'].pluck('id', 'titulo')).to eq([['02', 'Configurações pessoais'], ['18', 'Entenda os conceitos']])
      expect(corpo['capitulos'].first['artigos'].pluck('ref')).to eq(%w[02-01 02-02 02-04])
      expect(corpo['capitulos'].last['artigos'].pluck('ref')).to eq(%w[18-01])
      expect(Autonomia::CentralDeAjuda::Publicador).to have_received(:garantir_async)
    end

    # #697 — o Guia sugere, ao abrir, os artigos da tela em que a pessoa está.
    it 'diz em cada artigo a tela que ele explica' do
      corpo = get_json('', agente)

      expect(corpo['capitulos'].first['artigos'].first['rota']).to eq('profile_settings_index')
    end

    it 'mostra ao administrador os artigos de administrador' do
      corpo = get_json('', admin)

      expect(corpo['capitulos'].first['artigos'].pluck('ref')).to eq(%w[02-01 02-02 02-03 02-04])
    end

    it 'mostra o artigo do recurso só para a conta que tem o recurso' do
      conta.enable_features!('crm')

      corpo = get_json('', agente)

      expect(corpo['capitulos'].last['artigos'].pluck('ref')).to eq(%w[18-01 18-02])
    end

    it 'avisa que a Central está sendo preparada quando o portal ainda não existe' do
      Portal.where(slug: 'plataforma').destroy_all

      corpo = get_json('', agente)

      expect(corpo).to eq('preparando' => true, 'capitulos' => [])
    end

    it 'exige login' do
      get "/api/v1/accounts/#{conta.id}/central-de-ajuda", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /central-de-ajuda/:ref' do
    it 'devolve o artigo com o botão Me leve até lá e os vizinhos do capítulo' do
      corpo = get_json('/02-02', agente)

      expect(corpo).to include('id' => '02.02', 'titulo' => 'Seu nome e sua foto', 'capitulo' => 'Configurações pessoais',
                               'me_leve_ate_la' => { 'rota' => 'profile_settings_index', 'destaque' => nil })
      expect(corpo['conteudo']).to include('Troque a foto do perfil.')
      expect(corpo['anterior']).to include('ref' => '02-01')
      expect(corpo['proximo']).to include('ref' => '02-04')
    end

    it 'devolve o vídeo do trajeto quando o artigo tem um, e nada quando não tem' do
      video = { 'arquivo' => '/central-de-ajuda/videos/02.01.mp4', 'legenda' => '/central-de-ajuda/videos/02.01.vtt',
                'poster' => '/central-de-ajuda/videos/02.01.jpg' }
      Article.find_by(slug: 'plataforma-02-01').tap { |a| a.update!(meta: a.meta.deep_merge('central' => { 'video' => video })) }

      expect(get_json('/02-01', agente)['video']).to eq(video)
      expect(get_json('/02-02', agente)['video']).to be_nil
    end

    it 'não entrega artigo que a pessoa não pode ler' do
      get_json('/02-03', agente)
      expect(response).to have_http_status(:not_found)

      get_json('/18-03', admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /central-de-ajuda/busca' do
    it 'acha sem acento e sem maiúscula, só no que a pessoa pode ler' do
      corpo = get_json('/busca', agente, termo: 'COTACAO')

      expect(corpo['resultados'].pluck('ref')).to eq(%w[02-02 18-01])
    end

    it 'põe o título na frente do texto' do
      corpo = get_json('/busca', agente, termo: 'janela')

      expect(corpo['resultados'].pluck('ref')).to eq(%w[18-01 02-04])
    end

    it 'exige as duas palavras quando são duas' do
      corpo = get_json('/busca', agente, termo: 'janela cotação?')

      expect(corpo['resultados'].pluck('ref')).to eq(%w[18-01])
    end

    it 'aceita frase inteira: basta a maioria das palavras, e quem tem mais vem antes' do
      corpo = get_json('/busca', agente, termo: 'como eu troco a foto do perfil')

      expect(corpo['resultados'].first['ref']).to eq('02-02')
    end

    it 'não acha nada quando a frase não bate com a maioria das palavras' do
      corpo = get_json('/busca', agente, termo: 'boleto vencido segunda via')

      expect(corpo['resultados']).to eq([])
    end

    it 'devolve lista vazia para busca vazia' do
      expect(get_json('/busca', agente, termo: '  ')['resultados']).to eq([])
    end
  end

  describe 'GET /central-de-ajuda/busca_inteligente' do
    let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }

    def responder_jev(choice, confidence = 0.8)
      stub_request(:post, jev_url).to_return(
        status: 200,
        body: { model: 'jev-1.13.0', usage: { input_tokens: 900, output_tokens: 2 },
                answers: { artigo: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
      )
    end

    before { allow(TypesafeAi::Config).to receive(:api_key).and_return('ts_test_key_not_real') }

    it 'devolve o artigo escolhido pelo Jev com a certeza, só entre os que a pessoa pode ler' do
      pedido = responder_jev('18.01', 0.74)

      corpo = get_json('/busca_inteligente', agente, termo: 'o cliente não responde mais')

      expect(response).to have_http_status(:ok)
      expect(corpo['melhor']).to include('ref' => '18-01', 'titulo' => 'A janela de 24 horas')
      expect(corpo['certeza']).to eq(0.74)
      expect(a_request(:post, jev_url).with do |http|
        JSON.parse(http.body).dig('questions', 'artigo', 'criteria').keys == %w[02.01 02.02 02.04 18.01 nenhum]
      end).to have_been_made.once
      expect(pedido).to have_been_made.once
      expect(Crm::AiUsageEvent.where(account: conta, feature: 'central_busca').count).to eq(1)
    end

    it 'com exceto, pede a alternativa sem a Melhor resposta entre as opções (#985)' do
      responder_jev('02.04', 0.55)

      corpo = get_json('/busca_inteligente', agente, termo: 'o cliente não responde mais', exceto: '18-01')

      expect(corpo['melhor']).to include('ref' => '02-04')
      expect(a_request(:post, jev_url).with do |http|
        pergunta = JSON.parse(http.body).dig('questions', 'artigo')
        pergunta['criteria'].keys == %w[02.01 02.02 02.04 nenhum] &&
          pergunta['instructions'] == Autonomia::CentralDeAjuda::BuscaInteligente::INSTRUCOES_DA_ALTERNATIVA
      end).to have_been_made.once
    end

    it 'com exceto que a pessoa não pode ler, devolve vazio sem chamar o Jev' do
      responder_jev('02.04', 0.55)

      expect(get_json('/busca_inteligente', agente, termo: 'o cliente não responde mais', exceto: '99.99'))
        .to eq('melhor' => nil, 'certeza' => nil)
      expect(a_request(:post, jev_url)).not_to have_been_made
    end

    it 'devolve vazio quando nenhum artigo responde' do
      responder_jev('nenhum', 0.9)

      expect(get_json('/busca_inteligente', agente, termo: 'boleto vencido')).to eq('melhor' => nil, 'certeza' => nil)
    end

    it 'devolve vazio, sem quebrar a tela, quando o Jev falha' do
      stub_request(:post, jev_url).to_return(status: 503)

      expect(get_json('/busca_inteligente', agente, termo: 'janela')).to eq('melhor' => nil, 'certeza' => nil)
      expect(response).to have_http_status(:ok)
    end

    it 'não chama o Jev para termo curto nem sem a chave configurada' do
      expect(get_json('/busca_inteligente', agente, termo: 'ab')).to eq('melhor' => nil, 'certeza' => nil)
      allow(TypesafeAi::Config).to receive(:api_key).and_return(nil)
      expect(get_json('/busca_inteligente', agente, termo: 'janela')).to eq('melhor' => nil, 'certeza' => nil)
      expect(a_request(:post, jev_url)).not_to have_been_made
    end

    it 'exige login' do
      get "/api/v1/accounts/#{conta.id}/central-de-ajuda/busca_inteligente", params: { termo: 'janela' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
