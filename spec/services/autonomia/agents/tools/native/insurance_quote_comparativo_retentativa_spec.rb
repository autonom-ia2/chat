require 'rails_helper'

# O COMPARATIVO TENTA DE NOVO QUANDO O PORTAL FALHA (chat#585). Em 21 e 22/09/2026 duas cotações com 8 e 9 preços
# fecharam por prazo e o cliente recebeu "os valores estão comigo" em vez do PDF: o gerador do portal
# (`/calculo/print`) falhou na única tentativa. Medido no dia seguinte: pedido de novo, minutos depois, o mesmo PDF
# saiu. Agora a geração tenta de novo, com espera, antes de desistir — só quando a falha é de tempo ou de portal
# fora; recusa de validação não melhora esperando.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: {},
                                     scope: { conversation_id: conversation.id })
  end
  let(:connector) { instance_double(Autonomia::Insurance::Connector::Mock) }
  let(:url) { { 'url' => 'https://arquivos.exemplo.test/comparativo-9.pdf' } }
  let(:handle_com_preco) do
    texto = '*Ezze*: R$ 2.050,40 no total'
    token = Autonomia::Agents::Tools::EntregaPublicada.token_de(run, texto)
    run.registrar_entrega_aceita!(token)
    { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'],
      described_class::PRECO_LEGADO_KEY => false, described_class::PRECOS_KEY => [token] }
  end
  let(:esperas) { [] }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def ferramenta
    tool = described_class.new(agent: agent, params: { 'cpf' => '042.979.126-78', 'vehicle' => { 'plate' => 'hik-9383' } }, run: run)
    registro = esperas
    allow(tool).to receive(:esperar_o_portal) { |segundos| registro << segundos }
    tool
  end

  def erro(tipo)
    Autonomia::Insurance::Connector::Error.new(tipo, 'portal')
  end

  it 'o portal falhou por tempo e depois gerou: sai o PDF, depois de esperar' do
    chamadas = 0
    allow(connector).to receive(:quote_proposal) do
      chamadas += 1
      chamadas < 3 ? raise(erro(:timeout)) : url
    end

    entregas = ferramenta.closing_deliveries(handle_com_preco)

    expect(entregas.size).to eq(1)
    expect(chamadas).to eq(3)
    expect(esperas).to eq(described_class::ESPERAS_DO_COMPARATIVO)
  end

  it 'portal fora em todas as tentativas: desiste, sem PDF' do
    allow(connector).to receive(:quote_proposal).and_raise(erro(:unavailable))

    expect(ferramenta.closing_deliveries(handle_com_preco)).to be_empty
    expect(connector).to have_received(:quote_proposal).exactly(described_class::ESPERAS_DO_COMPARATIVO.size + 1).times
  end

  it 'recusa que não é de tempo nem de portal fora não é tentada de novo' do
    allow(connector).to receive(:quote_proposal).and_raise(erro(:validation))

    expect(ferramenta.closing_deliveries(handle_com_preco)).to be_empty
    expect(connector).to have_received(:quote_proposal).once
    expect(esperas).to be_empty
  end

  it 'na primeira, sem espera nenhuma' do
    allow(connector).to receive(:quote_proposal).and_return(url)

    ferramenta.closing_deliveries(handle_com_preco)

    expect(esperas).to be_empty
  end
end
