require 'rails_helper'

# #2144 (LGPD): conversa excluída por qualquer caminho, e o texto do cliente não sobra no registro do agente de IA
# (autonomia_agent_tool_runs e autonomia_agent_events). Ficam as linhas, com códigos, contagens, custos e datas.
RSpec.describe Autonomia::Agents::RegistroDaConversaExcluida do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:outra) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:segredo) { 'Placa ABC1D23 de Maria Cliente, CPF 123.456.789-09' }
  let(:message_id) { 987_654 }

  # O handle como o motor o deixa: o que a ferramenta devolveu, a identidade do pedido e as marcas (o `submitted` é true).
  def criar_execucao(conversa, status:, slug: 'cotar_seguro', marcas: { Autonomia::Agents::ToolRun::SUBMITTED_KEY => true })
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agent, conversation_id: conversa.id, slug: slug, status: status,
      execution_key: SecureRandom.uuid, origin_message_id: message_id, arguments: { 'pedido' => segredo },
      handle: { 'cotacao' => segredo, 'numero_no_portal' => '998877', Autonomia::Agents::ToolRun::PEDIDO => 'digest-do-pedido',
                Autonomia::Agents::ToolRun::INTENCOES => 1 }.merge(marcas),
      attempts: 3, delivered_count: 2
    )
  end

  def criar_evento(conversa, **attrs)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conversa.id, message_id: message_id,
                                          event_type: :consulted, confidence: 0.8, handoff_reason: 'other',
                                          metadata: { 'principal_id' => 7, 'custo_usd' => 0.0012, 'rodadas' => 2,
                                                      'memoria_fact_ids' => [1, 2], 'texto' => segredo }, **attrs)
  end

  # O texto do cliente em qualquer coluna das duas tabelas, lido como o banco o guarda.
  def sobra_do_cliente?
    [Autonomia::Agents::ToolRun, Autonomia::Agents::AgentEvent].any? do |modelo|
      modelo.where(account_id: account.id).exists?(["#{modelo.table_name}::text LIKE ?", '%ABC1D23%'])
    end
  end

  it 'DELETE da conversa: as linhas ficam sem argumento, resultado, mensagem nem texto; a viva para' do
    viva = criar_execucao(conversation, status: 'running')
    encerrada = { Autonomia::Agents::ToolRun::SUBMITTED_KEY => true, Autonomia::Agents::ToolRun::ENCERRADA_EM => '2026-10-24T10:00:00.000Z',
                  Autonomia::Agents::Tools::Encerramento::CLOSED_KEY => true }
    feita = criar_execucao(conversation, status: 'done', slug: 'agendar_reuniao', marcas: encerrada)
    evento = criar_evento(conversation)

    freeze_time { conversation.destroy! }

    expect(sobra_do_cliente?).to be(false)
    expect(viva.reload).to have_attributes(status: 'blocked', failure_code: 'conversa_excluida', arguments: {},
                                           origin_message_id: nil, conversation_id: conversation.id, attempts: 3,
                                           delivered_count: 2)
    expect(viva.handle).to eq(Autonomia::Agents::ToolRun::INTENCOES => 1, Autonomia::Agents::ToolRun::SUBMITTED_KEY => true,
                              Autonomia::Agents::ToolRun::ENCERRADA_EM => viva.updated_at.iso8601(3))
    expect(feita.reload).to have_attributes(status: 'done', failure_code: nil, arguments: {})
    expect(feita.handle).to eq(encerrada.merge(Autonomia::Agents::ToolRun::INTENCOES => 1))
    expect(evento.reload).to have_attributes(message_id: nil, conversation_id: conversation.id, event_type: 'consulted',
                                             confidence: 0.8, handoff_reason: 'other')
    expect(evento.metadata).to eq('principal_id' => 7, 'custo_usd' => 0.0012, 'rodadas' => 2)
  end

  it 'o job que estava no meio da passada perde a posse e não grava o resultado de volta' do
    run = criar_execucao(conversation, status: 'running')
    no_job = Autonomia::Agents::ToolRun.find(run.id)

    conversation.destroy!

    expect(no_job.record_attempt!(handle: { 'cotacao' => segredo })).to be(false)
    expect(no_job.finish!('done')).to be(false)
    expect(sobra_do_cliente?).to be(false)
  end

  it 'a viva que decidiu submeter e não recebeu o número fica marcada como possivelmente duplicada, como no finish!' do
    incerta = criar_execucao(conversation, status: 'running', marcas: {})
    pendente = criar_execucao(conversation, status: 'pending', slug: 'agendar_reuniao', marcas: {})
    Autonomia::Agents::ToolRun.where(id: pendente.id).update_all(handle: {}) # rubocop:disable Rails/SkipsModelValidations

    conversation.destroy!

    expect(incerta.reload).to have_attributes(status: 'blocked', failure_code: 'conversa_excluida')
    expect(incerta.handle).to include(Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA => true, Autonomia::Agents::ToolRun::INTENCOES => 1)
    expect(incerta.handle).to have_key(Autonomia::Agents::ToolRun::ENCERRADA_EM)
    expect(Autonomia::Agents::ToolRun.possivelmente_duplicadas).to contain_exactly(incerta)
    expect(pendente.reload.status).to eq('blocked')
  end

  it 'uma segunda exclusão (ou a limpeza repetida) não regrava linha já limpa' do
    run = criar_execucao(conversation, status: 'done')
    evento = criar_evento(conversation)
    described_class.new(account_id: account.id, conversation_id: conversation.id).perform
    antes = [run.reload.updated_at, evento.reload.attributes]

    travel(1.minute) { described_class.new(account_id: account.id, conversation_id: conversation.id).perform }

    expect([run.reload.updated_at, evento.reload.attributes]).to eq(antes)
  end

  # Fica para a Issue de seguimento (#2175): um turno em andamento que abre uma execução depois da limpeza grava os argumentos
  # numa conversa que não existe mais. Este exemplo registra o limite de hoje.
  it 'limite conhecido: execução aberta depois do destroy não é limpa por este serviço' do
    conversation.destroy!

    tardia = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'cotar_seguro', arguments: { 'pedido' => segredo },
                                              scope: { conversation_id: conversation.id })

    expect(tardia.arguments).to eq('pedido' => segredo)
  end

  it 'o registro de outra conversa não é tocado' do
    run = criar_execucao(outra, status: 'running')
    evento = criar_evento(outra)

    conversation.destroy!

    expect(run.reload).to have_attributes(status: 'running', origin_message_id: message_id)
    expect(run.arguments).to eq('pedido' => segredo)
    expect(evento.reload.message_id).to eq(message_id)
  end

  it 'excluir o contato: as conversas saem num job, e o registro delas é limpo' do
    criar_execucao(conversation, status: 'done')
    criar_evento(conversation)

    perform_enqueued_jobs { contact.destroy! }

    expect(Conversation.exists?(conversation.id)).to be(false)
    expect(sobra_do_cliente?).to be(false)
  end

  it 'excluir a conta: as duas tabelas saem inteiras, sem a limpeza conversa a conversa' do
    criar_execucao(conversation, status: 'done')
    criar_evento(conversation)
    allow(described_class).to receive(:new).and_call_original

    DeleteObjectJob.perform_now(account)

    expect(described_class).not_to have_received(:new)
    expect(Autonomia::Agents::ToolRun.where(account_id: account.id)).to be_empty
    expect(Autonomia::Agents::AgentEvent.where(account_id: account.id)).to be_empty
  end
end
