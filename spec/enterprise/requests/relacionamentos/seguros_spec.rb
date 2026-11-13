require 'rails_helper'

# E4 (#2897) — a parte da carteira de seguros que depende do Enterprise: o que a função personalizada muda (ver seguro é
# ver contatos, mudar é editar contatos, sem chave nova) e os seguros da ficha da empresa. Tudo fictício.
RSpec.describe 'Carteira de seguros: funções e empresa', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:caixa) { create(:inbox, account: account, enable_email_collect: false) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:seguro) { criar_apolice(marina, numero: 'EX-001234', fim_vigencia: Date.new(2026, 12, 16), bem: 'Carro Exemplo 2022') }
  let(:leituras) do
    %w[seguros seguros/todos seguros/contagens seguros/resumo seguros/opcoes_de_filtro] +
      ["seguros/#{seguro.id}", "seguros/#{seguro.id}/historia", "seguros/#{seguro.id}/pdf", "pessoas/#{marina.id}/seguros"]
  end

  before do
    account.enable_features!('companies')
    travel_to(agora)
    guardar_pdf_na(seguro)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: caixa)
    user
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def pdf_de_exemplo
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
  end

  # Cada escrita da gaveta, na ordem em que uma depende da outra (o seguro chega e sai com PDF e sem cancelamento).
  # Devolve o código de cada resposta.
  def escrever(quem)
    cabecalhos = -> { quem.create_new_auth_token }
    caminho = "#{base}/seguros/#{seguro.id}"
    pedidos = {
      'corrigir' => -> { patch caminho, params: { bem: 'Carro Exemplo 2023' }, headers: cabecalhos.call, as: :json },
      'cancelar' => -> { post "#{caminho}/cancelar", headers: cabecalhos.call, as: :json },
      'voltar a ativo' => -> { post "#{caminho}/voltar_a_ativo", headers: cabecalhos.call, as: :json },
      'tirar o PDF' => -> { delete "#{caminho}/pdf", headers: cabecalhos.call },
      'guardar o PDF' => -> { post "#{caminho}/pdf", params: { arquivo: pdf_de_exemplo }, headers: cabecalhos.call }
    }
    pedidos.transform_values do |pedir|
      pedir.call
      response.status
    end
  end

  describe 'funções personalizadas' do
    it 'a função sem a chave de contatos não lê nem escreve (401), nem os seguros do contato de uma conversa que ela vê' do
      sem_contatos = pessoa_com(%w[conversation_manage crm_view])
      create(:conversation, account: account, inbox: caixa, contact: marina)
      antes = seguro.reload.attributes

      leituras.each do |caminho|
        ler(caminho, quem: sem_contatos)

        expect(response).to have_http_status(:unauthorized), caminho
      end
      expect(escrever(sem_contatos).values.uniq).to eq([401])
      expect([seguro.reload.attributes, seguro.eventos.count, seguro.pdf.attached?]).to eq([antes, 0, true])
    end

    it 'a função com contact_view lê tudo e não escreve nada' do
      so_ve = pessoa_com(%w[contact_view])
      antes = seguro.reload.attributes

      leituras.each do |caminho|
        ler(caminho, quem: so_ve)

        expect(response).to have_http_status(:ok), caminho
      end
      expect(escrever(so_ve).values.uniq).to eq([401])
      expect([seguro.reload.attributes, seguro.eventos.count, seguro.pdf.attached?]).to eq([antes, 0, true])
    end

    it 'a função com contact_manage, o agente sem função e o administrador leem e escrevem' do
      [pessoa_com(%w[contact_manage]), agente, admin].each do |quem|
        leituras.each do |caminho|
          ler(caminho, quem: quem)

          expect(response).to have_http_status(:ok), "#{caminho} (#{quem.id})"
        end
        expect(escrever(quem).values.uniq).to eq([200]), quem.id.to_s
      end
    end
  end

  describe 'os seguros da empresa' do
    let(:oficina) { create(:company, account: account, name: 'Oficina Exemplo', domain: nil) }

    before { criar_apolice(marina, numero: 'EX-FROTA', company: oficina, tipo: 'empresarial', fim_vigencia: hoje + 20) }

    def da_empresa(empresa = oficina, quem: agente)
      ler("empresas/#{empresa.id}/seguros", quem: quem)
    end

    it 'traz só os seguros em que a empresa é o segurado, na ordem de urgência' do
      criar_apolice(marina, numero: 'EX-VENCIDO', company: oficina, fim_vigencia: hoje - 2)
      criar_apolice(marina, numero: 'EX-OUTRA', company: create(:company, account: account, name: 'Padaria Exemplo', domain: nil))

      da_empresa

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.pluck('numero', 'selo')).to eq([%w[EX-VENCIDO vencido], %w[EX-FROTA ativo]])
      expect(response.parsed_body.last).to include(
        'pessoaId' => marina.id, 'segurado' => { 'tipo' => 'empresa', 'id' => oficina.id, 'nome' => 'Oficina Exemplo', 'documento' => nil }
      )
    end

    it 'responde 404 sem a carteira, 403 sem Empresas ligado, 404 para empresa de outra conta e 422 para parâmetro desconhecido' do
      de_fora = create(:company, account: conta_com_carteira, name: 'Empresa de Outra Conta', domain: nil)

      da_empresa(de_fora)
      expect(response).to have_http_status(:not_found)
      ler("empresas/#{oficina.id}/seguros", busca: 'Oficina Exemplo')
      expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'pedido_invalido' }])
      account.disable_features!('companies')
      da_empresa
      expect(response).to have_http_status(:forbidden)
      account.disable_features!('carteira_seguros')
      da_empresa
      expect(response).to have_http_status(:not_found)
    end

    it 'pede a chave de contatos: sem ela 401, com contact_view 200' do
      da_empresa(quem: pessoa_com(%w[conversation_manage crm_view]))
      expect(response).to have_http_status(:unauthorized)

      da_empresa(quem: pessoa_com(%w[contact_view]))
      expect(response).to have_http_status(:ok)
    end

    it 'na aba Seguros, a busca acha pelo nome da empresa e a ordem por nome usa o segurado' do
      ler('seguros', busca: 'oficina')
      expect(response.parsed_body['itens'].pluck('numero')).to eq(%w[EX-FROTA])

      criar_apolice(create(:contact, account: account, name: 'Zélia Exemplo'), numero: 'EX-ZELIA')
      ler('seguros', ordem: 'nome')

      expect(response.parsed_body['itens'].map { |item| item.dig('segurado', 'nome') }).to eq(['Marina Exemplo', 'Oficina Exemplo', 'Zélia Exemplo'])
    end

    it 'não faz uma consulta a mais por seguro com empresa' do
      criar = ->(n) { criar_apolice(marina, company: create(:company, account: account, name: "Empresa Exemplo #{n}", domain: nil)) }
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/seguros", headers: cabecalhos }
      pedir.call
      com_duas = consultas_da_carteira(&pedir)
      3.times(&criar)

      expect(consultas_da_carteira(&pedir)).to eq(com_duas)
      expect(response.parsed_body['itens'].size).to eq(5)
    end
  end
end
