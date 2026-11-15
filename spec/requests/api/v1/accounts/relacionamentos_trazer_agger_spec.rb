require 'rails_helper'

# E7 (#2900) — as rotas de "Trazer do Agger": começar a busca, o Conferir com as seguradoras, buscar de novo, o histórico
# das buscas, o interruptor da busca de todo dia e o resumo dizendo se a conta pode trazer e se o login foi aceito. O
# job da busca só é posto na fila, com o id; os passos andam aqui com o conector de mentira. Tudo fictício.
RSpec.describe 'Carteira de seguros: trazer do Agger', :aggregate_failures, type: :request do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos/trazer/seguros" }

  before do
    enable_test_encryption!
    sem_pergunta_paga_do_ramo
  end

  def buscar(quem: admin)
    post "#{base}/busca", headers: quem.create_new_auth_token, as: :json
  end

  def resumo
    get "/api/v1/accounts/#{account.id}/relacionamentos/seguros/resumo", headers: admin.create_new_auth_token
    response.parsed_body
  end

  it 'sem o login do Agger: o resumo diz que pode trazer mas não está ligado, e a busca é recusada' do
    expect(resumo).to include('aggerDisponivel' => true, 'aggerLigado' => false)

    expect { buscar }.not_to have_enqueued_job(Carteira::Conector::BuscaJob)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'agger_desligado')
  end

  describe 'com o Agger conectado' do
    before { conectar_agger!(account) }

    it 'começa a busca, põe o job na fila só com o id, e o Conferir mostra as seguradoras e os números' do
      expect(resumo['aggerLigado']).to be(true)
      expect { buscar }.to have_enqueued_job(Carteira::Conector::BuscaJob).with(kind_of(Integer))
      expect(response).to have_http_status(:created)
      id = response.parsed_body['leituraId']

      get "#{base}/leituras/#{id}", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('estado' => 'lendo', 'origem' => 'conector', 'diaria' => false)

      andar_a_busca(Carteira::Leitura.find(id))
      get "#{base}/leituras/#{id}", headers: admin.create_new_auth_token
      corpo = response.parsed_body
      expect(corpo).to include('estado' => 'lida', 'seguros' => 3, 'pessoas' => 3, 'semTelefone' => 3, 'naoDeuParaTrazer' => 2)
      expect(corpo['porSeguradora']).to include({ 'nome' => nil, 'situacao' => 'sem_login' },
                                                { 'nome' => 'Seguradora Sol (exemplo)', 'situacao' => 'pede_login' })
      expect(corpo.to_s).not_to include('mock-pdf', 'exemplo.test', '10020030088')
    end

    it 'trazer, o histórico com Desfazer e buscar de novo' do
      buscar
      id = response.parsed_body['leituraId']
      leitura = andar_a_busca(Carteira::Leitura.find(id))

      post "#{base}/leituras/#{id}/de_novo", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['estado']).to eq('lendo')
      andar_a_busca(leitura)

      post "#{base}/leituras/#{id}/trazer", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['estado']).to eq('trazendo')
      gravar_a_busca(leitura)

      get "#{base}/leituras", params: { origem: 'conector' }, headers: admin.create_new_auth_token
      expect(response.parsed_body).to match([include('id' => id, 'diaria' => false, 'situacao' => 'trazida', 'seguros' => 3,
                                                     'podeDesfazer' => true)])

      get "#{base}/busca_diaria", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('ligado' => true, 'jaTrouxe' => true)

      get "#{base}/leituras", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq([])

      get "#{base}/leituras", params: { origem: 'pdf' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'buscar de novo só vale para a busca no Agger' do
      lote = create(:carteira_leitura, account: account, origem: 'pdf', estado: 'lida')

      post "#{base}/leituras/#{lote.id}/de_novo", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'o interruptor da busca de todo dia liga e desliga, e recusa o que não é sim ou não' do
      get "#{base}/busca_diaria", headers: admin.create_new_auth_token
      expect(response.parsed_body).to eq('ligado' => false, 'jaTrouxe' => false)

      put "#{base}/busca_diaria", params: { ligado: true }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('ligado' => true)
      expect(Carteira::Conector::BuscaDiaria.new(account).ligada?).to be(true)

      put "#{base}/busca_diaria", params: { ligado: 'sim' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Carteira::Conector::BuscaDiaria.new(account).ligada?).to be(true)
    end

    it 'o agente sem a permissão de trazer contatos não busca nem mexe no interruptor' do
      buscar(quem: agente)
      expect(response).to have_http_status(:unauthorized)

      put "#{base}/busca_diaria", params: { ligado: true }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'a conta sem a carteira não vê nada disso' do
    sem_carteira = create(:account)
    dono = create(:user, account: sem_carteira, role: :administrator)

    post "/api/v1/accounts/#{sem_carteira.id}/relacionamentos/trazer/seguros/busca", headers: dono.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found).or have_http_status(:unauthorized)
  end

  it 'a conta que só tem a carteira conecta o Agger pela porta da Cotação, e o resto da Cotação continua fechado' do
    post "/api/v1/accounts/#{account.id}/autonomia/insurance/connection",
         params: { provider: 'agger', connection: { username: 'corretora@exemplo.test', password: 'segredo' } },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'status')).to be_in(%w[ready discovering])
    expect(Carteira::Conector.ligado?(account)).to be(true)

    get "/api/v1/accounts/#{account.id}/autonomia/insurance/quote_agent", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
