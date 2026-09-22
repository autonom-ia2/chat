require 'rails_helper'

# O TETO DO `AsyncPublishJob`: a cadeia do turno deixa de ser esperada em `MAX_PUBLISH_DEFERRALS`, e o job
# reenfileira a forma que o publicador devolveu em `adiada`. SÓ ARQUIVO desde a PR C: o texto encadeado (o fecho
# que esperava o PDF) e o texto solto que um job da versão anterior carregue são descartados, e nada chega ao
# cliente por eles.
RSpec.describe Autonomia::Agents::Tools::AsyncPublishJob, type: :job do
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
                                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                              origin_message_id: 77 })
                              .tap { |r| r.promote!(expected_chunks: 2, notify_customer: false, expires_at: 3.minutes.from_now) }
  end
  let(:config) { Autonomia::Agents::Tools::AsyncConfig }
  # O fecho encadeado que a versão anterior enfileirava para esperar o PDF.
  let(:encadeado_antigo) do
    { 'encadeada' => { 'texto' => 'Encerrei a busca.', 'depois_de' => [run.delivery_token('arquivo:https://x.test/c.pdf')] } }
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before { stub_arquivo }

  def bot_messages = conversation.messages.reload.where(sender_type: 'AgentBot')

  def reenfileirados
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == described_class.name }
                   .map { |job| ActiveJob::Arguments.deserialize(job['arguments']) }
  end

  it 'com a cadeia aberta abaixo do teto, reenfileira o arquivo ja gravado com mais um adiamento' do
    described_class.new.perform(run.id, arquivo_de_teste, 0)

    expect(bot_messages).to be_empty
    expect(reenfileirados.sole.first).to eq(run.id)
    expect(reenfileirados.sole.second).to include('arquivo_gravado')
    expect(reenfileirados.sole.last).to eq(1)
  end

  it 'no teto da cadeia, publica o arquivo, sem texto' do
    described_class.new.perform(run.id, arquivo_de_teste, config::MAX_PUBLISH_DEFERRALS)

    expect(bot_messages.sole.content).to be_blank
    expect(bot_messages.sole.attachments.size).to eq(1)
    expect(reenfileirados).to be_empty
  end

  # A EXECUÇÃO QUE ATRAVESSOU O DEPLOY: o job adiado pela versão anterior traz o fecho encadeado, ou um texto
  # solto. Nenhum dos dois sai, e nenhum é reenfileirado.
  it 'descarta o fecho encadeado e o texto que um job da versao anterior carrega' do
    described_class.new.perform(run.id, encadeado_antigo, config::MAX_DEPENDENCY_DEFERRALS)
    described_class.new.perform(run.id, 'encontrei 3 opções', config::MAX_PUBLISH_DEFERRALS)

    expect(bot_messages).to be_empty
    expect(reenfileirados).to be_empty
  end
end
