require 'rails_helper'

# #1430, desenho D: com a flag `agente_ferramenta_em_segundo_plano` e uma conversa, a chamada HTTP sai do turno (um
# ToolRun `running` e o HttpAssincronaJob na fila agent_tools) e o turno espera por ela até `ESPERA_DO_TURNO`. Chegou:
# o modelo lê o mesmo texto do síncrono. Não chegou: "em andamento", e o resultado vem por evento. Cada exemplo cobre
# um modo de falha.
RSpec.describe Autonomia::Agents::Tools::ConsultaNoTurno do
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
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job) { Autonomia::Agents::Tools::HttpAssincronaJob }
  let(:tool) { ferramenta('consultar_pedido') }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }
  let(:chaves) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { agent_inbox }

  def ferramenta(slug, segundos: 60)
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug, timeout_seconds: segundos,
      endpoint_url: "https://erp.exemplo.test/#{slug}",
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end

  def turno(origem = 77)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: origem)
  end

  def chamada(numero = '42', slug: 'consultar_pedido')
    { 'name' => slug, 'arguments' => { numero: numero }.to_json, 'call_id' => "c#{numero}" }
  end

  describe 'flag desligada: nada muda' do
    it 'a HTTP roda sincrona, no turno, sem execucao, com o mesmo texto do #2426 (o bit ainda nao existe no yml)' do
      sistema_responde('{"status":"enviado"}', chaves: chaves)

      saida = bound.execute(chamada, delivery: turno)

      expect(saida).to eq('{"status":"enviado"}')
      expect(runs.count).to eq(0)
      expect(job).not_to have_been_enqueued
      expect(chaves).to eq([Autonomia::Agents::Tools::ChaveDeIdempotencia.para(tool: tool, turno: turno, params: { 'numero' => 42 })])
    end
  end

  describe 'flag ligada' do
    before { ligar_consulta_em_segundo_plano }

    it 'sem conversa (Testar, Copiloto, playground) continua sincrona' do
      sistema_responde('{"status":"enviado"}')

      expect(bound.execute(chamada, delivery: nil)).to eq('{"status":"enviado"}')
      expect(runs.count).to eq(0)
    end

    it 'abre a execucao running com a ferramenta, a chave do turno e o tempo, e enfileira o job na agent_tools' do
      relogio_do_turno
      entrega = turno

      bound.execute(chamada, delivery: entrega)

      run = runs.sole
      chave = Autonomia::Agents::Tools::ChaveDeIdempotencia.para(tool: tool, turno: turno, params: { 'numero' => 42 })
      expect(run).to have_attributes(status: 'running', autonomia_agent_tool_id: tool.id, arguments: { 'numero' => 42 },
                                     origin_message_id: 77, agent_inbox_id: agent_inbox.id, autonomia_agent_id: agent.id)
      expect(run.faixa).to start_with('consulta_http')
      expect(run.handle).to include(runs::CHAVE_DA_CONSULTA => chave, runs::TEMPO_DA_CONSULTA => 60)
      expect(job).to have_been_enqueued.with(run.id).on_queue('agent_tools')
    end

    it 'chegou na janela: o modelo le o mesmo texto do sincrono, e nenhum evento sai' do
      sistema_responde('{"status":"enviado"}')
      relogio_do_turno { rodar_consultas }

      saida = bound.execute(chamada, delivery: turno)

      expect(saida).to eq('{"status":"enviado"}')
      run = runs.sole
      expect(run).to have_attributes(status: 'done')
      expect(run.handle[runs::ENTREGA]).to eq(runs::ENTREGUE_NO_TURNO)
      expect(eventos_disparados(run)).to be_empty
    end

    it 'a recusa HTTP que chega na janela tem o mesmo texto do sincrono' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable', status: 503))
      relogio_do_turno { rodar_consultas }

      saida = bound.execute(chamada, delivery: turno)

      expect(JSON.parse(saida)).to eq('error' => 'tool_http_error: 503')
    end

    it 'nao chegou: em andamento, o turno desiste com a telemetria, e o resultado vem por evento uma vez' do
      sistema_responde('{"status":"enviado"}')
      relogio_do_turno

      saida = bound.execute(chamada, delivery: turno)

      run = runs.sole
      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(run.handle[runs::ENTREGA]).to eq(runs::DESISTIU_DO_TURNO)
      expect(run.handle[runs::TURNO_DESISTIU]).to include('espera_ms' => 8000)

      rodar_consultas

      expect(run.reload.status).to eq('done')
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o "em andamento" nao vale como dado de sistema' do
      relogio_do_turno

      saida = bound.execute(chamada, delivery: turno)

      expect(bound.consulta_em_andamento?(saida)).to be(true)
    end

    describe 'entrega unica na corrida' do
      it 'o resultado gravado um instante antes da desistencia: o turno entrega, e o job nao dispara evento' do
        sistema_responde('{"status":"enviado"}')
        # O job grava o resultado na última pausa da janela, antes de fechar a linha.
        relogio_do_turno(passo: 8) do
          run = runs.sole
          run.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 10)
        end

        saida = bound.execute(chamada, delivery: turno)
        run = runs.sole
        job.new.perform(run.id)

        expect(saida).to eq('{"status":"enviado"}')
        expect(run.reload.handle[runs::ENTREGA]).to eq(runs::ENTREGUE_NO_TURNO)
        expect(eventos_disparados(run)).to be_empty
        expect(SafeFetch).not_to have_received(:fetch)
      end

      it 'a desistencia um instante antes do resultado: o turno diz em andamento, e o job dispara uma vez' do
        sistema_responde('{"status":"enviado"}')
        relogio_do_turno

        saida = bound.execute(chamada, delivery: turno)
        rodar_consultas
        job.new.perform(runs.sole.id)

        expect(saida).to eq(described_class::EM_ANDAMENTO)
        expect(eventos_disparados(runs.sole)).to eq(['consulta_concluida'])
      end
    end

    describe 'a janela e do turno' do
      it 'duas ferramentas no mesmo turno esperam juntas, sem somar' do
        outra = ferramenta('consultar_estoque')
        pausas = []
        relogio = relogio_do_turno { pausas << :pausa }
        entrega = turno

        bound.execute(chamada, delivery: entrega)
        Autonomia::Agents::Tools::Bound.new(agent: agent, record: outra).execute(chamada(slug: 'consultar_estoque'), delivery: entrega)

        expect(relogio.first).to eq(8.0)
        expect(pausas.size).to eq(32)
      end

      it 'o Answerer dispara todas as chamadas da rodada antes de esperar qualquer uma' do
        tool
        ferramenta('consultar_estoque')
        abertas_na_primeira_pausa = []
        relogio_do_turno { abertas_na_primeira_pausa << runs.count if abertas_na_primeira_pausa.empty? }
        answerer = Autonomia::Agents::Answerer.new(agent: agent, query: 'oi', trust_instruction: true, delivery: turno)

        answerer.send(:execute_tool_calls, [chamada, chamada('7', slug: 'consultar_estoque')])

        expect(abertas_na_primeira_pausa).to eq([2])
        expect(runs.count).to eq(2)
      end

      it 'a espera nao segura a conexao do banco entre as leituras' do
        conexoes = []
        relogio_do_turno { conexoes << ActiveRecord::Base.connection_pool.active_connection? }

        bound.execute(chamada, delivery: turno)

        expect(conexoes).not_to be_empty
        expect(conexoes).to all(be_falsey)
      end
    end

    describe 'reuso: a mesma chamada nunca chama o sistema duas vezes' do
      it 'a mesma chamada no mesmo turno, com a execucao rodando, reusa' do
        relogio_do_turno
        entrega = turno

        2.times { bound.execute(chamada, delivery: entrega) }

        expect(runs.count).to eq(1)
        expect(job).to have_been_enqueued.once
      end

      it 'o turno refeito (outra passada da mesma mensagem) reusa a execucao rodando' do
        relogio_do_turno
        bound.execute(chamada, delivery: turno(77))

        saida = bound.execute(chamada, delivery: turno(77))

        expect(runs.count).to eq(1)
        expect(saida).to eq(described_class::EM_ANDAMENTO)
      end

      it 'outro pedido no mesmo turno abre outra, sem trocar a primeira' do
        relogio_do_turno
        entrega = turno

        bound.execute(chamada('42'), delivery: entrega)
        bound.execute(chamada('43'), delivery: entrega)

        expect(runs.pluck(:status)).to eq(%w[running running])
      end
    end

    it 'argumento que nao converte e a recusa do sincrono, sem abrir' do
      relogio_do_turno

      saida = bound.execute(chamada('quarenta'), delivery: turno)

      expect(JSON.parse(saida)).to eq('error' => 'tool_execution_error')
      expect(runs.count).to eq(0)
    end

    it 'o ajudante segue o desenho com o turno do principal, sem a recusa ajudante_sem_entrega' do
      relogio_do_turno
      vinculo = Autonomia::Agents::Specialist.new(agent: agent, name: 'Ajudante', slug: 'ajudante')
      laco = Autonomia::Agents::Specialists::LacoDoAjudante.new(vinculo: vinculo, delivery: turno)

      saida = laco.executar(bound, chamada)

      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(runs.sole).to have_attributes(conversation_id: conversation.id, autonomia_agent_id: agent.id)
    end

    it 'o especialista comum com HTTP nao vira cotacao' do
      relogio_do_turno
      entrega = turno
      especialista = Autonomia::Agents::Specialist.create!(agent: agent, name: 'Pedidos', slug: 'pedidos', description: 'pedidos',
                                                           instruction: 'Consulte pedidos.')
      runner = Autonomia::Agents::Specialists::Runner.new(specialist: especialista, request: 'pedido 42', delivery: entrega)

      runner.send(:executar, bound, chamada)

      expect(runner.instance_variable_get(:@tentou_cotar)).to be_nil
      expect(entrega.cotacao_existente?).to be(false)
    end
  end
end
