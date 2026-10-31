require 'rails_helper'

# #1430: a passada da ferramenta HTTP assíncrona. Uma chamada, com a chave gravada no aceite e o tempo da ferramenta;
# o resultado fica na execução e o agente fala num turno de evento. Cada exemplo cobre um modo de falha.
RSpec.describe Autonomia::Agents::Tools::HttpAssincronaJob, type: :job do
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
      account: account, agent: agent, name: 'Cotar seguro', slug: 'cotar_seguro', timeout_seconds: 90,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:evento) { Autonomia::Agents::Tools::Evento }
  let(:chaves) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { inbox && agent_inbox }

  # O aceite de verdade (o `Bound`) e o despacho de verdade (o `AsyncDispatcher`): a linha nasce como em produção.
  def consulta_rodando
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool)
                                   .execute({ 'name' => tool.slug, 'arguments' => '{"numero":"42"}' }, delivery: entrega)
    Autonomia::Agents::Tools::AsyncDispatcher.new(delivery: entrega, agent: agent).dispatch!(replied: true)
    entrega.runs.sole.reload
  end

  def responder(corpo)
    allow(SafeFetch).to receive(:fetch) do |_url, **opcoes, &bloco|
      chaves << opcoes[:headers]['Idempotency-Key']
      arquivo = Tempfile.new('resposta')
      arquivo.write(corpo)
      arquivo.rewind
      bloco.call(SafeFetch::Result.new(tempfile: arquivo, filename: 'r.json', content_type: 'application/json'))
    end
  end

  it 'roda na fila propria agent_tools' do
    expect(described_class.new.queue_name).to eq('agent_tools')
    expect(described_class::FILA).to eq(:agent_tools)
  end

  describe 'sucesso' do
    it 'chama uma vez com a chave do aceite e o tempo da ferramenta, grava a resposta, fecha done e dispara o evento' do
      run = consulta_rodando
      responder('{"status":"enviado"}')

      described_class.new.perform(run.id)

      expect(SafeFetch).to have_received(:fetch).once.with(tool.endpoint_url, hash_including(total_timeout: 90))
      expect(chaves).to eq([run.handle[runs::CHAVE_DA_CONSULTA]])
      expect(run.reload).to have_attributes(status: 'done')
      expect(run.handle[runs::RESULTADO_DA_CONSULTA]).to eq('{"status":"enviado"}')
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'a resposta grande e gravada com o mesmo teto e aviso de corte que o modelo le no sincrono' do
      run = consulta_rodando
      responder({ texto: 'x' * 9_000 }.to_json)

      described_class.new.perform(run.id)

      gravado = run.reload.handle[runs::RESULTADO_DA_CONSULTA]
      expect(gravado.length).to eq(Autonomia::Agents::Tools::Bound::MAX_OUTPUT_CHARS)
      expect(gravado).to end_with(Autonomia::Agents::Tools::Bound::AVISO_DE_CORTE)
    end

    it 'o slug cotar_seguro e resolvido pela ferramenta da linha, nunca pelo catalogo da Lia' do
      run = consulta_rodando
      responder('{"ok":true}')
      allow(Autonomia::Agents::Tools::Registry).to receive(:find).and_call_original

      described_class.new.perform(run.id)

      expect(Autonomia::Agents::Tools::Registry).not_to have_received(:find)
      expect(run.reload.status).to eq('done')
    end

    it 'solta a conexao do banco antes da chamada HTTP' do
      run = consulta_rodando
      ordem = []
      allow(ActiveRecord::Base.connection_handler).to receive(:clear_active_connections!).and_wrap_original do |original, *args|
        ordem << :soltou
        original.call(*args)
      end
      allow(SafeFetch).to receive(:fetch) do
        ordem << :chamou
        raise SafeFetch::FetchError, 'x'
      end

      described_class.new.perform(run.id)

      expect(ordem).to eq(%i[soltou chamou])
    end
  end

  describe 'falha' do
    it 'erro HTTP grava a saida de recusa do sincrono, fecha failed e dispara consulta_falhou' do
      run = consulta_rodando
      erro = SafeFetch::HttpError.new('503 Service Unavailable', status: 503)
      allow(SafeFetch).to receive(:fetch).and_raise(erro)

      described_class.new.perform(run.id)

      erro_do_executor = Autonomia::Agents::Tools::HttpExecutor::Error.new('tool_http_error: 503', status: 503)
      esperado = Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool).texto_da_recusa_http(erro_do_executor)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'tool_http_error')
      expect(run.handle[runs::RESULTADO_DA_CONSULTA]).to eq(esperado)
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'tempo esgotado tambem e consulta_falhou' do
      run = consulta_rodando
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'execution expired')

      described_class.new.perform(run.id)

      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'tool_execution_error')
      expect(JSON.parse(run.handle[runs::RESULTADO_DA_CONSULTA])).to eq('error' => 'tool_execution_error')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'ferramenta desligada depois do aceite: falha ferramenta_indisponivel com evento, sem chamar' do
      run = consulta_rodando
      tool.update!(enabled: false)
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'ferramenta_indisponivel')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'ferramenta apagada depois do aceite: mesma falha' do
      run = consulta_rodando
      tool.destroy!
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'ferramenta_indisponivel')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'operador puxou o freio (agente desligado): bloqueia sem chamar e sem evento' do
      run = consulta_rodando
      agent.update!(enabled: false)
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(run.reload).to have_attributes(status: 'blocked', failure_code: 'nao_autorizado')
      expect(eventos_disparados(run)).to be_empty
    end
  end

  describe 'consulta trocada no meio' do
    it 'o resultado da supersedida fica gravado na linha e nao e falado' do
      run = consulta_rodando
      allow(SafeFetch).to receive(:fetch) do |_url, **_opcoes, &bloco|
        runs.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations -- o cliente pediu outra coisa
        arquivo = Tempfile.new('resposta')
        arquivo.write('{"status":"antigo"}')
        arquivo.rewind
        bloco.call(SafeFetch::Result.new(tempfile: arquivo, filename: 'r.json', content_type: 'application/json'))
      end

      described_class.new.perform(run.id)

      expect(run.reload.status).to eq('superseded')
      expect(run.handle[runs::RESULTADO_DA_CONSULTA]).to eq('{"status":"antigo"}')
      expect(eventos_disparados(run)).to be_empty
    end

    it 'linha que ja nao roda nao chama' do
      run = consulta_rodando
      run.finish!('done')
      allow(SafeFetch).to receive(:fetch)

      described_class.new.perform(run.id)

      expect(SafeFetch).not_to have_received(:fetch)
    end
  end
end
