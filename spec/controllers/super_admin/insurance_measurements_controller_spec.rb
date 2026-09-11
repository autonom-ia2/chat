require 'rails_helper'

# TERMO 4 — A CONSULTA NÃO DEPENDE DE ENGENHEIRO. A operação abre a página, escolhe o período e lê
# os dois números por corretora. Sem token, sem `curl`, sem console.
RSpec.describe 'Super Admin Insurance Measurement', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:outra) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  # As células da tabela que são número, na ordem das colunas: cotações, seguradoras acionadas, com
  # preço, cotações com proposta, propostas emitidas, sem medida, sem confirmação, possível duplicata.
  def celulas_numericas
    response.body.scan(%r{<td[^>]*>(\d+)</td>}).flatten
  end

  # As oito células que a medida da PRÓPRIA conta daria, na ordem das colunas — para exigir que a
  # linha da página seja essa, e não uma parecida.
  def celulas_da_medida(conta, janela)
    medida = Autonomia::Insurance::Medida.new(conta: conta, inicio: janela[:from], fim: janela[:to]).call
    medida.values_at(*Autonomia::Insurance::Medida::NUMEROS).map(&:to_s)
  end

  # O gate do endpoint da conta, para o exemplo que compara as duas superfícies.
  def enable_feature!
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return('true')
    Autonomia::Insurance::Config.enable_for!(account)
  end

  def cotacao!(handle:, criada_em: Time.current, conta: account)
    agente = Autonomia::Agents::Agent.create!(account: conta, name: "Mia #{conta.id}", agent_type: 'insurance_quote',
                                              status: :active, enabled: true, instruction: 'Cote.')
    conversa = create(:conversation, account: conta, inbox: create(:inbox, account: conta))
    Autonomia::Agents::ToolRun.create!(account: conta, agent: agente, conversation_id: conversa.id,
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

    # POR CORRETORA, NA TELA QUE COBRA. Os exemplos acima têm UMA conta com execução: um wiring que
    # mostrasse só a primeira corretora (`por_conta.first(1)`) passava por todos eles, e o termo 1
    # ficava provado só no serviço (rodada 5). Aqui são duas, dezessete e três, cada uma na sua linha
    # e na ordem da que mais acionou para a que menos.
    it 'mostra as duas corretoras, cada uma na sua linha' do
      # Arrange
      cotacao!(handle: { 'quote_id' => 'a', 'seguradoras_acionadas' => dezessete })
      cotacao!(handle: { 'quote_id' => 'b', 'seguradoras_acionadas' => dezessete.first(3) }, conta: outra)

      # Act
      get '/super_admin/insurance_measurement'

      # Assert — as duas linhas, dezessete antes de três.
      expect(response.body).to include("##{account.id}<", "##{outra.id}<")
      expect(response.body.index("##{account.id}<")).to be < response.body.index("##{outra.id}<")
      expect(celulas_numericas).to eq(%w[1 17 0 0 0 0 0 0 1 3 0 0 0 0 0 0])
    end

    # A FOLGA DA ENUMERAÇÃO TEM MAGNITUDE. A lista enumera as corretoras no fuso da instalação com uma
    # folga (`FOLGA_DE_FUSO`) antes de ler cada uma no fuso dela; folga zero já reprovava, mas 3 h
    # passava por 53 exemplos — todos em São Paulo. Com folga menor do que a distância entre os fusos
    # extremos, a corretora em UTC+14 com cotação na primeira hora do mês (ainda 31/08 em UTC) e a em
    # UTC-12 com cotação na última (já 01/10 em UTC) somem da FATURA em silêncio, enquanto a API de
    # cada uma responde 1/17 (rodada 5). A linha da página tem de ser a medida da própria conta.
    it 'le a corretora em qualquer fuso, e a linha e a medida da propria conta' do
      # Arrange — Kiritimati (UTC+14) às 00:30 de 01/09; Etc/GMT+12 (UTC-12) às 23:30 de 30/09.
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      outra.update!(reporting_timezone: 'Etc/GMT+12')
      cotacao!(handle: { 'quote_id' => 'leste', 'seguradoras_acionadas' => dezessete },
               criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-01 00:30'))
      cotacao!(handle: { 'quote_id' => 'oeste', 'seguradoras_acionadas' => dezessete }, conta: outra,
               criada_em: ActiveSupport::TimeZone['Etc/GMT+12'].parse('2026-09-30 23:30'))
      janela = { from: '2026-09-01', to: '2026-09-30' }

      # Act
      get '/super_admin/insurance_measurement', params: janela

      # Assert — as duas na página, com o fuso de cada uma, e as células são as da medida da conta.
      expect(response.body).to include('Pacific/Kiritimati', 'Etc/GMT+12')
      expect(celulas_da_medida(account, janela).first(2)).to eq(%w[1 17])
      expect(celulas_numericas).to eq(celulas_da_medida(account, janela) + celulas_da_medida(outra, janela))
    end

    # O DIA DE UMA CORRETORA AINDA NÃO COMEÇOU, E A PÁGINA NÃO CAI. `from=hoje` sem `to` à 01h UTC:
    # para a instalação (UTC) a data é válida; para São Paulo (UTC-3) ainda são 22h de ontem. Até a
    # rodada 4, a `Medida.new(conta:)` de São Paulo levantava `PeriodoInvalido` e a página inteira
    # respondia "a data inicial é posterior à final" — culpando uma final que ninguém mandou — sem
    # linha para NENHUMA corretora (rodada 5). A resposta certa para ela é nenhuma execução; a outra
    # corretora, cujo dia começou, continua na fatura.
    it 'nao derruba a pagina quando o dia de uma corretora ainda nao comecou' do
      # Arrange — São Paulo com cotação às 23h UTC de ontem; a outra (UTC) com uma às 00h30 de hoje.
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      travel_to Time.utc(2026, 9, 11, 1, 0) do
        cotacao!(handle: { 'quote_id' => 'sp', 'seguradoras_acionadas' => dezessete }, criada_em: Time.utc(2026, 9, 10, 23, 0))
        cotacao!(handle: { 'quote_id' => 'utc', 'seguradoras_acionadas' => dezessete }, conta: outra,
                 criada_em: Time.utc(2026, 9, 11, 0, 30))

        # Act
        get '/super_admin/insurance_measurement', params: { from: '2026-09-11' }

        # Assert — sem aviso de período; só a corretora cujo dia começou.
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Período inválido')
        expect(response.body).to include("##{outra.id}<")
        expect(response.body).not_to include("##{account.id}<")
        expect(celulas_numericas).to eq(%w[1 17 0 0 0 0 0 0])
      end
    end

    # O RELÓGIO DA INSTALAÇÃO NÃO DECIDE O DIA DE NINGUÉM. Meio-dia UTC de 11/09; em Kiritimati
    # (UTC+14) já são 02h de 12/09, e a corretora de lá cotou à 01h. `from=2026-09-12` sem `to`: a
    # API da conta dela responde 1/17, e a página que FATURA tem de responder o mesmo. Até a rodada 5
    # a página recusava antes de olhar qualquer corretora — "a data inicial está no futuro", pelo
    # nosso relógio — e a linha dela sumia da fatura (rodada 6, P2 do Codex). O exemplo lê as DUAS
    # superfícies e exige que batam.
    it 'le a corretora cujo dia ja comecou no fuso dela, e bate com a API da conta' do
      # Arrange
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      travel_to Time.utc(2026, 9, 11, 12, 0) do
        cotacao!(handle: { 'quote_id' => 'kiritimati', 'seguradoras_acionadas' => dezessete },
                 criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-12 01:00'))
        janela = { from: '2026-09-12' }

        # Act — a página que cobra e, no mesmo instante, a porta da corretora.
        get '/super_admin/insurance_measurement', params: janela
        expect(response.body).not_to include('Período inválido')
        expect(response.body).to include('Pacific/Kiritimati')
        pagina = celulas_numericas.first(2)

        enable_feature!
        get "/api/v1/accounts/#{account.id}/autonomia/insurance/measurement", params: janela,
                                                                              headers: admin.create_new_auth_token, as: :json
        payload = response.parsed_body['payload']

        # Assert — o dia 12 dela já começou nas duas: uma cotação, dezessete seguradoras.
        expect(pagina).to eq(%w[1 17])
        expect(payload.values_at('quotes', 'insurers_called')).to eq([1, 17])
      end
    end

    # Quando o dia não começou para NENHUMA corretora, a página diz "nenhuma cotação no período" —
    # que é a verdade — e não "período inválido" pelo nosso relógio.
    it 'mostra nenhuma cotação, sem aviso de periodo, quando o dia nao comecou para nenhuma corretora' do
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      travel_to Time.utc(2026, 9, 11, 12, 0) do
        cotacao!(handle: { 'quote_id' => 'kiritimati', 'seguradoras_acionadas' => dezessete },
                 criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-12 01:00'))

        get '/super_admin/insurance_measurement', params: { from: '2026-09-13' }

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Período inválido')
        expect(response.body).to include('Nenhuma cotação no período')
        expect(response.body).not_to include('>17<')
      end
    end

    it 'nao inventa linha para corretora sem cotação' do
      get '/super_admin/insurance_measurement'

      expect(response.body).to include('Nenhuma cotação no período')
    end
  end
end
