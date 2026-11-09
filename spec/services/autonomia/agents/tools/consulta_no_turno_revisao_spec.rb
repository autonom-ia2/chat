require 'rails_helper'

# #1430, revisão do PR assíncrono (lado do turno): a janela por rodada (D1), o mesmo pedido numa mensagem nova (B2), o
# turno de evento síncrono (B3), a falha de infraestrutura no disparo (B5), a repetição depois da falha (B8), o turno
# refeito (B9) e os menores (B10). Cada exemplo cobre um modo de falha apontado na revisão.
RSpec.describe Autonomia::Agents::Tools::ConsultaNoTurno do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job) { Autonomia::Agents::Tools::HttpAssincronaJob }
  let(:tool) { ferramenta('consultar_pedido') }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    tool
  end

  def ferramenta(slug)
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug, timeout_seconds: 60,
      endpoint_url: "https://erp.exemplo.test/#{slug}",
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end

  def turno(origem = 77)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: origem)
  end

  def chamada(numero = '42', slug: 'consultar_pedido', id: nil)
    { 'name' => slug, 'arguments' => { numero: numero }.to_json, 'call_id' => id || "c#{numero}" }
  end

  def answerer(entrega)
    Autonomia::Agents::Answerer.new(agent: agent, query: 'oi', trust_instruction: true, delivery: entrega)
  end

  def saidas(resultado)
    resultado.map { |item| item[:output] }
  end

  describe 'com a flag' do
    before { ligar_consulta_em_segundo_plano }

    describe 'D1: a janela e da rodada' do
      it 'cada rodada do Answerer abre a sua janela de 8 s; a segunda nao herda a primeira vencida' do
        relogio = relogio_do_turno
        entrega = turno

        answerer(entrega).send(:execute_tool_calls, [chamada('1')])
        answerer(entrega).send(:execute_tool_calls, [chamada('2')])

        expect(relogio.first).to eq(16.0)
        expect(runs.order(:id).map { |run| run.handle[runs::TURNO_DESISTIU]['espera_ms'] }).to eq([8000, 8000])
      end

      it 'B10: a espera de quem desiste conta do comeco da janela da rodada, nao da propria chamada' do
        relogio_do_turno
        resultado = answerer(turno).send(:execute_tool_calls, [chamada('1'), chamada('2')])

        expect(saidas(resultado)).to eq([described_class::EM_ANDAMENTO] * 2)
        expect(runs.order(:id).map { |run| run.handle[runs::TURNO_DESISTIU]['espera_ms'] }).to eq([8000, 8000])
      end
    end

    describe 'B2: o mesmo pedido numa mensagem nova' do
      it 'com a chamada feita, o turno novo se pendura na execucao antiga: sem superar e sem chamar de novo' do
        relogio_do_turno
        bound.execute(chamada, delivery: turno(77))
        antiga = runs.sole
        antiga.merge_handle!({ runs::CHAMADA_FEITA => true, runs::FILA_MS => 5 })

        saida = bound.execute(chamada, delivery: turno(78))

        expect(saida).to eq(described_class::EM_ANDAMENTO)
        expect(runs.sole.id).to eq(antiga.id)
        expect(antiga.reload.status).to eq('running')
        expect(job).to have_been_enqueued.once
      end

      it 'concluida, o mesmo pedido numa mensagem nova continua sendo outro pedido (decisao A)' do
        chaves = sistema_responde('{"status":"enviado"}')
        relogio_do_turno { rodar_consultas }
        bound.execute(chamada, delivery: turno(77))

        expect(bound.execute(chamada, delivery: turno(78))).to eq('{"status":"enviado"}')
        expect(runs.pluck(:status)).to eq(%w[done done])
        expect(chaves.uniq.size).to eq(2)
      end
    end

    it 'B3: o turno de um evento roda a consulta sincrona, sem abrir execucao' do
      sistema_responde('{"status":"ok"}')
      do_evento = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, evento: 'consulta_concluida')

      expect(bound.execute(chamada, delivery: do_evento)).to eq('{"status":"ok"}')
      expect(runs.count).to eq(0)
      expect(job).not_to have_been_enqueued
    end

    describe 'B5: erro de infraestrutura no disparo' do
      it 'o Redis fora no enfileiramento nao derruba o turno: recusa nomeada, sem segunda tentativa e sem linha viva' do
        relogio_do_turno
        allow(job).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'redis fora')

        resultado = nil
        expect { resultado = answerer(turno).send(:execute_tool_calls, [chamada]) }.not_to raise_error

        expect(JSON.parse(saidas(resultado).sole)).to eq('error' => 'tool_execution_error')
        expect(job).to have_received(:perform_later).once
        expect(runs.sole).to have_attributes(status: 'failed', failure_code: 'consulta_nao_disparou')
      end

      it 'o banco falhando no disparo da execucao vira a mesma recusa' do
        relogio_do_turno
        allow(Autonomia::Agents::ToolRun).to receive(:travar!).and_raise(ActiveRecord::ConnectionTimeoutError)

        saida = nil
        expect { saida = bound.execute(chamada, delivery: turno) }.not_to raise_error

        expect(JSON.parse(saida)).to eq('error' => 'tool_execution_error')
      end
    end

    it 'B8: depois de um 5xx no mesmo turno, a mesma chamada chama a API de novo, com a mesma chave' do
      chaves = []
      allow(SafeFetch).to receive(:fetch) do |_url, **opcoes|
        chaves << opcoes[:headers]['Idempotency-Key']
        raise SafeFetch::HttpError.new('503 Service Unavailable', status: 503)
      end
      relogio_do_turno { rodar_consultas }
      entrega = turno

      2.times { bound.execute(chamada, delivery: entrega) }

      expect(chaves.size).to eq(2)
      expect(chaves.uniq.size).to eq(1)
      expect(runs.pluck(:status)).to eq(%w[failed failed])
    end

    describe 'B9: o turno refeito (a mesma chave) com a execucao concluida' do
      it 'entregue no turno: reaproveita, sem chamar de novo, e le o mesmo resultado' do
        sistema_responde('{"status":"enviado"}')
        relogio_do_turno { rodar_consultas }
        bound.execute(chamada, delivery: turno(77))

        saida = bound.execute(chamada(id: 'outro_call_id'), delivery: turno(77))

        expect(saida).to eq('{"status":"enviado"}')
        expect(SafeFetch).to have_received(:fetch).once
        expect(runs.count).to eq(1)
      end

      it 'entregue por evento: o modelo le que o resultado ja foi informado ao cliente' do
        sistema_responde('{"status":"enviado"}')
        relogio_do_turno
        bound.execute(chamada, delivery: turno(77))
        rodar_consultas

        saida = bound.execute(chamada(id: 'outro_call_id'), delivery: turno(77))

        expect(saida).to eq(described_class::JA_INFORMADO)
        expect(SafeFetch).to have_received(:fetch).once
      end
    end

    describe 'B10' do
      it 'duas chamadas identicas na mesma rodada sao dois pedidos: duas execucoes, duas chaves' do
        chaves = sistema_responde('{"status":"ok"}')
        abertas_na_primeira_pausa = []
        relogio_do_turno do
          abertas_na_primeira_pausa << runs.count if abertas_na_primeira_pausa.empty?
          rodar_consultas
        end

        resultado = answerer(turno).send(:execute_tool_calls, [chamada(id: 'a'), chamada(id: 'b')])

        expect(abertas_na_primeira_pausa).to eq([2])
        expect(saidas(resultado)).to eq(['{"status":"ok"}'] * 2)
        expect(runs.count).to eq(2)
        expect(chaves.size).to eq(2)
        expect(chaves.uniq.size).to eq(2)
      end

      it 'a falha que chega na janela registra a recusa, como o sincrono' do
        allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found', status: 404))
        relogio_do_turno { rodar_consultas }
        antes = Autonomia::Agents::Tools::Recusa.registradas

        saida = bound.execute(chamada, delivery: turno)

        expect(JSON.parse(saida)).to eq('error' => 'tool_http_error: 404')
        expect(Autonomia::Agents::Tools::Recusa.registradas).to eq(antes + 1)
      end

      it 'o 2xx entregue por evento tambem conclui: a repeticao seguinte no turno e outro pedido' do
        chaves = sistema_responde('{"status":"ok"}')
        relogio_do_turno
        entrega = turno
        bound.execute(chamada, delivery: entrega)
        rodar_consultas

        expect(bound.execute(chamada(id: 'r2'), delivery: entrega)).to eq(described_class::JA_INFORMADO)
        relogio_do_turno { rodar_consultas }
        expect(bound.execute(chamada(id: 'r3'), delivery: entrega)).to eq('{"status":"ok"}')
        expect(chaves.uniq.size).to eq(2)
      end
    end
  end
end
