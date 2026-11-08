require 'rails_helper'

# TESTADOR (pré-merge #1430): cenários sem cobertura nos specs do PR.
RSpec.describe Autonomia::Agents::Tools::ConsultaNoTurno, type: :job do
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
  let(:segredo_header) { 'segredo-da-conta-123' }
  let(:segredo_query) { 'qk9zzqueryvalor' }
  let(:tool) { ferramenta(account, agent) }
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job) { Autonomia::Agents::Tools::HttpAssincronaJob }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { agent_inbox }

  def ferramenta(conta, dono)
    Autonomia::Agents::Tool.create!(
      account: conta, agent: dono, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: "https://erp.exemplo.test/pedidos?token=#{segredo_query}",
      headers_config: [{ key: 'x-api-key', value: segredo_header, secret: true }],
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número', required: true }]
    )
  end

  def turno(origem = 77, conversa: conversation, vinculo: agent_inbox)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: vinculo, origin_message_id: origem)
  end

  def chamada(numero = '42')
    { 'name' => 'consultar_pedido', 'arguments' => { numero: numero }.to_json, 'call_id' => "c#{numero}" }
  end

  describe 'flag ligada' do
    before { ligar_consulta_em_segundo_plano }

    it 'C08 CAS: com instancias desatualizadas, entregue x desistencia, so um vence (nos dois sentidos)' do
      relogio_do_turno
      described_class.new(tool: tool, agente: agent, turno: turno(77), args: { 'numero' => '1' }).disparar
      described_class.new(tool: tool, agente: agent, turno: turno(77), args: { 'numero' => '2' }).disparar
      r1, r2 = runs.order(:id).to_a

      a = runs.find(r1.id)
      b = runs.find(r1.id)
      expect([a.marcar_entregue!, b.marcar_desistencia!(espera_ms: 1)]).to eq([true, false])
      expect(runs.find(r1.id).entrega).to eq(runs::ENTREGUE_NO_TURNO)

      c = runs.find(r2.id)
      d = runs.find(r2.id)
      expect([c.marcar_desistencia!(espera_ms: 1), d.marcar_entregue!]).to eq([true, false])
      expect(runs.find(r2.id).entrega).to eq(runs::DESISTIU_DO_TURNO)
    end

    it 'C12 mensagem nova com o mesmo pedido: a antiga e superada e o job dela nao chama' do
      relogio_do_turno
      allow(SafeFetch).to receive(:fetch)
      bound.execute(chamada, delivery: turno(77))
      antiga = runs.sole

      bound.execute(chamada, delivery: turno(78))

      expect(runs.count).to eq(2)
      expect(antiga.reload.status).to eq('superseded')
      expect(runs.where.not(id: antiga.id).sole.status).to eq('running')
      job.new.perform(antiga.id)
      expect(SafeFetch).not_to have_received(:fetch)
    end

    it 'C13a 2xx na janela avanca a ocorrencia: a repeticao identica e outro pedido, outra chave' do
      chaves = sistema_responde('{"status":"ok"}')
      relogio_do_turno { rodar_consultas }
      entrega = turno

      2.times { bound.execute(chamada, delivery: entrega) }

      expect(runs.count).to eq(2)
      expect(chaves.size).to eq(2)
      expect(chaves.uniq.size).to eq(2)
    end

    it 'C13b 5xx na janela nao avanca a ocorrencia: a repeticao identica mantem a chave' do
      chaves = []
      allow(SafeFetch).to receive(:fetch) do |_u, **op|
        chaves << op[:headers]['Idempotency-Key']
        raise SafeFetch::HttpError.new('503 Service Unavailable', status: 503)
      end
      relogio_do_turno { rodar_consultas }
      entrega = turno

      2.times { bound.execute(chamada, delivery: entrega) }

      pedido = Autonomia::Agents::Tools::ChaveDeIdempotencia.pedido(tool, entrega, { 'numero' => 42 })
      expect(entrega.ocorrencia(pedido)).to eq(0)
      expect(chaves.uniq.size).to eq(1)
      # B8: a repetição depois da falha chama a API de novo, como o síncrono.
      expect(chaves.size).to eq(2)
    end

    it 'C15 timeout total: failed, consulta_falhou, sem levantar' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::TotalTimeoutError, 'tempo total')
      relogio_do_turno
      bound.execute(chamada, delivery: turno)
      run = runs.sole

      expect { job.new.perform(run.id) }.not_to raise_error
      run.reload
      expect(run.status).to eq('failed')
      expect(run.failure_code).to eq('tool_execution_error')
      expect(JSON.parse(run.resultado_da_consulta)).to include('error')
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'C16 resposta enorme: cortada no teto do modelo com o aviso de corte' do
      sistema_responde({ itens: 'x' * 60_000 }.to_json)
      relogio_do_turno { rodar_consultas }

      saida = bound.execute(chamada, delivery: turno)

      expect(saida.length).to eq(Autonomia::Agents::Tools::Bound::MAX_OUTPUT_CHARS)
      expect(saida).to end_with(Autonomia::Agents::Tools::Bound::AVISO_DE_CORTE)
      expect(runs.sole.resultado_da_consulta.length).to be <= Autonomia::Agents::Tools::Bound::MAX_OUTPUT_CHARS
    end

    describe 'C17 segredo' do
      let(:log) { StringIO.new }

      before { allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log)) }

      def sem_segredo(texto)
        expect(texto.to_s).not_to include(segredo_header)
        expect(texto.to_s).not_to include(segredo_query)
      end

      it '2xx que ecoa o header e a query: nada no handle, na nota do evento, nem no log' do
        sistema_responde({ eco: segredo_header, q: segredo_query, status: 'ok' }.to_json)
        relogio_do_turno
        bound.execute(chamada, delivery: turno)
        run = runs.sole
        rodar_consultas

        run.reload
        expect(run.status).to eq('done')
        expect(run.resultado_da_consulta).to include('ok')
        sem_segredo(run.handle.to_json)
        sem_segredo(run.arguments.to_json)
        sem_segredo(Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'consulta_concluida').nota_do_sistema)
        expect(log.string).to include("run=#{run.id}")
        sem_segredo(log.string)
      end

      it '4xx com o segredo no corpo do erro: nada no handle nem no log' do
        allow(SafeFetch).to receive(:fetch).and_raise(
          SafeFetch::HttpError.new('401 Unauthorized', status: 401, body_excerpt: "chave #{segredo_header} token #{segredo_query} invalida")
        )
        relogio_do_turno
        bound.execute(chamada, delivery: turno)
        run = runs.sole
        rodar_consultas

        run.reload
        expect(run.status).to eq('failed')
        sem_segredo(run.handle.to_json)
        sem_segredo(Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'consulta_falhou').nota_do_sistema)
        sem_segredo(log.string)
      end
    end

    describe 'C18 isolamento entre contas' do
      let(:outra_conta) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
      let(:outra_conversa) { create(:conversation, account: outra_conta, inbox: create(:inbox, account: outra_conta), assignee: nil) }
      let(:outro_agente) do
        Autonomia::Agents::Agent.create!(account: outra_conta, name: 'Bot B', agent_type: 'custom', status: :active, enabled: true,
                                         instruction: 'Atenda.', config: { 'with_knowledge' => false })
      end

      def outro_vinculo
        @outro_vinculo ||= Autonomia::Agents::AgentInbox.create!(agent: outro_agente, inbox: outra_conversa.inbox, account: outra_conta,
                                                                 agent_bot: create(:agent_bot, account: outra_conta))
      end

      it 'execucao apontando a ferramenta de outra conta: indisponivel, sem chamar' do
        tool_b = ferramenta(outra_conta, outro_agente)
        relogio_do_turno
        allow(SafeFetch).to receive(:fetch)
        bound.execute(chamada, delivery: turno)
        run = runs.sole
        run.update_column(:autonomia_agent_tool_id, tool_b.id) # rubocop:disable Rails/SkipsModelValidations

        job.new.perform(run.id)

        expect(SafeFetch).not_to have_received(:fetch)
        expect(run.reload).to have_attributes(status: 'failed', failure_code: 'ferramenta_indisponivel')
      end

      it 'o mesmo pedido nas duas contas nao reaproveita execucao nem chave e cada resultado fica na sua conta' do
        tool_b = ferramenta(outra_conta, outro_agente)
        outro_vinculo
        relogio_do_turno

        bound.execute(chamada, delivery: turno(77))
        Autonomia::Agents::Tools::Bound.new(agent: outro_agente, record: tool_b)
                                       .execute(chamada, delivery: turno(77, conversa: outra_conversa, vinculo: outro_vinculo))

        expect(runs.count).to eq(2)
        a = runs.find_by(account_id: account.id)
        b = runs.find_by(account_id: outra_conta.id)
        expect([a.conversation_id, a.autonomia_agent_tool_id]).to eq([conversation.id, tool.id])
        expect([b.conversation_id, b.autonomia_agent_tool_id]).to eq([outra_conversa.id, tool_b.id])
        expect(a.handle[runs::CHAVE_DA_CONSULTA]).not_to eq(b.handle[runs::CHAVE_DA_CONSULTA])

        sistema_responde('{"dono":"A"}')
        job.new.perform(a.id)
        expect(b.reload.resultado_gravado?).to be(false)
        expect(b.status).to eq('running')
      end
    end
  end
end
