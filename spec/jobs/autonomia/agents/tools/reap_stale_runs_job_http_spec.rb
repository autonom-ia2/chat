require 'rails_helper'

# #1430, desenho D: um deploy no meio da consulta HTTP mata o worker por SIGKILL e o job não volta. O varredor
# reenfileira UMA vez, com a mesma Idempotency-Key (o sistema de fora reconhece o pedido repetido); na segunda vez,
# fecha como falha e o agente avisa. A execução reivindicada há pouco não é tocada.
RSpec.describe Autonomia::Agents::Tools::ReapStaleRunsJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
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
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job_http) { Autonomia::Agents::Tools::HttpAssincronaJob }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    ligar_consulta_em_segundo_plano
    allow(Autonomia::Agents::Tools::Registry).to receive(:find).and_call_original
  end

  # O turno desistiu, e a linha venceu sem o job ter voltado.
  def consulta_vencida
    relogio_do_turno
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
    Autonomia::Agents::Tools::ConsultaNoTurno.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => 42 }).resultado
    vencer(runs.sole)
  end

  def vencer(run)
    runs.where(id: run.id).update_all(expires_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    run.reload
  end

  it 'na primeira vez reenfileira o job HTTP uma vez, renovando o prazo pelo tempo gravado, sem fechar nem falar' do
    run = consulta_vencida
    run.merge_handle!({ runs::CHAMADA_FEITA => true }) # o worker morreu no meio da chamada

    freeze_time do
      described_class.new.perform

      expect(run.reload).to have_attributes(status: 'running', expires_at: 60.seconds.from_now + job_http::FOLGA)
    end
    expect(run.handle).to include(runs::REENFILEIRADA => true)
    expect(run.handle).not_to have_key(runs::CHAMADA_FEITA)
    expect(job_http).to have_been_enqueued.with(run.id).twice # o da abertura e o do varredor
    expect(eventos_disparados(run)).to be_empty
    expect(Autonomia::Agents::Tools::Registry).not_to have_received(:find)
  end

  it 'na segunda vez fecha failed com consulta_falhou' do
    run = consulta_vencida
    described_class.new.perform
    vencer(run)

    described_class.new.perform

    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
    expect(eventos_disparados(run)).to eq(['consulta_falhou'])
  end

  it 'a passada reenfileirada usa a mesma Idempotency-Key da primeira' do
    run = consulta_vencida
    chaves = []
    allow(SafeFetch).to receive(:fetch) do |_url, **opcoes|
      chaves << opcoes[:headers]['Idempotency-Key']
      # A primeira passada morre no meio da chamada, como no deploy: nada do job roda depois disto.
      raise Sidekiq::Shutdown if chaves.one?

      raise SafeFetch::FetchError, 'de novo'
    end
    expect { job_http.new.perform(run.id) }.to raise_error(Sidekiq::Shutdown)
    vencer(run)

    described_class.new.perform
    job_http.new.perform(run.id)

    expect(chaves.size).to eq(2)
    expect(chaves.uniq).to eq([run.reload.handle.fetch(runs::CHAVE_DA_CONSULTA)])
    expect(run.status).to eq('failed')
  end

  it 'a execucao reivindicada ha pouco nao e tocada' do
    run = consulta_vencida
    allow(SafeFetch).to receive(:fetch) do
      # Dentro da chamada: o job acabou de começar e renovou o prazo; o varredor passa agora.
      described_class.new.perform
      raise SafeFetch::FetchError, 'x'
    end

    job_http.new.perform(run.id)

    expect(run.reload.handle).not_to have_key(runs::REENFILEIRADA)
    expect(run.status).to eq('failed')
  end
end
