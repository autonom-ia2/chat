require 'rails_helper'

# #2154 (flag `agente_so_informa`): o turno do agente começa na mensagem do cliente (ReplyJob#trigger), para a IA de
# Atribuição não entregar a conversa enquanto ele responde. Quem não chega ao Responder solta a marca no settle.
RSpec.describe Autonomia::Agents::Operate::ReplyJob do
  include_context 'with crm responsible agent'

  let(:turno) { Autonomia::Agents::Operate::TurnoEmCurso }
  let(:mensagem) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    Redis::Alfred.delete(turno.chave(conversation.id))
  end

  it 'a mensagem do cliente abre o turno, com o id dela', :aggregate_failures do
    described_class.perform_now(conversation.id, mensagem.id, 'trigger')

    expect(Redis::Alfred.get(turno.chave(conversation.id))).to eq(mensagem.id.to_s)
    expect(Redis::Alfred.ttl(turno.chave(conversation.id))).to be > 0
  end

  it 'sem a flag, não abre' do
    account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)

    described_class.perform_now(conversation.id, mensagem.id, 'trigger')

    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'uma pessoa assumiu na janela do debounce: o settle solta a marca do turno' do
    described_class.perform_now(conversation.id, mensagem.id, 'trigger')
    conversation.update!(assignee: admin)

    described_class.perform_now(conversation.id, mensagem.id, 'settle')

    expect(turno.em_curso?(conversation.id)).to be(false)
  end
end
