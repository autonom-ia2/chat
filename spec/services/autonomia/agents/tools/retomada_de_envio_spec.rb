require 'rails_helper'

# A RETOMADA DO ENVIO PENDENTE PELO VARREDOR (rodada 9 da entrega 11). O `reap_stale_runs_job_spec`
# prova o desfecho pelo job inteiro; o que fica AQUI é o que o desfecho não mostra — a ORDEM: a
# conversa é travada ANTES de o `SendReplyJob` entrar na fila, e a mensagem é RELIDA sob o lock (um
# objeto velho, com a marca, não reenvia o que o banco já não tem). Sem estas duas guardas, a retomada
# "sob o lock" seria só uma frase no comentário.
RSpec.describe Autonomia::Agents::Tools::RetomadaDeEnvio do
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
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
                              .tap { |r| r.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) }
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  # -> a mensagem marcada pela primeira tentativa do publicador (fila recusando o envio), com a fila já
  # de volta — LIDA DO BANCO, como o varredor a lê (`marcadas`): a instância do `let` carrega o
  # `display_id` que o banco atribui, e `lock!` recusa registro com mudança não persistida.
  def mensagem_pendente
    fila_recusa_o_envio
    expect(Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish('cotação pronta')).to be_blocked
    fila_volta
    Message.find(conversation.messages.where(sender_type: 'AgentBot').sole.id).tap do |mensagem|
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio).to be_pendente(mensagem)
    end
  end

  it 'trava a conversa antes de por o reenvio na fila' do
    # Arrange
    mensagem = mensagem_pendente
    eventos = []
    sql = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      eventos << :trava if payload[:sql].to_s.include?('FOR UPDATE')
    end
    fila = ActiveSupport::Notifications.subscribe('enqueue.active_job') do |*, payload|
      eventos << :fila if payload[:job].is_a?(SendReplyJob)
    end

    # Act
    described_class.new(run: run).recuperar(mensagem)

    # Assert — o lock, e só então o job
    expect(eventos).to eq(%i[trava fila])
    expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
  ensure
    ActiveSupport::Notifications.unsubscribe(sql) if sql
    ActiveSupport::Notifications.unsubscribe(fila) if fila
  end

  it 'rele a mensagem sob o lock: o objeto velho com a marca nao reenvia o que o banco ja nao tem' do
    # Arrange — o varredor leu a mensagem marcada; antes de ele travar, outro processo resolveu a pendência
    mensagem = mensagem_pendente
    velha = Message.find(mensagem.id)
    Autonomia::Agents::Tools::PendenciaDeEnvio.limpar(mensagem, contexto: 'outro processo')

    # Act
    resolvido = described_class.new(run: run).recuperar(velha)

    # Assert
    expect(resolvido).to be(true)
    expect(SendReplyJob).not_to have_been_enqueued
  end
end
