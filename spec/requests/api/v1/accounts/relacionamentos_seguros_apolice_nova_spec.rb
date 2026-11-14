require 'rails_helper'

# E5 (#2898) — "Apólice nova" feita à mão, a partir do seguro que ela renovou: nasce um seguro novo da mesma pessoa,
# ligado ao anterior, e o anterior fica renovado. A recusa é um código em `error`, e o corpo nunca repete o que foi
# mandado. Tudo fictício.
RSpec.describe 'Carteira de seguros: apólice nova à mão', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Bia Exemplo') }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/relacionamentos/seguros" }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:anterior) do
    criar_apolice(marina, numero: 'EX-000001', tipo: 'auto', bem: 'Carro Exemplo 2022', inicio_vigencia: Date.new(2025, 12, 2),
                          fim_vigencia: Date.new(2026, 12, 2))
  end
  let(:da_nova) do
    { anteriorId: anterior.id, tipo: 'auto', seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', comeca: '2026-12-02',
      termina: '2027-12-02', valor: 3650.5, bem: 'Carro Exemplo 2022' }
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    anterior
  end

  def guardar(dados = da_nova, quem: admin, onde: caminho)
    post onde, params: dados, headers: quem.create_new_auth_token, as: :json
  end

  def recusa
    [response.status, response.parsed_body]
  end

  def seguros
    Carteira::Apolice.where(account_id: account.id)
  end

  def nova
    seguros.find_by(numero: 'OS-777001')
  end

  describe 'guardar' do
    it 'cria o seguro da mesma pessoa, feito à mão, ligado ao anterior, e devolve o seguro novo' do
      guardar

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'id' => nova.id, 'pessoaId' => marina.id, 'tipo' => 'auto', 'seguradora' => 'Outra Seguradora Exemplo', 'numero' => 'OS-777001',
        'comeca' => '2026-12-02', 'termina' => '2027-12-02', 'valor' => 3650.5, 'bem' => 'Carro Exemplo 2022', 'selo' => 'ativo',
        'apoliceNova' => false, 'renovacao' => nil, 'renovadoEm' => nil
      )
      expect(response.parsed_body['origem']).to include('tipo' => 'manual')
      expect(nova).to have_attributes(apolice_anterior_id: anterior.id, contact_id: marina.id, company_id: nil, origem: 'manual',
                                      seguradora_chave: 'outraseguradoraexemplo', numero_chave: 'OS777001', valor_centavos: 365_050)
      expect(nova.eventos.sole).to have_attributes(tipo: 'apolice_nova', user_id: admin.id, valores: { 'anterior' => 'EX-000001' })
    end

    it 'o anterior sem card de renovação fica renovado, com o passo na história' do
      guardar

      expect(anterior.reload).to have_attributes(renovado_em: agora, nao_renovou_em: nil)
      expect(anterior.eventos.sole).to have_attributes(tipo: 'renovou', user_id: admin.id)
    end

    it 'o anterior passa a dizer que a apólice nova dele já está guardada' do
      ler_o_anterior = lambda do
        get "#{caminho}/#{anterior.id}", headers: admin.create_new_auth_token
        response.parsed_body.slice('selo', 'apoliceNova')
      end
      antes = ler_o_anterior.call

      guardar

      expect([antes, ler_o_anterior.call]).to eq([{ 'selo' => 'ativo', 'apoliceNova' => false }, { 'selo' => 'renovado', 'apoliceNova' => true }])
    end

    it 'o card de renovação aberto do anterior fecha como ganho, e é ele que deixa o anterior renovado' do
      card = por_em_renovacao(anterior, ajustes)

      guardar

      expect(response).to have_http_status(:created)
      expect(card.reload.status).to eq('won')
      expect(anterior.reload.renovado_em).to eq(agora)
      expect(anterior.eventos.order(:id).pluck(:tipo)).to eq(%w[renovacao_card_nasceu renovou])
    end

    it 'o anterior que já estava como "Renovou" só ganha a apólice nova' do
      card = por_em_renovacao(anterior, ajustes)
      Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform
      atividades = card.activities.count
      travel 2.days

      guardar

      expect(response).to have_http_status(:created)
      expect([anterior.reload.renovado_em, card.activities.count]).to eq([agora, atividades])
      expect(nova.apolice_anterior_id).to eq(anterior.id)
    end

    it 'o segurado empresa do anterior continua sendo o do novo' do
      account.enable_features!('companies')
      empresa = create(:company, account: account, name: 'Empresa Exemplo')
      anterior.update!(company: empresa)

      guardar

      expect(nova.company_id).to eq(empresa.id)
      expect(response.parsed_body['segurado']).to include('tipo' => 'empresa', 'id' => empresa.id)
    end

    it 'só a seguradora, o tipo e o fim são obrigatórios: o que vem vazio fica sem' do
      guardar({ anteriorId: anterior.id, tipo: 'auto', seguradora: 'Outra Seguradora Exemplo', termina: '2027-12-02', numero: '', bem: '' })

      novo = seguros.where.not(id: anterior.id).sole
      expect(response).to have_http_status(:created)
      expect(novo).to have_attributes(numero: nil, numero_chave: nil, inicio_vigencia: nil, valor_centavos: nil, bem: nil)
    end

    it 'o agente comum, que edita contatos, também guarda' do
      guardar(da_nova, quem: agente)

      expect(response).to have_http_status(:created)
      expect(nova.eventos.sole.user_id).to eq(agente.id)
    end

    # A seguradora manteve o número: é outro termo da mesma apólice (Carteira::Termo), e é a linha nova que se liga.
    it 'a renovação que mantém a seguradora e o número nasce como outra linha, ligada à anterior, que não é mexida' do
      comecos = { 'EX-000011' => '2026-12-02', 'EX-000012' => '2026-11-20', 'EX-000013' => nil }
      anteriores = comecos.keys.map do |numero|
        criar_apolice(marina, numero: numero, tipo: 'auto', inicio_vigencia: Date.new(2025, 12, 2), fim_vigencia: Date.new(2026, 12, 2))
      end

      respostas = anteriores.map do |antiga|
        guardar(da_nova.merge(anteriorId: antiga.id, seguradora: 'Seguradora Exemplo', numero: antiga.numero, comeca: comecos[antiga.numero]))
        response.status
      end

      novas = anteriores.map { |antiga| seguros.find_by(apolice_anterior_id: antiga.id) }
      expect(respostas).to eq([201, 201, 201])
      expect(novas.map { |novo| [novo.numero, novo.inicio_vigencia&.iso8601, novo.fim_vigencia.iso8601, novo.origem] }).to eq(
        [%w[EX-000011 2026-12-02 2027-12-02 manual], %w[EX-000012 2026-11-20 2027-12-02 manual], ['EX-000013', nil, '2027-12-02', 'manual']]
      )
      expect(anteriores.map { |antiga| antiga.reload.slice(:inicio_vigencia, :fim_vigencia, :renovado_em, :origem).values }).to all(
        eq([Date.new(2025, 12, 2), Date.new(2026, 12, 2), agora, 'planilha'])
      )
    end
  end

  describe 'recusas' do
    def nada_mudou
      [seguros.count, anterior.reload.renovado_em, anterior.eventos.count] == [1, nil, 0]
    end

    it 'recusa o anterior que não existe, o de outra conta e o que não é um id' do
      outra = conta_com_carteira
      de_fora = criar_apolice(create(:contact, account: outra), numero: 'EX-000009', fim_vigencia: Date.new(2026, 12, 2))

      respostas = [0, de_fora.id, 'abc', nil].map do |id|
        guardar(da_nova.merge(anteriorId: id))
        recusa
      end

      expect(respostas).to all(eq([422, { 'error' => 'anterior_desconhecida' }]))
      expect([nada_mudou, Carteira::Apolice.where(account_id: outra.id).count]).to eq([true, 1])
    end

    it 'recusa o que falta e o que não dá para ler, sem repetir o que veio' do
      pedidos = {
        { tipo: nil } => 'falta_tipo', { seguradora: ' ' } => 'falta_seguradora', { termina: '' } => 'falta_termina',
        { tipo: 'moto' } => 'tipo_desconhecido', { seguradora: '---' } => 'falta_seguradora', { termina: '02/12/2027' } => 'data_invalida',
        { comeca: '2026-13-01' } => 'data_invalida', { valor: 'caro' } => 'valor_invalido', { valor: -1 } => 'valor_invalido',
        { comeca: '2027-12-03' } => 'termina_antes', { comeca: nil, termina: '2026-12-02' } => 'termina_antes_da_anterior',
        { outro: 1 } => 'pedido_invalido', { tipo: ['auto'] } => 'pedido_invalido'
      }

      respostas = pedidos.keys.map do |mudanca|
        guardar(da_nova.merge(mudanca))
        recusa
      end

      expect(respostas).to eq(pedidos.values.map { |codigo| [422, { 'error' => codigo }] })
      expect(nada_mudou).to be(true)
    end

    it 'recusa quando o anterior foi cancelado, está como "não renovou" ou já tem a apólice nova' do
      anterior.update!(cancelado_em: agora)
      guardar
      cancelado = recusa
      anterior.update!(cancelado_em: nil, nao_renovou_em: agora)
      guardar
      nao_renovou = recusa
      anterior.update!(nao_renovou_em: nil)
      guardar
      guardar(da_nova.merge(numero: 'OS-777002'))

      expect([cancelado, nao_renovou, recusa]).to eq(
        [[422, { 'error' => 'anterior_cancelada' }], [422, { 'error' => 'ja_tem_desfecho' }], [422, { 'error' => 'ja_tem_apolice_nova' }]]
      )
      expect(seguros.pluck(:numero)).to contain_exactly('EX-000001', 'OS-777001')
    end

    it 'recusa a apólice que a conta já tem, sem mexer nela nem no anterior' do
      guardada = criar_apolice(marina, seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', tipo: 'vida', bem: 'Outro item',
                                       inicio_vigencia: Date.new(2026, 12, 2), fim_vigencia: Date.new(2027, 12, 2))
      antes = guardada.reload.attributes

      guardar

      expect(recusa).to eq([422, { 'error' => 'apolice_repetida' }])
      expect([guardada.reload.attributes, guardada.eventos.count, seguros.count]).to eq([antes, 0, 2])
      expect([anterior.reload.renovado_em, anterior.eventos.count]).to eq([nil, 0])
    end

    it 'recusa a apólice que a conta já tem marcada como cancelada: ela não é mexida nem vira a apólice nova' do
      cancelada = criar_apolice(marina, seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', inicio_vigencia: Date.new(2026, 12, 2),
                                        fim_vigencia: Date.new(2027, 12, 2), cancelado_em: agora)
      antes = cancelada.reload.attributes

      guardar

      expect(recusa).to eq([422, { 'error' => 'apolice_cancelada' }])
      expect([cancelada.reload.attributes, cancelada.eventos.count, seguros.count]).to eq([antes, 0, 2])
      expect([anterior.reload.renovado_em, anterior.eventos.count]).to eq([nil, 0])
    end

    it 'o mesmo número com o mesmo começo da anterior é a própria anterior: recusa como repetida, e ela não é mexida' do
      antes = anterior.reload.attributes

      guardar(da_nova.merge(seguradora: 'Seguradora Exemplo', numero: 'EX-000001', comeca: '2025-12-02'))

      expect(recusa).to eq([422, { 'error' => 'apolice_repetida' }])
      expect([anterior.reload.attributes, nada_mudou]).to eq([antes, true])
    end

    it 'recusa a apólice que já está guardada para outra pessoa, sem mudar o dono nem o anterior' do
      caio = create(:contact, account: account, name: 'Caio Exemplo', phone_number: '+5511900000024')
      de_outro = criar_apolice(caio, seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', fim_vigencia: Date.new(2027, 12, 2))
      antes = de_outro.reload.attributes

      guardar

      expect(recusa).to eq([422, { 'error' => 'apolice_de_outra_pessoa' }])
      expect([de_outro.reload.attributes, de_outro.eventos.count, seguros.count]).to eq([antes, 0, 2])
      expect([anterior.reload.renovado_em, anterior.eventos.count]).to eq([nil, 0])
    end

    it 'recusa quando duas vigências guardadas da mesma apólice podem ser a digitada, sem escolher uma' do
      guardadas = [Date.new(2027, 6, 2), Date.new(2027, 9, 2)].map do |fim|
        criar_apolice(marina, seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', inicio_vigencia: Date.new(2026, 12, 2),
                              fim_vigencia: fim)
      end
      antes = guardadas.map { |guardada| guardada.reload.attributes }

      guardar

      expect(recusa).to eq([422, { 'error' => 'termo_ambiguo' }])
      expect([guardadas.map { |guardada| guardada.reload.attributes }, seguros.count]).to eq([antes, 3])
      expect([anterior.reload.renovado_em, anterior.eventos.count]).to eq([nil, 0])
    end
  end

  describe 'em toda conta' do
    it 'responde 401 sem login e 404 sem a carteira' do
      post caminho, params: da_nova, as: :json
      sem_login = response.status
      account.disable_features!('carteira_seguros')
      guardar

      expect([sem_login, response.status, seguros.count]).to eq([401, 404, 1])
    end

    it 'quem é de outra conta não usa o seguro desta como anterior' do
      outra = conta_com_carteira
      dona = create(:user, account: outra, role: :administrator)

      guardar(da_nova, quem: dona, onde: "/api/v1/accounts/#{outra.id}/relacionamentos/seguros")

      expect(recusa).to eq([422, { 'error' => 'anterior_desconhecida' }])
      expect([Carteira::Apolice.count, anterior.reload.renovado_em]).to eq([1, nil])
    end
  end
end
