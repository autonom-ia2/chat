require 'rails_helper'

# #2894 — a parte da Lista nova de Relacionamentos que depende do Enterprise: a aba Empresas, as empresas no resumo e na
# gaveta de filtros, e a permissão por função personalizada (a mesma de ver contatos e empresas hoje).
RSpec.describe 'Lista de Relacionamentos: empresas e funções', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }
  let(:leituras_de_empresa) { %w[empresas empresas/contagens] }
  let(:leituras) { %w[pessoas pessoas/contagens pessoas/todas resumo opcoes_de_filtro] + leituras_de_empresa }

  before do
    account.enable_features!('relacionamentos_novo', 'companies')
    travel_to(agora)
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def empresa(nome, **dados)
    create(:company, account: account, name: nome, domain: nil, **dados)
  end

  def pessoa_da(empresa, **dados)
    create(:contact, account: account, company: empresa, contact_type: :lead, **dados)
  end

  describe 'aba Empresas' do
    it 'responde 401 sem login' do
      leituras_de_empresa.each do |caminho|
        get "#{base}/#{caminho}"

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'responde 404 com a chave da conta desligada' do
      account.disable_features!('relacionamentos_novo')

      leituras_de_empresa.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:not_found), caminho
      end
    end

    it 'responde 403 sem Empresas ligado na conta, como a lista de empresas de hoje' do
      account.disable_features!('companies')

      leituras_de_empresa.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:forbidden), caminho
      end
    end

    it 'devolve a página com os campos que as telas leem' do
      padaria = empresa('Padaria Bom Dia', domain: 'padaria-bom-dia.exemplo.com.br', created_at: agora - 30.days,
                                           last_activity_at: agora - 2.days, additional_attributes: { cnpj: '12.345.678/0001-00', city: 'Campinas' })
      pessoa_da(padaria, contact_type: :customer)
      pessoa_da(padaria)

      ler('empresas')

      expect(response.parsed_body).to eq(
        'total' => 1, 'tem_mais' => false,
        'itens' => [{ 'id' => padaria.id, 'name' => 'Padaria Bom Dia', 'domain' => 'padaria-bom-dia.exemplo.com.br',
                      'cnpj' => '12.345.678/0001-00', 'created_at' => (agora - 30.days).to_i, 'contacts_count' => 2,
                      'customers_count' => 1, 'last_activity_at' => (agora - 2.days).to_i }]
      )
    end

    it 'aceita grupo, busca, ordem e página, e devolve as contagens' do
      pessoa_da(empresa('Padaria Ana'), contact_type: :customer)
      empresa('Padaria Bruno', last_activity_at: agora - 100.days)
      empresa('Oficina Carla')
      create(:company, account: create(:account), name: 'Padaria de outra conta')

      ler('empresas', grupo: 'sem_pessoas', busca: 'padaria', ordem: 'nome', pagina: 1)
      expect(response.parsed_body['itens'].pluck('name')).to eq(['Padaria Bruno'])

      ler('empresas/contagens', busca: 'padaria')
      expect(response.parsed_body).to eq('todas' => 2, 'com_clientes' => 1, 'sem_pessoas' => 1, 'sem_conversa_3_meses' => 2)
    end

    it 'responde 422 para pedido malformado e para filtro, que a aba Empresas não tem' do
      { { grupo: ['todas'] } => 'grupo em formato inválido', { busca: { a: 'b' } } => 'busca em formato inválido',
        { filtros: 'abc' } => 'filtros em formato inválido', { filtros: { cidade: 'Campinas' } } => 'filtro desconhecido: cidade',
        { pagina: '99999999999999999999' } => 'pagina inválida: 99999999999999999999' }.each do |params, mensagem|
        leituras_de_empresa.each do |caminho|
          ler(caminho, **params)

          expect(response).to have_http_status(:unprocessable_entity), "#{caminho} #{params}"
          expect(response.parsed_body).to eq('error' => mensagem)
        end
      end
    end

    it 'responde 422 para grupo que não é de empresa' do
      ler('empresas', grupo: 'clientes')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'grupo desconhecido: clientes')
    end
  end

  describe 'empresas no resumo e na gaveta de filtros' do
    before do
      empresa('Ótica Hortêncio', last_activity_at: agora - 100.days)
      empresa('Costura Fina', last_activity_at: agora - 5.days)
      empresa('mercado da Esquina')
      create(:company, account: create(:account), name: 'De outra conta')
    end

    it 'o resumo conta as empresas e as que estão sem conversa há 3 meses' do
      ler('resumo')

      expect(response.parsed_body['empresas']).to eq('total' => 3, 'sem_conversa_3_meses' => 2)
    end

    it 'a gaveta oferece todas as empresas da conta, por nome' do
      ler('opcoes_de_filtro')

      expect(response.parsed_body['empresas'].pluck('label')).to eq(['Costura Fina', 'mercado da Esquina', 'Ótica Hortêncio'])
      expect(response.parsed_body['empresas'].pluck('value')).to all(be_an(Integer))
    end

    it 'sem Empresas ligado na conta, o resumo e a gaveta vêm sem empresa nenhuma' do
      account.disable_features!('companies')

      ler('resumo')
      expect(response.parsed_body['empresas']).to eq('total' => 0, 'sem_conversa_3_meses' => 0)

      ler('opcoes_de_filtro')
      expect(response.parsed_body['empresas']).to eq([])
    end
  end

  describe 'funções personalizadas' do
    it 'recusa a função sem a chave de contatos em todas as leituras' do
      sem_contatos = pessoa_com(%w[conversation_participating_manage])

      leituras.each do |caminho|
        ler(caminho, quem: sem_contatos)

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'atende a função com contact_view, o administrador e o agente sem função' do
      [pessoa_com(%w[contact_view]), create(:user, account: account, role: :administrator), agente].each do |quem|
        leituras.each do |caminho|
          ler(caminho, quem: quem)

          expect(response).to have_http_status(:ok), "#{caminho} (#{quem.id})"
        end
      end
    end
  end
end
