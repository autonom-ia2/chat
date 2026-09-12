require 'rails_helper'

# O COMPARATIVO SAI COMO ARQUIVO, com nome que diz o que ele é (entrega 11, termos 1 e 5).
#
# A ferramenta não baixa nada: ela entrega a URL do portal, o NOME do arquivo, a legenda e a
# reserva (o texto com o link, o mesmo de antes). O nome leva a placa — o dado que o cliente já
# vê e pelo qual ele procura o arquivo depois —, e nenhum outro dado dele. Provado por mutação em
# 11/09/2026: trocar o nome por um genérico ("comparativo.pdf") reprova o primeiro exemplo.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:params) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'hik-9383' } } }
  let(:entrega_de_arquivo) { Autonomia::Agents::Tools::EntregaDeArquivo }
  # A FERRAMENTA COMO O MOTOR A MONTA (entrega 8a): com a LINHA da execução. O encerramento só pede
  # o comparativo a quem tem preço ACEITO pelo publicador, e essa pergunta é feita à linha —
  # `entregues` no handle é o que se emitiu, não o que o publicador assumiu.
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: {},
                                     scope: { conversation_id: conversation.id })
  end
  let(:tool) { ferramenta(params) }
  # O handle de quem já entregou um preço AO CLIENTE: a identidade emitida, e o aceite na linha. A
  # COBERTURA entra explícita (`preco_legado` falso): sem ela o handle cairia na PROVA LEGADA
  # (`entregues` não vazio) e estes exemplos passariam por lá em vez do aceite que exercitam.
  let(:handle_com_preco) do
    texto = '*Ezze* — R$ 2.050,40 no total'
    token = Autonomia::Agents::Tools::EntregaPublicada.token_de(run, texto)
    run.registrar_entrega_aceita!(token)
    { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'],
      described_class::PRECO_LEGADO_KEY => false, described_class::PRECOS_KEY => [token] }
  end

  def ferramenta(params)
    described_class.new(agent: agent, params: params, run: run)
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    connector = instance_double(Autonomia::Insurance::Connector::Mock,
                                quote_proposal: { 'url' => 'https://arquivos.exemplo.test/comparativo-9.pdf' })
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def comparativo(tool)
    entrega_de_arquivo.de(tool.closing_deliveries(handle_com_preco).first)
  end

  it 'entrega o comparativo como arquivo, nomeado pela placa que o cliente informou' do
    entrega = comparativo(tool)

    expect(entrega).to be_a(entrega_de_arquivo)
    expect(entrega.nome).to eq('Comparativo de seguro — placa HIK9383.pdf')
    expect(entrega.url).to eq('https://arquivos.exemplo.test/comparativo-9.pdf')
  end

  it 'mantem a legenda e a reserva com o link, que e o que sai se o arquivo falhar' do
    entrega = comparativo(tool)

    expect(entrega.legenda).to eq('Comparativo com todas as opções.')
    expect(entrega.reserva).to eq("Comparativo com todas as opções:\nhttps://arquivos.exemplo.test/comparativo-9.pdf")
  end

  it 'nao poe no nome nada alem do que o cliente ja ve' do
    expect(comparativo(tool).nome).not_to include('042', '979', '31110')
  end

  it 'nomeia pelo ramo quando nao ha placa (chassi, FIPE ou outro ramo)' do
    sem_placa = ferramenta(params.merge('vehicle' => { 'chassis' => '9BWZZZ377VT004251' }))
    bike = ferramenta('produto' => 'bike', 'dados' => '{}')

    expect(comparativo(sem_placa).nome).to eq('Comparativo de seguro — auto.pdf')
    expect(comparativo(bike).nome).to eq('Comparativo de seguro — bike.pdf')
  end

  # A URL VEM DE FORA e a forma da entrega de arquivo pode recusá-la (o adapter só garante que é uma
  # URL; https não é promessa). A falha da forma não pode apagar a entrega: sai o texto com o link,
  # o de antes, e o motivo curto no log. Sem esta guarda o Hash inválido era descartado pelo
  # `Progress` com a sentinela do comparativo já gravada — nem arquivo, nem link (rodada 2, P2).
  describe 'quando a URL do portal nao tem a forma segura' do
    let(:url_http) { 'http://arquivos.exemplo.test/comparativo-9.pdf' }

    before do
      connector = instance_double(Autonomia::Insurance::Connector::Mock, quote_proposal: { 'url' => url_http })
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(Rails.logger).to receive(:warn).and_call_original
    end

    it 'entrega o texto com o link, como antes, e registra o defeito da forma' do
      entrega = tool.closing_deliveries(handle_com_preco).first

      expect(entrega).to eq("Comparativo com todas as opções:\n#{url_http}")
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/comparativo sem forma de arquivo account=#{account.id} defeito=url; vai como link/))
    end
  end

  it 'nomeia pelo ramo com espaco, nunca pelo sublinhado do codigo' do
    fianca = ferramenta('produto' => 'fianca_locaticia', 'dados' => '{}')

    expect(comparativo(fianca).nome).to eq('Comparativo de seguro — fianca locaticia.pdf')
  end
end
