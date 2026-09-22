require 'rails_helper'

# A ENTRADA RECUSADA NO `quote/start` (#470), pelo motor, com a ferramenta de cotação de verdade.
#
# Em 19/09/2026 a consulta de CPF não achou a pessoa, o `quote/start` recusou a entrada (faltavam
# nascimento e sexo) e o job leu isso como falha passageira: 15 tentativas em 7 minutos, prazo
# esgotado e "um atendente vai continuar". O adapter confere a entrada antes do `calcularV2`, então
# nada foi cotado; o que falta é pergunta ao cliente, feita uma vez — pela Lia, no evento `falta_dado` (PR C).
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  let(:dados) do
    { segurado: { nome: 'Fulano', cpfCnpj: '04297912678' },
      configuracoes: { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' } }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true',
                      INSURANCE_CONNECTOR_MODE: 'mock') { example.run }
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    register_async_tool(cotacao)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(mock)
    issues = ['insured.birthDate: Required', 'insured.gender: Required']
    allow(mock).to receive(:quote_start)
      .and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'auto quote input invalid', { 'issues' => issues }))
  end

  def execucao
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'bike', 'dados' => dados },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
    run
  end

  it 'vira o evento do que falta, uma vez, sem nova chamada ao portal e sem texto nosso' do
    run = execucao

    described_class.new.perform(run.id, 0)
    expect(run.reload.handle).to include('recusa' => 'faltam_dados',
                                         'faltando' => %w[insured.birthDate insured.gender])
    expect(run.handle).not_to have_key(Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA)

    described_class.new.perform(run.id, 1)
    described_class.new.perform(run.id, 2)

    expect(run.reload.status).to eq('done')
    expect(mock).to have_received(:quote_start).once
    expect(conversation.messages.reload.where(sender_type: 'AgentBot')).to be_empty
    expect(eventos_disparados(run)).to eq(['falta_dado'])
    fatos = Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'falta_dado').fatos
    expect(fatos).to include('data de nascimento do titular', 'sexo do titular')
  end

  # AS PERGUNTAS QUE O ADAPTER DECLARA (adapters#76): cidade de CEP único sem rua, CEP que não existe, documento
  # recusado pelo portal. Não são `Required`, e até aqui caíam na nova tentativa: até 60 passadas, e o 400 de documento
  # repetia a chamada paga. Agora viram o mesmo evento, com o motivo do adapter para o modelo.
  def recusa_do_start(details)
    allow(mock).to receive(:quote_start)
      .and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'entrada recusada', details))
  end

  it 'a pergunta declarada pelo adapter vira o evento do que falta, uma vez, com o motivo para o modelo' do
    recusa_do_start('issues' => ['segurado.logradouro: cidade de CEP unico'],
                    'perguntas' => [{ 'campo' => 'segurado.logradouro', 'motivo' => 'a cidade tem CEP unico; pergunte a rua do imovel' }])
    run = execucao

    3.times { |passada| described_class.new.perform(run.id, passada) }

    expect(run.reload.status).to eq('done')
    expect(run.handle).to include('recusa' => 'faltam_dados', 'faltando' => ['segurado.logradouro'])
    expect(mock).to have_received(:quote_start).once
    expect(eventos_disparados(run)).to eq(['falta_dado'])
    expect(Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'falta_dado').fatos).to include('pergunte a rua do imovel')
  end

  it 'o documento recusado pelo portal nao repete a chamada paga' do
    recusa_do_start('issues' => ['insured.document: o portal recusou o CPF'],
                    'perguntas' => [{ 'campo' => 'insured.document', 'motivo' => 'o portal recusou o CPF; confirme o documento' }])
    run = execucao

    3.times { |passada| described_class.new.perform(run.id, passada) }

    expect(mock).to have_received(:quote_start).once
    expect(run.reload.handle['faltando']).to eq(['insured.document'])
  end

  it 'erro de formato sem pergunta declarada nao vira pergunta ao cliente' do
    recusa_do_start('issues' => ['vehicle.plate: placa com 7 caracteres'])
    run = execucao

    described_class.new.perform(run.id, 0)

    expect(run.reload.handle).not_to have_key('recusa')
    expect(eventos_disparados(run)).to be_empty
  end
end
