require 'rails_helper'

# TESTADOR 2 (pré-PR #1430 assíncrona): lacunas sem cobertura. NÃO COMMITAR.
# Sem `ligar_consulta_em_segundo_plano`: a flag é ligada pelo bit real do features.yml.
RSpec.describe Autonomia::Agents::Tools::ConsultaNoTurno, type: :job do
  let(:flag) { 'agente_ferramenta_em_segundo_plano' }
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:segredo) { 'segredo-da-conta-XYZ987' }
  let(:tool) { ferramenta(account, agent) }
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job) { Autonomia::Agents::Tools::HttpAssincronaJob }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { agent_inbox }

  def ferramenta(conta, dono)
    Autonomia::Agents::Tool.create!(
      account: conta, agent: dono, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      headers_config: [{ key: 'x-api-key', value: segredo, secret: true }],
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número', required: true }]
    )
  end

  def turno(conversa: conversation, vinculo: agent_inbox)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: vinculo, origin_message_id: 77)
  end

  def chamada(numero = '42')
    { 'name' => 'consultar_pedido', 'arguments' => { numero: numero }.to_json, 'call_id' => "c#{numero}" }
  end

  def ligar_de_verdade(conta = account)
    conta.enable_features!(flag)
    conta.reload
  end

  def jobs_http
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == job }
  end

  it 'N1a/S02: o bit real da flag (sem stub) liga o caminho novo: ToolRun running e job na agent_tools' do
    ligar_de_verdade
    expect(account.feature_enabled?(flag)).to be(true)
    relogio_do_turno
    allow(SafeFetch).to receive(:fetch)

    saida = bound.execute(chamada, delivery: turno)

    expect(saida).to eq(described_class::EM_ANDAMENTO)
    expect(SafeFetch).not_to have_received(:fetch)
    expect(runs.count).to eq(1)
    expect(runs.sole).to have_attributes(status: 'running', autonomia_agent_tool_id: tool.id, account_id: account.id)
    expect(jobs_http.size).to eq(1)
    expect(jobs_http.first[:queue]).to eq('agent_tools')
  end

  it 'N1b/S01: flag desligada pelo bit real: sincrono, 0 ToolRun, 0 job, SafeFetch 1x' do
    account.disable_features!(flag)
    expect(account.reload.feature_enabled?(flag)).to be(false)
    sistema_responde('{"status":"pago"}')

    saida = bound.execute(chamada, delivery: turno)

    expect(saida).to include('pago')
    expect(SafeFetch).to have_received(:fetch).once
    expect(runs.count).to eq(0)
    expect(jobs_http.size).to eq(0)
  end

  it 'N2/S03: ligar o bit 32 do ext_2 nao muda nenhuma outra flag' do
    antes = account.reload.all_features
    ligar_de_verdade
    depois = account.all_features
    mudou = depois.keys.reject { |k| depois[k] == antes[k] }
    expect(mudou).to eq([flag])
    expect(account.feature_flags_ext_2 & (1 << 31)).to eq(1 << 31)
  end

  it 'N3/S14: a conta B nao cede a vez por causa da ocupacao da conta A (contagem por conta)' do
    outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    outra_inbox = create(:inbox, account: outra)
    outra_conversa = create(:conversation, account: outra, inbox: outra_inbox, assignee: nil)
    outro_agente = Autonomia::Agents::Agent.create!(account: outra, name: 'Bot B', agent_type: 'custom', status: :active, enabled: true,
                                                    instruction: 'Atenda.', config: { 'with_knowledge' => false })
    outro_vinculo = Autonomia::Agents::AgentInbox.create!(agent: outro_agente, inbox: outra_inbox, account: outra,
                                                          agent_bot: create(:agent_bot, account: outra))
    tool_b = ferramenta(outra, outro_agente)
    ligar_de_verdade
    ligar_de_verdade(outra)
    # A conta A: 9 em voo e 1 esperando.
    9.times do |i|
      runs.create!(account: account, agent: agent, slug: 'consultar_pedido', faixa: "ocupada_#{i}", status: 'running',
                   conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {},
                   handle: { runs::FILA_MS => 1 }, autonomia_agent_tool_id: tool.id, expires_at: 5.minutes.from_now)
    end
    runs.create!(account: account, agent: agent, slug: 'consultar_pedido', faixa: 'esperando_a', status: 'running',
                 conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {}, handle: {},
                 autonomia_agent_tool_id: tool.id, expires_at: 5.minutes.from_now)
    relogio_do_turno
    Autonomia::Agents::Tools::Bound.new(agent: outro_agente, record: tool_b)
                                   .execute(chamada, delivery: turno(conversa: outra_conversa, vinculo: outro_vinculo))
    run_b = runs.find_by!(account_id: outra.id)
    sistema_responde('{"dono":"B"}')

    job.new.perform(run_b.id)

    expect(SafeFetch).to have_received(:fetch).once
    expect(run_b.reload.status).to eq('done')
    expect(runs.where(account_id: account.id).pluck(:status).uniq).to eq(['running'])
    expect(runs.where(account_id: account.id).where("handle->>'#{runs::RESULTADO_DA_CONSULTA}' IS NOT NULL").count).to eq(0)
  end

  it 'N4/S18: erro de infra com segredo na mensagem: o log leva so a classe, e a recusa e nomeada' do
    ligar_de_verdade
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))
    relogio_do_turno
    allow(job).to receive(:perform_later).and_raise(Redis::CannotConnectError, "redis://user:#{segredo}@host falhou")

    saida = bound.execute(chamada, delivery: turno)

    expect(JSON.parse(saida)).to eq('error' => 'tool_execution_error')
    expect(runs.sole).to have_attributes(status: 'failed', failure_code: 'consulta_nao_disparou')
    expect(saida.to_s).not_to include(segredo)
    expect(log.string).to include('Redis::CannotConnectError')
    expect(log.string).not_to include(segredo)
    expect(runs.where(status: 'running').count).to eq(0)
    runs.find_each { |r| expect(r.handle.to_json + r.arguments.to_json + r.failure_code.to_s).not_to include(segredo) }
  end

  it 'N5/S21: TurnoEmCurso.marcar? liga com a flag da consulta mesmo com agente_so_informa desligada' do
    account.disable_features!('agente_so_informa', flag)
    expect(Autonomia::Agents::Operate::TurnoEmCurso.marcar?(account.reload)).to be(false)
    ligar_de_verdade
    expect(Autonomia::Agents::Operate::TurnoEmCurso.marcar?(account)).to be(true)
  end

  it 'N6/S24: a conexao nao e solta dentro de uma transacao aberta pelo codigo' do
    resultado = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      runs.count
      resultado = Autonomia::Agents::Tools::ConexaoDoBanco.soltar
    end
    expect(resultado).to be(false)
  end

  it 'N7/S25: o job da consulta e enfileirado depois do commit da abertura, fora da transacao' do
    ligar_de_verdade
    relogio_do_turno
    base = ActiveRecord::Base.connection.open_transactions
    profundidades = []
    allow(job).to receive(:perform_later).and_wrap_original do |original, *args|
      profundidades << ActiveRecord::Base.connection.open_transactions
      original.call(*args)
    end

    bound.execute(chamada, delivery: turno)

    expect(profundidades).to eq([base])
  end

  it 'N8/S26: a nativa da Lia (cotar_seguro) com a flag ligada nao abre consulta HTTP no pre-disparo' do
    ligar_de_verdade
    nativa = Autonomia::Agents::Tools::Registry.find('cotar_seguro')
    expect(nativa).to be_present
    allow(described_class).to receive(:new).and_call_original
    lia = Autonomia::Agents::Tools::Bound.new(agent: agent, native: nativa)

    retorno = lia.disparar({ 'name' => 'cotar_seguro', 'arguments' => '{}', 'call_id' => 'x' }, turno: turno)

    expect(retorno).to be_nil
    expect(described_class).not_to have_received(:new)
    expect(runs.count).to eq(0)
    expect(jobs_http.size).to eq(0)
  end

  it 'N9/S27: o varredor leva a consulta HTTP com slug de nativa para fechar_consulta, nunca ao Encerramento da Lia' do
    ligar_de_verdade
    relogio_do_turno
    bound.execute(chamada, delivery: turno)
    run = runs.sole
    runs.where(id: run.id).update_all(slug: 'cotar_seguro', expires_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    allow(Autonomia::Agents::Tools::Encerramento).to receive(:new).and_call_original
    allow(Autonomia::Agents::Tools::Registry).to receive(:find).and_call_original

    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    expect(Autonomia::Agents::Tools::Encerramento).not_to have_received(:new)
    expect(Autonomia::Agents::Tools::Registry).not_to have_received(:find).with('cotar_seguro')
    run.reload
    expect(run.status).to eq('running')
    expect(run.expires_at).to be > Time.current
    expect(run.handle).not_to have_key(runs::REENFILEIRADA)
  end
end
