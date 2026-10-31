require 'rails_helper'

# #1430: a ferramenta HTTP com tempo acima de `Tool::LIMIAR_ASSINCRONO` não segura o turno. O `Bound` só ACEITA: abre a
# execução com a ferramenta, os argumentos tipados e a Idempotency-Key do turno, e devolve ao modelo o texto neutro. A
# chamada HTTP acontece depois, no `HttpAssincronaJob`. Cada exemplo cobre um modo de falha do aceite.
RSpec.describe Autonomia::Agents::Tools::Bound do
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
  let(:consulta) { Autonomia::Agents::Tools::ConsultaAssincrona }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def ferramenta(segundos: 60, slug: 'consultar_pedido')
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug, timeout_seconds: segundos,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end

  def turno(origem = 77, **extra)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: origem, **extra)
  end

  def chamada(numero = '42')
    { 'name' => 'consultar_pedido', 'arguments' => { numero: numero }.to_json, 'call_id' => 'c1' }
  end

  before { allow(SafeFetch).to receive(:fetch).and_raise('a chamada HTTP não pode acontecer dentro do turno') }

  describe 'o limiar: modo, não teto' do
    it 'ferramenta de 25 s continua sincrona e roda no turno' do
      tool = ferramenta(segundos: 25)
      executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"status":"enviado"}')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(executor)

      saida = described_class.new(agent: agent, record: tool).execute(chamada, delivery: turno)

      expect(tool.assincrona?).to be(false)
      expect(described_class.new(agent: agent, record: tool).async?).to be(false)
      expect(saida).to eq('{"status":"enviado"}')
      expect(runs.count).to eq(0)
    end

    it 'ferramenta de 26 s vira assincrona: aceita sem chamar o sistema de fora' do
      tool = ferramenta(segundos: 26)

      saida = described_class.new(agent: agent, record: tool).execute(chamada, delivery: turno)

      expect(tool.assincrona?).to be(true)
      expect(described_class.new(agent: agent, record: tool).async?).to be(true)
      expect(saida).to eq(consulta::ACEITE)
      expect(SafeFetch).not_to have_received(:fetch)
    end
  end

  describe 'a abertura' do
    it 'abre a execucao pendente com a ferramenta, os argumentos tipados e a Idempotency-Key do turno' do
      tool = ferramenta
      entrega = turno

      described_class.new(agent: agent, record: tool).execute(chamada('42'), delivery: entrega)

      run = entrega.runs.sole
      chave = Autonomia::Agents::Tools::ChaveDeIdempotencia.para(tool: tool, turno: turno, params: { 'numero' => 42 })
      expect(run).to have_attributes(status: 'pending', slug: 'consultar_pedido', autonomia_agent_tool_id: tool.id,
                                     arguments: { 'numero' => 42 }, origin_message_id: 77, agent_inbox_id: agent_inbox.id)
      expect(run.handle[runs::CHAVE_DA_CONSULTA]).to eq(chave)
      expect(run).to be_consulta_http
    end

    it 'o mesmo pedido no mesmo turno e recusado e nao abre outra' do
      tool = ferramenta
      entrega = turno
      bound = described_class.new(agent: agent, record: tool)
      bound.execute(chamada('42'), delivery: entrega)

      saida = bound.execute(chamada(42), delivery: entrega)

      expect(JSON.parse(saida)).to eq('error' => 'execucao_ja_aberta_neste_turno')
      expect(runs.count).to eq(1)
    end

    it 'mensagem nova com o mesmo pedido e a consulta rodando: ja estou consultando, sem abrir outra' do
      tool = ferramenta
      bound = described_class.new(agent: agent, record: tool)
      primeiro = turno(77)
      bound.execute(chamada('42'), delivery: primeiro)
      primeiro.runs.sole.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)

      segundo = turno(78)
      saida = bound.execute(chamada('42'), delivery: segundo)

      expect(saida).to eq(consulta::JA_CONSULTANDO)
      expect(segundo.runs).to be_empty
      expect(runs.count).to eq(1)
      expect(primeiro.runs.sole.reload.status).to eq('running')
    end

    it 'mensagem nova com outro pedido supersede a consulta antiga e abre a nova' do
      tool = ferramenta
      bound = described_class.new(agent: agent, record: tool)
      primeiro = turno(77)
      bound.execute(chamada('42'), delivery: primeiro)
      primeiro.runs.sole.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)

      segundo = turno(78)
      saida = bound.execute(chamada('43'), delivery: segundo)

      expect(saida).to eq(consulta::ACEITE)
      expect(primeiro.runs.sole.reload.status).to eq('superseded')
      expect(segundo.runs.sole).to have_attributes(status: 'pending', arguments: { 'numero' => 43 })
    end

    it 'sem conversa (o Testar) recusa como hoje' do
      tool = ferramenta

      saida = described_class.new(agent: agent, record: tool).execute(chamada, delivery: nil)

      expect(JSON.parse(saida)).to eq('error' => 'async_indisponivel_nesta_superficie')
      expect(runs.count).to eq(0)
    end

    it 'o turno de um evento nao abre consulta' do
      tool = ferramenta
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, evento: 'consulta_concluida')

      saida = described_class.new(agent: agent, record: tool).execute(chamada, delivery: entrega)

      expect(JSON.parse(saida)).to eq('error' => 'turno_de_evento')
      expect(runs.count).to eq(0)
    end

    it 'argumento que nao converte para o tipo e recusa nomeada, sem abrir' do
      tool = ferramenta

      saida = described_class.new(agent: agent, record: tool).execute(chamada('quarenta'), delivery: turno)

      expect(JSON.parse(saida)).to eq('error' => 'tool_execution_error')
      expect(runs.count).to eq(0)
    end
  end

  describe 'slug igual ao da Lia' do
    it 'a HTTP chamada cotar_seguro abre a execucao dela, sem tocar na cotacao viva da conversa' do
      lia = runs.open!(agent: agent, slug: 'cotar_seguro', arguments: {},
                       scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id, faixa: '' })
      lia.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      tool = ferramenta(slug: 'cotar_seguro')
      entrega = turno

      saida = described_class.new(agent: agent, record: tool).execute(chamada, delivery: entrega)

      expect(saida).to eq(consulta::ACEITE)
      expect(lia.reload.status).to eq('running')
      expect(entrega.runs.sole).to have_attributes(slug: 'cotar_seguro', autonomia_agent_tool_id: tool.id)
      expect(runs.nativas.pluck(:id)).to eq([lia.id])
    end
  end

  describe 'o despacho' do
    it 'promove com o prazo da ferramenta e enfileira o job HTTP, nao o motor da Lia' do
      tool = ferramenta(segundos: 90)
      entrega = turno
      described_class.new(agent: agent, record: tool).execute(chamada, delivery: entrega)

      freeze_time do
        Autonomia::Agents::Tools::AsyncDispatcher.new(delivery: entrega, agent: agent).dispatch!(replied: true)

        expect(entrega.runs.sole.reload).to have_attributes(status: 'running', expires_at: 90.seconds.from_now +
                                                             Autonomia::Agents::Tools::HttpAssincronaJob::FOLGA)
      end
      expect(Autonomia::Agents::Tools::HttpAssincronaJob).to have_been_enqueued.with(entrega.runs.sole.id)
      expect(Autonomia::Agents::Tools::AsyncRunJob).not_to have_been_enqueued
    end
  end
end
