require 'rails_helper'

# #2894 — as leituras da Lista nova de Relacionamentos: pessoas (página, contagens e "todas"), o resumo do topo e as
# opções da gaveta de filtros. A regra de grupo, busca, filtro e ordem está em consulta_de_pessoas_spec.rb.
RSpec.describe 'Lista de Relacionamentos', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }
  let(:leituras) { %w[pessoas pessoas/contagens pessoas/todas resumo opcoes_de_filtro] }

  before do
    account.enable_features!('relacionamentos_novo')
    travel_to(agora)
  end

  def ler(caminho, **params)
    get "#{base}/#{caminho}", params: params, headers: agente.create_new_auth_token
  end

  def pessoa(nome, **dados)
    create(:contact, account: account, name: nome, contact_type: :lead, **dados)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  it 'responde 401 sem login' do
    leituras.each do |caminho|
      get "#{base}/#{caminho}"

      expect(response).to have_http_status(:unauthorized), caminho
    end
  end

  it 'responde 404 com a chave da conta desligada' do
    account.disable_features!('relacionamentos_novo')

    leituras.each do |caminho|
      ler(caminho)

      expect(response).to have_http_status(:not_found), caminho
    end
  end

  it 'atende o agente comum, como a lista de contatos de hoje' do
    leituras.each do |caminho|
      ler(caminho)

      expect(response).to have_http_status(:ok), caminho
    end
  end

  describe 'GET pessoas' do
    it 'devolve a página com os campos que as telas leem' do
      account.disable_features!('companies')
      ana = pessoa('Ana Albuquerino', email: 'ana.albuquerino@exemplo.com.br', phone_number: '+5511910310001',
                                      contact_type: :customer, customer_since: agora - 20.days,
                                      last_activity_at: agora - 2.days, created_at: agora - 40.days,
                                      additional_attributes: { city: 'Campinas', company_name: 'Padaria Bom Dia' },
                                      custom_attributes: { cpf: '123.456.789-00' },
                                      opted_out_at: agora - 1.day, opt_out_source: 'manual')
      ana.update_labels(%w[feira])

      ler('pessoas')

      expect(response.parsed_body).to eq(
        'total' => 1, 'tem_mais' => false,
        'itens' => [{
          'id' => ana.id, 'name' => 'Ana Albuquerino', 'email' => 'ana.albuquerino@exemplo.com.br',
          'phone_number' => '+5511910310001', 'thumbnail' => '', 'blocked' => false, 'contact_type' => 'customer',
          'customer_since' => (agora - 20.days).to_i, 'last_activity_at' => (agora - 2.days).to_i,
          'created_at' => (agora - 40.days).to_i,
          'additional_attributes' => { 'city' => 'Campinas', 'company_name' => 'Padaria Bom Dia' },
          'custom_attributes' => { 'cpf' => '123.456.789-00' }, 'labels' => %w[feira],
          'opted_out_at' => (agora - 1.day).to_i, 'opt_out_source' => 'manual'
        }]
      )
    end

    it 'manda a empresa da pessoa só com Empresas ligado na conta, como o contato de hoje' do
      account.enable_features!('companies')
      empresa = create(:company, account: account)
      pessoa('Ana Albuquerino', company_id: empresa.id)

      ler('pessoas')

      expect(response.parsed_body['itens'].first).to include('company_id' => empresa.id)
    end

    it 'quem nunca conversou vem com a última conversa vazia' do
      pessoa('Bruno Brandolim')

      ler('pessoas')

      expect(response.parsed_body['itens'].first).to include('last_activity_at' => nil, 'opted_out_at' => nil, 'labels' => [])
    end

    it 'aceita grupo, busca, ordem, página e filtros' do
      pessoa('Ana Albuquerino', contact_type: :customer, additional_attributes: { city: 'Campinas' })
      pessoa('Aná Brandolim', contact_type: :customer, additional_attributes: { city: 'Santos' })
      pessoa('Ana Carvalhedo', additional_attributes: { city: 'Campinas' })

      ler('pessoas', grupo: 'clientes', busca: 'ana', ordem: 'nome', pagina: 1, filtros: { cidade: 'Campinas' })

      expect(response.parsed_body['itens'].pluck('name')).to eq(['Ana Albuquerino'])
      expect(response.parsed_body).to include('total' => 1, 'tem_mais' => false)
    end

    it 'responde 422 com mensagem clara para grupo ou ordem que não existem' do
      ler('pessoas', grupo: 'vips')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'grupo desconhecido: vips')

      ler('pessoas', ordem: 'aleatoria')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'ordem desconhecida: aleatoria')
    end

    it 'responde 422 para página que não cabe no banco' do
      ler('pessoas', pagina: '99999999999999999999')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'pagina inválida: 99999999999999999999')
    end

    it 'não faz uma consulta a mais por pessoa (etiquetas e foto)' do
      criar = ->(nome) { create(:contact, :with_avatar, account: account, name: nome, contact_type: :lead).update_labels(%w[feira]) }
      2.times { |n| criar.call("Pessoa #{n}") }
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/pessoas", headers: cabecalhos }
      pedir.call
      com_duas = consultas_feitas(&pedir)
      3.times { |n| criar.call("Outra #{n}") }

      expect(consultas_feitas(&pedir)).to eq(com_duas)
      expect(response.parsed_body['itens'].pluck('labels')).to all(eq(%w[feira]))
      expect(response.parsed_body['itens'].pluck('thumbnail')).to all(be_present)
    end

    it 'não mostra gente de outra conta' do
      pessoa('Ana Albuquerino')
      create(:contact, account: create(:account), name: 'Ana de outra conta', contact_type: :lead)

      ler('pessoas')

      expect(response.parsed_body['itens'].pluck('name')).to eq(['Ana Albuquerino'])
    end

    it 'não deixa ler a conta de outra pessoa' do
      outra = create(:account)
      outra.enable_features!('relacionamentos_novo')

      get "/api/v1/accounts/#{outra.id}/relacionamentos/pessoas", headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET pessoas/contagens' do
    it 'devolve o número de cada grupo, respeitando busca e filtros' do
      pessoa('Ana Albuquerino', contact_type: :customer, last_activity_at: agora - 2.days)
      pessoa('Ana Brandolim', last_activity_at: agora - 45.days)
      pessoa('Bruno Carvalhedo')

      ler('pessoas/contagens', busca: 'ana')

      expect(response.parsed_body).to eq(
        'todos' => 2, 'clientes' => 1, 'falou_ha_pouco' => 1, 'sumiu_1_a_3_meses' => 1, 'sumiu_mais_de_3_meses' => 0,
        'nunca_conversou' => 0, 'nao_quer_mensagens' => 0
      )
    end
  end

  describe 'GET pessoas/todas' do
    it 'devolve a consulta inteira, só com o que as ações em grupo leem' do
      ana = pessoa('Ana Albuquerino', phone_number: '+5511910310001', opted_out_at: agora - 1.day, opt_out_source: 'manual')
      bruno = pessoa('Bruno Brandolim', blocked: true)
      carla = pessoa('Carla Carvalhedo', contact_type: :customer)

      ler('pessoas/todas', busca: 'a', ordem: 'nome', grupo: 'todos', pagina: 7)

      expect(response.parsed_body).to eq(
        'total' => 3,
        'itens' => [
          { 'id' => ana.id, 'name' => 'Ana Albuquerino', 'phone_number' => '+5511910310001', 'blocked' => false,
            'opted_out_at' => (agora - 1.day).to_i },
          { 'id' => bruno.id, 'name' => 'Bruno Brandolim', 'phone_number' => nil, 'blocked' => true, 'opted_out_at' => nil },
          { 'id' => carla.id, 'name' => 'Carla Carvalhedo', 'phone_number' => nil, 'blocked' => false, 'opted_out_at' => nil }
        ]
      )
    end
  end

  # Os quatro filtros com os nomes que a tela manda (fonte/listaFonte.js): trocar um nome de um lado só vira 422 aqui.
  it 'aceita os filtros como a tela manda, nas três leituras de pessoas' do
    pessoa('Ana Albuquerino')
    filtros = { empresa: '1', etiqueta: 'feira', cidade: 'Campinas', chegou_em: 'ultimos_30' }

    %w[pessoas pessoas/contagens pessoas/todas].each do |caminho|
      ler(caminho, grupo: 'todos', busca: 'ana', filtros: filtros)

      expect(response).to have_http_status(:ok), "#{caminho}: #{response.body}"
    end
  end

  # O permit do Rails descarta em silêncio o que chega no formato errado; sem a conferência, o pedido seguiria sem filtro
  # e "Marcar todas" marcaria a base inteira.
  describe 'pedido malformado' do
    let(:malformados) do
      { { grupo: ['clientes'] } => 'grupo em formato inválido', { busca: { a: 'b' } } => 'busca em formato inválido',
        { ordem: ['nome'] } => 'ordem em formato inválido', { pagina: ['2'] } => 'pagina em formato inválido',
        { filtros: 'abc' } => 'filtros em formato inválido', { filtros: { inventado: 1 } } => 'filtro desconhecido: inventado',
        { filtros: { cidade: ['Campinas'] } } => 'filtros[cidade] em formato inválido' }
    end

    before { pessoa('Ana Albuquerino') }

    %w[pessoas pessoas/contagens pessoas/todas].each do |caminho|
      it "responde 422 em #{caminho}, em vez de seguir sem filtro" do
        malformados.each do |params, mensagem|
          ler(caminho, **params)

          expect(response).to have_http_status(:unprocessable_entity), params.to_s
          expect(response.parsed_body).to eq('error' => mensagem)
        end
      end
    end
  end

  describe 'GET resumo' do
    it 'conta as pessoas, os clientes e quem sumiu há 1 a 3 meses' do
      pessoa('Ana Albuquerino', contact_type: :customer, last_activity_at: agora - 2.days)
      pessoa('Bruno Brandolim', contact_type: :customer, last_activity_at: agora - 45.days)
      pessoa('Carla Carvalhedo', last_activity_at: agora - 60.days)
      pessoa('Diego Dornelaz')

      ler('resumo')

      expect(response.parsed_body).to include('total' => 4, 'clientes' => 2, 'sumiu_1_a_3_meses' => 2)
      expect(response.parsed_body['empresas'].keys).to contain_exactly('total', 'sem_conversa_3_meses')
    end
  end

  describe 'GET opcoes_de_filtro' do
    it 'oferece só as etiquetas e cidades que existem nas pessoas da conta, em ordem' do
      pessoa('Ana Albuquerino', additional_attributes: { city: 'Santos' }).update_labels(%w[site feira])
      pessoa('Bruno Brandolim', additional_attributes: { city: 'Campinas' }).update_labels(%w[feira])
      pessoa('Carla Carvalhedo', additional_attributes: { city: '' })
      create(:contact, account: create(:account), contact_type: :lead, additional_attributes: { city: 'Recife' }).update_labels(%w[evento])
      create(:conversation, account: account).update_labels(%w[so-de-conversa])

      ler('opcoes_de_filtro')

      expect(response.parsed_body).to include(
        'etiquetas' => [{ 'value' => 'feira', 'label' => 'feira' }, { 'value' => 'site', 'label' => 'site' }],
        'cidades' => [{ 'value' => 'Campinas', 'label' => 'Campinas' }, { 'value' => 'Santos', 'label' => 'Santos' }]
      )
      expect(response.parsed_body['empresas']).to be_an(Array)
    end
  end
end
