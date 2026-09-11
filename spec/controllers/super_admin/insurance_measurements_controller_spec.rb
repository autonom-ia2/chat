require 'rails_helper'

# TERMO 4 — A CONSULTA NÃO DEPENDE DE ENGENHEIRO. A operação abre a página, escolhe o período e lê
# os dois números por corretora. Sem token, sem `curl`, sem console.
RSpec.describe 'Super Admin Insurance Measurement', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  # As células da tabela que são número, na ordem das colunas: cotações, seguradoras acionadas, com
  # preço, cotações com proposta, propostas emitidas, sem medida, sem confirmação, possível duplicata.
  def celulas_numericas
    response.body.scan(%r{<td[^>]*>(\d+)</td>}).flatten
  end

  # O gate do endpoint da conta, para o exemplo que compara as duas superfícies.
  def enable_feature!
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return('true')
    Autonomia::Insurance::Config.enable_for!(account)
  end

  def cotacao!(handle:, criada_em: Time.current)
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Mia', agent_type: 'insurance_quote',
                                              status: :active, enabled: true, instruction: 'Cote.')
    conversa = create(:conversation, account: account, inbox: create(:inbox, account: account))
    Autonomia::Agents::ToolRun.create!(account: account, agent: agente, conversation_id: conversa.id,
                                       slug: Autonomia::Agents::Tools::Native::InsuranceQuote.slug,
                                       status: 'done', execution_key: SecureRandom.uuid,
                                       handle: handle, created_at: criada_em)
  end

  it 'exige super admin' do
    get '/super_admin/insurance_measurement'

    expect(response).to have_http_status(:redirect)
  end

  context 'when o super admin esta autenticado' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'mostra a corretora com os dois numeros' do
      # Arrange
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         'entregues' => %w[1 3 4 5 7 8 11 12 19 20 26] })

      # Act
      get '/super_admin/insurance_measurement'

      # Assert
      expect(response).to have_http_status(:success)
      expect(response.body).to include(account.name)
      expect(response.body).to include('Seguradoras acionadas')
      expect(response.body).to include('>17<')
    end

    # TERMO 3 na tela: COTAÇÕES que viraram proposta e a soma dos códigos são DUAS colunas. Uma
    # cotação com duas propostas é uma cotação — a coluna da fatura não pode dobrar por causa da soma.
    it 'mostra cotações com proposta e propostas emitidas em colunas separadas' do
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => %w[8 3] })

      get '/super_admin/insurance_measurement'

      expect(response.body).to include('Cotações com proposta', 'Propostas emitidas')
      expect(celulas_numericas).to eq(%w[1 17 0 1 2 0 0 0])
    end

    it 'aceita a janela pedida' do
      cotacao!(handle: { 'quote_id' => 'velha', 'seguradoras_acionadas' => dezessete }, criada_em: 40.days.ago)

      get '/super_admin/insurance_measurement', params: { from: 60.days.ago.to_date.to_s, to: Time.zone.today.to_s }

      expect(response.body).to include('>17<')
    end

    # Data ilegível não vira janela padrão em silêncio: a página avisa e não mostra número nenhum.
    it 'avisa em vez de escolher a janela sozinho' do
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })

      get '/super_admin/insurance_measurement', params: { from: 'ontem' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Período inválido')
      expect(response.body).not_to include('>17<')
    end

    # A JANELA TEM DUAS BORDAS TAMBÉM NESTA TELA — a que fatura. O serviço e a API já provavam a borda
    # de cima; aqui, `fim: nil` no lugar de `fim: params[:to]` passava por seis exemplos verdes
    # (rodada 4, MX8), porque "aceita a janela pedida" usava `to=hoje`, indistinguível do padrão. A
    # operação pede setembro; a cotação de 01/10 é da fatura de outubro, e número inflado em fatura
    # ninguém questiona.
    it 'nao conta cotação feita depois do fim da janela' do
      # Arrange — uma em setembro, uma no primeiro dia de outubro.
      cotacao!(handle: { 'quote_id' => 'setembro', 'seguradoras_acionadas' => dezessete },
               criada_em: Time.zone.parse('2026-09-15 10:00'))
      cotacao!(handle: { 'quote_id' => 'outubro', 'seguradoras_acionadas' => dezessete },
               criada_em: Time.zone.parse('2026-10-01 09:00'))

      # Act
      get '/super_admin/insurance_measurement', params: { from: '2026-09-01', to: '2026-09-30' }

      # Assert — a de outubro ficou de fora: uma cotação, dezessete seguradoras.
      expect(celulas_numericas).to eq(%w[1 17 0 0 0 0 0 0])
    end

    # CADA CORRETORA NO FUSO DELA, E O MESMO NÚMERO QUE A API DELA RESPONDE. A cotação das 23h de 30/09
    # em São Paulo é 02h de 01/10 em UTC (o fuso da instalação): lida no nosso fuso, ela cai na fatura
    # de outubro nesta tela e fica em setembro na tela da corretora — dois números para o mesmo mês,
    # numa conta de dinheiro (rodada 4, P2). O exemplo lê as DUAS superfícies e exige que batam.
    it 'le cada corretora no fuso dela e bate com a API da conta' do
      # Arrange
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete },
               criada_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-30 23:00'))
      janela = { from: '2026-09-01', to: '2026-09-30' }

      # Act — a página que cobra e, no mesmo exemplo, a porta da corretora.
      get '/super_admin/insurance_measurement', params: janela
      pagina = celulas_numericas.first(2)
      expect(response.body).to include('America/Sao_Paulo')

      enable_feature!
      get "/api/v1/accounts/#{account.id}/autonomia/insurance/measurement", params: janela,
                                                                            headers: admin.create_new_auth_token, as: :json
      payload = response.parsed_body['payload']

      # Assert — setembro tem a cotação nas duas: uma cotação, dezessete seguradoras.
      expect(pagina).to eq(%w[1 17])
      expect(payload.values_at('quotes', 'insurers_called')).to eq([1, 17])
    end

    it 'nao inventa linha para corretora sem cotação' do
      get '/super_admin/insurance_measurement'

      expect(response.body).to include('Nenhuma cotação no período')
    end
  end
end
