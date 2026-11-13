require 'rails_helper'

# E4 (#2897) — a carteira de seguros na lista de pessoas de Relacionamentos, pelo caminho que a tela usa: o selo de
# seguro das pessoas da página (seguros/resumo_por_dono), o grupo "Só tem um seguro" e a busca pelo número da apólice e
# pelo bem. A regra de cada um está em spec/services (carteira/resumo_por_pessoa_spec.rb e
# relacionamentos/consulta_de_pessoas_spec.rb). Tudo fictício.
RSpec.describe 'Carteira de seguros na lista de pessoas', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:marina) { pessoa('Marina Exemplo') }
  let(:bruno) { pessoa('Bruno Exemplo') }
  let(:carla) { pessoa('Carla Sem Seguro') }

  before do
    travel_to(agora)
    criar_apolice(marina, numero: 'EX-001234', tipo: 'auto', fim_vigencia: hoje + 18, bem: 'Carro Exemplo 2022')
    criar_apolice(bruno, numero: 'EX-005678', tipo: 'residencial', fim_vigencia: hoje + 200)
    criar_apolice(bruno, numero: 'EX-005679', tipo: 'vida', fim_vigencia: hoje - 2)
    carla
  end

  def pessoa(nome, conta: account)
    create(:contact, account: conta, name: nome, contact_type: :customer)
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def nomes(**params)
    ler('pessoas', **params)
    response.parsed_body['itens'].pluck('name')
  end

  describe 'GET seguros/resumo_por_dono' do
    it 'devolve, por pessoa da página, quantos seguros ela tem e o selo do que mais pede atenção' do
      ler('seguros/resumo_por_dono', pessoa_ids: [marina.id, bruno.id, carla.id])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        marina.id.to_s => { 'quantos' => 1, 'selo' => 'ativo', 'tipo' => 'auto', 'dias' => 18 },
        bruno.id.to_s => { 'quantos' => 2, 'selo' => 'vencido', 'tipo' => 'vida', 'dias' => -2 }
      )
    end

    it 'responde 401 sem login e 404 na conta sem a carteira' do
      get "#{base}/seguros/resumo_por_dono", params: { pessoa_ids: [marina.id] }
      expect(response).to have_http_status(:unauthorized)

      account.disable_features!('carteira_seguros')
      ler('seguros/resumo_por_dono', pessoa_ids: [marina.id])
      expect(response).to have_http_status(:not_found)
    end

    it 'não devolve nada de pessoa de outra conta' do
      outra = conta_com_carteira
      de_fora = pessoa('Dona de fora', conta: outra)
      criar_apolice(de_fora, numero: 'EX-777777')

      ler('seguros/resumo_por_dono', pessoa_ids: [de_fora.id])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it 'responde 422, sem repetir o que foi mandado, para o pedido que a leitura não conhece' do
      [{}, { pessoa_ids: 'Marina Exemplo' }, { pessoa_ids: ['Marina Exemplo'] }, { pessoa_ids: [marina.id], busca: 'Marina Exemplo' },
       { pessoa_ids: { a: marina.id } }].each do |pedido|
        ler('seguros/resumo_por_dono', **pedido)

        expect(response).to have_http_status(:unprocessable_entity), pedido.inspect
        expect(response.parsed_body).to eq('error' => 'pedido_invalido')
      end
    end
  end

  describe 'GET pessoas, na conta com a carteira' do
    it 'tem o grupo "Só tem um seguro", na lista, nos números dos grupos e em "Marcar todas"' do
      expect(nomes(grupo: 'so_um_seguro')).to contain_exactly('Marina Exemplo', 'Bruno Exemplo')
      ler('pessoas/contagens')
      expect(response.parsed_body).to include('todos' => 3, 'clientes' => 3, 'so_um_seguro' => 2)
      ler('pessoas/todas', grupo: 'so_um_seguro')
      expect(response.parsed_body['itens'].pluck('name')).to contain_exactly('Marina Exemplo', 'Bruno Exemplo')
    end

    it 'acha a pessoa pelo número da apólice e pelo bem segurado' do
      expect(nomes(busca: 'EX-001234')).to eq(['Marina Exemplo'])
      expect(nomes(busca: '005679')).to eq(['Bruno Exemplo'])
      expect(nomes(busca: 'carro exemplo')).to eq(['Marina Exemplo'])
    end
  end

  describe 'GET pessoas, na conta sem a carteira' do
    before { account.disable_features!('carteira_seguros') }

    it 'não tem o grupo nem procura nos seguros: a lista fica como era' do
      ler('pessoas', grupo: 'so_um_seguro')
      expect(response).to have_http_status(:unprocessable_entity)

      ler('pessoas/contagens')
      expect(response.parsed_body.keys).to eq(Relacionamentos::ConsultaDePessoas::GRUPOS.keys)
      expect(nomes(busca: 'EX-001234')).to be_empty
      expect(nomes).to contain_exactly('Marina Exemplo', 'Bruno Exemplo', 'Carla Sem Seguro')
    end
  end
end
