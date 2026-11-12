require 'rails_helper'

# #2894 — a consulta da aba Empresas da Lista nova de Relacionamentos, com a regra da demonstração da tela
# (relacionamentos/fonte/grupos.js e listaFonte.js).
RSpec.describe Relacionamentos::ConsultaDeEmpresas do
  let(:account) { create(:account) }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }

  before { travel_to(agora) }

  def empresa(nome, **dados)
    create(:company, account: account, name: nome, domain: nil, **dados)
  end

  def pessoa_da(empresa, **dados)
    create(:contact, account: account, company: empresa, contact_type: :lead, **dados)
  end

  def consulta(**pedido)
    described_class.new(account, pedido)
  end

  def nomes(**pedido)
    consulta(**pedido).itens.map(&:name)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  describe 'grupos' do
    it '"sem conversa há 3 meses" começa depois de 90 dias exatos e inclui quem nunca conversou' do
      { 'há 89 dias' => 89.days, 'há 90 dias' => 90.days, 'há 90 dias e 1 segundo' => 90.days + 1.second,
        'há 91 dias' => 91.days }.each { |nome, tempo| empresa(nome, last_activity_at: agora - tempo) }
      empresa('nunca conversou')

      expect(nomes(grupo: 'sem_conversa_3_meses')).to contain_exactly('há 90 dias e 1 segundo', 'há 91 dias', 'nunca conversou')
    end

    it 'separa as que têm cliente das que não têm ninguém' do
      com_cliente = empresa('Com cliente')
      pessoa_da(com_cliente, contact_type: :customer)
      pessoa_da(com_cliente)
      pessoa_da(empresa('Só com gente'))
      empresa('Vazia')

      expect(nomes(grupo: 'com_clientes')).to contain_exactly('Com cliente')
      expect(nomes(grupo: 'sem_pessoas')).to contain_exactly('Vazia')
      expect(nomes(grupo: 'todas')).to contain_exactly('Com cliente', 'Só com gente', 'Vazia')
      expect(nomes).to contain_exactly('Com cliente', 'Só com gente', 'Vazia')
    end
  end

  it 'conta as pessoas e os clientes de cada empresa' do
    com_cliente = empresa('Com cliente')
    2.times { pessoa_da(com_cliente, contact_type: :customer) }
    pessoa_da(com_cliente)
    empresa('Vazia')

    contagem = consulta(ordem: 'nome').itens.map { |item| [item.name, item.contacts_count, item.customers_count] }

    expect(contagem).to eq([['Com cliente', 3, 2], ['Vazia', 0, 0]])
  end

  # O modelo não impede o contato de uma conta de apontar para a empresa de outra; a conta do contato decide.
  it 'cliente de outra conta apontando para a empresa não conta como cliente dela' do
    create(:contact, account: create(:account), company: empresa('Padaria Ana'), contact_type: :customer)

    expect(consulta.itens.map { |item| [item.name, item.customers_count] }).to eq([['Padaria Ana', 0]])
    expect(nomes(grupo: 'com_clientes')).to be_empty
    expect(consulta.contagens).to include('com_clientes' => 0)
  end

  describe 'busca' do
    before do
      empresa('Padaria Pão de Açúcar', domain: 'padaria-bom-dia.exemplo.com.br')
      empresa('Oficina 4321', additional_attributes: { cnpj: '12.345.678/0001-00' })
    end

    it 'acha pelo nome sem acento e pelo domínio' do
      expect(nomes(busca: 'PAO DE ACUCAR')).to contain_exactly('Padaria Pão de Açúcar')
      expect(nomes(busca: 'bom-dia.exemplo')).to contain_exactly('Padaria Pão de Açúcar')
    end

    it 'só número procura no CNPJ, com ou sem pontuação, e não no nome' do
      expect(nomes(busca: '12345678000100')).to contain_exactly('Oficina 4321')
      expect(nomes(busca: '12.345.678/0001-00')).to contain_exactly('Oficina 4321')
      expect(nomes(busca: '4321')).to be_empty
    end
  end

  describe 'ordem' do
    before do
      empresa('Ótica Hortêncio', last_activity_at: agora - 2.days, created_at: agora - 1.hour)
      empresa('mercado da Esquina', last_activity_at: agora - 1.day, created_at: agora - 8.days)
      empresa('Costura Fina', created_at: agora - 1.day)
    end

    it 'por padrão, a última conversa primeiro e quem nunca conversou no fim' do
      expect(nomes).to eq(['mercado da Esquina', 'Ótica Hortêncio', 'Costura Fina'])
    end

    it 'por nome, sem diferença de acento nem de maiúscula' do
      expect(nomes(ordem: 'nome')).to eq(['Costura Fina', 'mercado da Esquina', 'Ótica Hortêncio'])
    end

    it 'as mais novas primeiro' do
      expect(nomes(ordem: 'mais_novos')).to eq(['Ótica Hortêncio', 'Costura Fina', 'mercado da Esquina'])
    end
  end

  describe 'página e contagens' do
    before do
      stub_const('Relacionamentos::Consulta::POR_PAGINA', 2)
      pessoa_da(empresa('Padaria Ana'), contact_type: :customer)
      pessoa_da(empresa('Padaria Bruno', last_activity_at: agora - 100.days))
      empresa('Padaria Carla', last_activity_at: agora - 5.days)
      empresa('Oficina Diego')
      create(:company, account: create(:account), name: 'Padaria de outra conta')
    end

    it 'devolve uma página por vez, com o total e se tem mais' do
      primeira = consulta(ordem: 'nome', busca: 'padaria')
      segunda = consulta(ordem: 'nome', busca: 'padaria', pagina: '2')

      expect(primeira.itens.map(&:name)).to eq(['Padaria Ana', 'Padaria Bruno'])
      expect([primeira.total, primeira.tem_mais?]).to eq([3, true])
      expect(segunda.itens.map(&:name)).to eq(['Padaria Carla'])
      expect([segunda.total, segunda.tem_mais?]).to eq([3, false])
      expect(consulta(pagina: '9').itens).to be_empty
    end

    it 'conta cada grupo respeitando a busca, numa consulta só, e o número bate com o total da lista' do
      contando = consulta(busca: 'padaria')
      contagens = nil

      expect(consultas_feitas { contagens = contando.contagens }).to eq(1)
      expect(contagens).to eq('todas' => 3, 'com_clientes' => 1, 'sem_pessoas' => 1, 'sem_conversa_3_meses' => 2)
      contagens.each do |grupo, numero|
        expect(consulta(grupo: grupo, busca: 'padaria').total).to eq(numero), "grupo #{grupo}"
      end
    end
  end

  it 'recusa grupo e ordem que não existem, dizendo qual' do
    expect { consulta(grupo: 'clientes') }.to raise_error(Relacionamentos::PedidoInvalido, 'grupo desconhecido: clientes')
    expect { consulta(ordem: 'aleatoria') }.to raise_error(Relacionamentos::PedidoInvalido, 'ordem desconhecida: aleatoria')
  end
end
