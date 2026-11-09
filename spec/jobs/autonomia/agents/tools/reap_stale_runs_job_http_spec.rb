require 'rails_helper'

# #1430, desenho D: um deploy no meio da consulta HTTP mata o worker por SIGKILL e o job se perde. O varredor decide
# pelo que a linha mostra: a chamada feita sem resposta fecha como incerta (nunca chama de novo); o job que nunca
# começou volta à fila sem gastar a segunda chance; o que começou e morreu antes de chamar volta uma vez e, na segunda,
# fecha como falha. Cada escrita confere o prazo vencido: a execução reivindicada há pouco não é tocada.
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

  # O job começou (anotou a espera na fila) e morreu antes de chamar.
  def comecou(run)
    run.merge_handle!({ runs::FILA_MS => 5 })
    run
  end

  it 'D2: a chamada feita sem resultado fecha como incerta, com nota ao atendente e consulta_falhou, sem chamar de novo' do
    run = comecou(consulta_vencida)
    run.merge_handle!({ runs::CHAMADA_FEITA => true, runs::PASSADA => 'job-morto' }) # o worker morreu no meio da chamada
    allow(SafeFetch).to receive(:fetch)

    described_class.new.perform

    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'consulta_incerta')
    expect(run.handle).not_to have_key(runs::REENFILEIRADA)
    expect(job_http).to have_been_enqueued.with(run.id).once # só o da abertura
    expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    expect(conversation.messages.where(private: true).sole.content).to include('Confira se o pedido foi registrado')
    expect(SafeFetch).not_to have_received(:fetch)
    expect(Autonomia::Agents::Tools::Registry).not_to have_received(:find)
  end

  it 'B4: o job que nunca comecou volta a fila sem gastar a segunda chance, quantas vezes precisar' do
    run = consulta_vencida

    freeze_time do
      described_class.new.perform

      expect(run.reload).to have_attributes(status: 'running', expires_at: 60.seconds.from_now + job_http::FOLGA)
    end
    vencer(run)
    described_class.new.perform

    expect(run.reload.status).to eq('running')
    expect(run.handle).not_to have_key(runs::REENFILEIRADA)
    expect(job_http).to have_been_enqueued.with(run.id).exactly(3).times # o da abertura e um por varredura
    expect(eventos_disparados(run)).to be_empty
  end

  it 'comecou e morreu antes de chamar: reenfileira uma vez; na segunda, fecha failed com consulta_falhou' do
    run = comecou(consulta_vencida)

    described_class.new.perform

    expect(run.reload.handle).to include(runs::REENFILEIRADA => true)
    expect(job_http).to have_been_enqueued.with(run.id).twice
    vencer(run)

    described_class.new.perform

    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
    expect(eventos_disparados(run)).to eq(['consulta_falhou'])
  end

  it 'o resultado gravado com a linha aberta (morreu entre gravar e fechar) so fecha' do
    run = comecou(consulta_vencida)
    run.merge_handle!({ runs::CHAMADA_FEITA => true })
    run.gravar_resultado!('{"ok":1}', sucesso: true, codigo: nil, api_ms: 3)

    described_class.new.perform

    expect(run.reload.status).to eq('done')
    expect(eventos_disparados(run)).to eq(['consulta_concluida'])
  end

  it 'B4: as escritas do varredor conferem o prazo vencido no mesmo comando' do
    run = comecou(consulta_vencida)
    viva = runs.find(run.id)
    runs.where(id: run.id).update_all(expires_at: 2.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations

    limite = described_class::GRACE.ago
    expect(job_http.reenfileirar(viva, vencida_antes_de: limite)).to be(false)
    expect(job_http.reenfileirar_sem_comecar(viva, vencida_antes_de: limite)).to be(false)
    expect(job_http.abandonar(viva, vencida_antes_de: limite)).to be(false)
    viva.merge_handle!({ runs::CHAMADA_FEITA => true })
    expect(job_http.incerta(viva, vencida_antes_de: limite)).to be(false)
    expect(run.reload.status).to eq('running')
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
