require 'rails_helper'

# #1430, revisão final do PR assíncrono (lado do turno): a entrega única entre turnos (A), o resultado nunca mudo na
# falha da espera (B2), o defeito nosso no rastreador (C), a incerteza que segura o mesmo pedido (F), a recusa
# `bloqueada` lida pelo turno e a Lia de fora (G). Cada exemplo cobre um modo de falha apontado na revisão.
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
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    tool
    ligar_consulta_em_segundo_plano
  end

  def turno(origem)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: origem)
  end

  def chamada(id = 'c42')
    { 'name' => 'consultar_pedido', 'arguments' => { numero: '42' }.to_json, 'call_id' => id }
  end

  # A mensagem mais nova do cliente: o stamp do debounce que o `Responder#turno_superado?` lê.
  def cliente_escreveu(message_id)
    allow(Autonomia::Agents::Fase2).to receive(:ligada?).and_return(true)
    stamp = { Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => message_id } }
    conversation.update!(additional_attributes: conversation.additional_attributes.to_h.merge(stamp))
  end

  # O turno 10 abre a consulta e desiste; o turno 12 (mensagem nova, mesmo pedido) se pendura nela.
  def dois_turnos_na_mesma_linha
    relogio_do_turno
    sistema_responde('{"status":"enviado"}')
    primeiro = turno(10)
    described_class.new(tool: tool, agente: agent, turno: primeiro, args: { 'numero' => '42' }).disparar
    run = runs.sole
    run.merge_handle!({ runs::CHAMADA_FEITA => true })
    segundo = turno(12)
    described_class.new(tool: tool, agente: agent, turno: segundo, args: { 'numero' => '42' }).disparar
    expect(runs.count).to eq(1)
    run.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 5)
    [primeiro, segundo, run]
  end

  def ler(entrega)
    described_class.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => '42' }).resultado
  end

  describe 'A: a entrega e de um turno so' do
    it 'dois turnos vivos na mesma linha: o primeiro entrega; o outro le que ja foi informado' do
      primeiro, segundo, run = dois_turnos_na_mesma_linha
      cliente_escreveu(10)

      expect(ler(primeiro)).to eq('{"status":"enviado"}')
      expect(ler(segundo)).to eq(described_class::JA_INFORMADO)
      expect(run.reload.handle).to include(runs::ENTREGA => runs::ENTREGUE_NO_TURNO, runs::ENTREGUE_POR => 'mensagem:10')
    end

    it 'o mesmo turno refeito (outro objeto, a mesma mensagem) rele o resultado' do
      primeiro, _segundo, = dois_turnos_na_mesma_linha
      cliente_escreveu(10)

      expect(ler(primeiro)).to eq('{"status":"enviado"}')
      expect(ler(turno(10))).to eq('{"status":"enviado"}')
    end

    it 'o turno que entregou foi superado por mensagem nova antes de postar: o turno novo entrega, e o resultado nao se perde' do
      primeiro, segundo, run = dois_turnos_na_mesma_linha
      cliente_escreveu(12)

      expect(ler(primeiro)).to eq('{"status":"enviado"}')
      expect(ler(segundo)).to eq('{"status":"enviado"}')
      expect(run.reload.handle[runs::ENTREGUE_POR]).to eq('mensagem:12')
      expect(eventos_disparados(run)).to be_empty
    end

    it 'o CAS falho rele a linha: a desistencia gravada entre a leitura e a marca vira ja informado, sem entregar' do
      relogio_do_turno
      entrega = turno(10)
      described_class.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => '42' }).disparar
      run = runs.sole
      run.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 5)
      allow_any_instance_of(runs).to receive(:marcar_entregue!).and_wrap_original do |original, **opcoes| # rubocop:disable RSpec/AnyInstance
        runs.find(original.receiver.id).desistir_sem_turno!
        original.call(**opcoes)
      end

      expect(ler(entrega)).to eq(described_class::JA_INFORMADO)
      expect(run.reload.entrega).to eq(runs::DESISTIU_DO_TURNO)
    end
  end

  describe 'B2 e C: a falha na espera nao cala o resultado' do
    it 'o banco falhando na espera com a execucao aberta: o turno desiste e diz em andamento; o evento fala depois' do
      relogio_do_turno
      sistema_responde('{"status":"enviado"}')
      allow_any_instance_of(described_class).to receive(:aguardar).and_raise(ActiveRecord::ConnectionTimeoutError) # rubocop:disable RSpec/AnyInstance

      saida = bound.execute(chamada, delivery: turno(10))

      run = runs.sole
      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(run.entrega).to eq(runs::DESISTIU_DO_TURNO)
      rodar_consultas
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o defeito nosso na espera vai ao rastreador e tambem nao cala o resultado' do
      relogio_do_turno
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
      allow_any_instance_of(described_class).to receive(:aguardar).and_raise(NoMethodError, 'defeito') # rubocop:disable RSpec/AnyInstance

      saida = bound.execute(chamada, delivery: turno(10))

      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(rastreador).to have_received(:capture_exception)
      expect(runs.sole.entrega).to eq(runs::DESISTIU_DO_TURNO)
    end

    it 'sem execucao (o disparo falhou no banco), a recusa continua sendo nao disparou, sem rastreador' do
      relogio_do_turno
      allow(ChatwootExceptionTracker).to receive(:new)
      allow(runs).to receive(:travar!).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect(JSON.parse(bound.execute(chamada, delivery: turno(10)))).to eq('error' => 'tool_execution_error')
      expect(ChatwootExceptionTracker).not_to have_received(:new)
    end

    it 'o defeito nosso no disparo vai ao rastreador, e o turno recusa sem cair' do
      relogio_do_turno
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
      allow(runs).to receive(:travar!).and_raise(NoMethodError, 'defeito')

      expect(JSON.parse(bound.execute(chamada, delivery: turno(10)))).to eq('error' => 'tool_execution_error')
      expect(rastreador).to have_received(:capture_exception)
    end
  end

  describe 'F: a incerta segura o mesmo pedido' do
    it 'numa mensagem nova, o mesmo pedido le a incerta ja informada, sem chamar o sistema de fora e sem abrir outra' do
      relogio_do_turno
      described_class.new(tool: tool, agente: agent, turno: turno(10), args: { 'numero' => '42' }).disparar
      run = runs.sole
      run.merge_handle!({ runs::CHAMADA_FEITA => true, runs::ENTREGA => runs::DESISTIU_DO_TURNO })
      job.incerta(run, vencida_antes_de: nil)
      expect(run.reload.status).to eq('failed')
      allow(SafeFetch).to receive(:fetch)
      clear_enqueued_jobs

      saida = bound.execute(chamada('c2'), delivery: turno(12))

      expect(saida).to eq(described_class::INCERTA_JA_INFORMADA)
      expect(runs.count).to eq(1)
      expect(job).not_to have_been_enqueued
      expect(SafeFetch).not_to have_received(:fetch)
    end
  end

  describe 'G: a recusa bloqueada e a Lia' do
    it 'o turno que ainda espera uma consulta bloqueada le a recusa bloqueada' do
      relogio_do_turno do
        agent_inbox.agent.update!(enabled: false)
        rodar_consultas
      end
      allow(SafeFetch).to receive(:fetch)

      saida = bound.execute(chamada, delivery: turno(10))

      expect(JSON.parse(saida)['error']).to eq(runs::BLOQUEADA)
      expect(runs.sole).to have_attributes(status: 'failed', failure_code: runs::BLOQUEADA)
      expect(SafeFetch).not_to have_received(:fetch)
    end

    it 'nao se aplica ao agente de cotacao (a Lia): a ferramenta dela fica sincrona' do
      agent.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.aplica?(tool.reload, turno(10))).to be(false)
    end

    it 'nem quando quem fala na conversa e a Lia, com a ferramenta de outro agente' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom', status: :active, enabled: true,
                                               instruction: 'X', config: { 'with_knowledge' => false })
      tool.update_column(:autonomia_agent_id, outro.id) # rubocop:disable Rails/SkipsModelValidations
      agent.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.aplica?(tool.reload, turno(10))).to be(false)
      sem_vinculo = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil)
      expect(described_class.aplica?(tool.reload, sem_vinculo)).to be(true)
    end
  end
end
