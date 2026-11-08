require 'rails_helper'

# #1430: o turno do agente acionado pelo resultado de uma ferramenta HTTP assíncrona. Os três casos do desenho: pessoa
# atendendo (nota privada com o resultado), cliente escrevendo no meio (espera o turno dele), e a falha (o agente diz
# que não conseguiu).
RSpec.describe Autonomia::Agents::Operate::EventoJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido',
                                    timeout_seconds: 60, endpoint_url: 'https://erp.exemplo.test/pedidos', param_schema: [])
  end
  let(:turno_em_curso) { Autonomia::Agents::Operate::TurnoEmCurso }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { lia_responde('Seu pedido 42 já foi enviado.') }

  after { Redis::Alfred.delete(turno_em_curso.chave(conversation.id)) }

  def consulta(resultado)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: tool.slug, arguments: {},
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                                    autonomia_agent_tool_id: tool.id, faixa: 'consulta_http' })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.merge_handle!({ Autonomia::Agents::ToolRun::CHAVE_DA_CONSULTA => 'chave' }) # a abertura de verdade grava a chave
    run.gravar_resultado!(resultado, sucesso: true, codigo: nil, api_ms: 1)
    run
  end

  def mensagens = conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)

  it 'o resultado chega: o agente fala com a nota do sistema e o resultado' do
    run = consulta('{"status":"enviado"}')

    described_class.new.perform(run.id, 'consulta_concluida')

    expect(mensagens.where(private: false).sole.content).to eq('Seu pedido 42 já foi enviado.')
    expect(queries_da_lia.sole).to include('{"status":"enviado"}')
    expect(queries_da_lia.sole.downcase).not_to include('cotação')
  end

  it '(a) pessoa atendendo: o agente nao fala, e a nota privada leva o resultado da consulta' do
    run = consulta('{"status":"enviado"}')
    conversation.update!(assignee: create(:user, account: account, role: :agent))

    described_class.new.perform(run.id, 'consulta_concluida')

    nota = mensagens.sole
    expect(nota.private).to be(true)
    expect(nota.content).to include('{"status":"enviado"}')
    expect(nota.content.downcase).not_to include('cotação')
    expect(queries_da_lia).to be_empty
  end

  it '(b) turno do cliente em curso: espera ele terminar antes de falar' do
    run = consulta('{"status":"enviado"}')
    turno_em_curso.abrir(conversation.id, 99)

    described_class.new.perform(run.id, 'consulta_concluida')

    expect(mensagens).to be_empty
    expect(described_class).to have_been_enqueued.with(run.id, 'consulta_concluida', 1, 0, [])

    turno_em_curso.soltar(conversation.id, 99)
    described_class.new.perform(run.id, 'consulta_concluida', 1)

    expect(mensagens.where(private: false).sole.content).to eq('Seu pedido 42 já foi enviado.')
  end

  it '(c) erro ou tempo esgotado: o agente recebe a falha para dizer que nao conseguiu' do
    run = consulta(Autonomia::Agents::Tools::Recusa.saida('tool_execution_error'))

    described_class.new.perform(run.id, 'consulta_falhou')

    expect(queries_da_lia.sole).to include(Autonomia::Agents::Tools::Evento::DESCRICOES.fetch('consulta_falhou'),
                                           'tool_execution_error')
    expect(mensagens.where(private: false).count).to eq(1)
  end

  # B1: sem `agente_so_informa`, a marca do turno nascia desligada e o resultado podia sair antes do "estou consultando".
  it 'B1: o evento que chega antes da fala do turno que desistiu espera ele postar, mesmo sem agente_so_informa' do
    ligar_consulta_em_segundo_plano
    expect(Autonomia::Agents::AgenteSoInforma.ligada?(account)).to be(false)
    run = consulta('{"status":"enviado"}')
    reply_job = Autonomia::Agents::Operate::ReplyJob.new
    reply_job.send(:abrir_turno, conversation, 77) # a mensagem do cliente que abriu o turno da consulta

    described_class.new.perform(run.id, 'consulta_concluida')

    expect(mensagens).to be_empty
    expect(described_class).to have_been_enqueued.with(run.id, 'consulta_concluida', 1, 0, [])

    reply_job.send(:fim_do_turno, conversation, 77, nil) # o turno postou o "estou consultando" e terminou
    described_class.new.perform(run.id, 'consulta_concluida', 1)

    expect(mensagens.where(private: false).sole.content).to eq('Seu pedido 42 já foi enviado.')
  end
end
