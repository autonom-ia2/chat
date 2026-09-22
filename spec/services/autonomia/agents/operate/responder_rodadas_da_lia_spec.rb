require 'rails_helper'

# AS RODADAS DA LIA (chat#585, decisão do CEO em 22/09/2026: "até 6 rodadas entre o principal e o especialista").
# O principal rodava com UMA rodada de ferramenta: se o especialista respondesse "falta o CPF" e o CPF estivesse na
# conversa, a Lia não conseguia chamá-lo de novo no mesmo turno — embora o manual dela mande fazer exatamente isso
# (§4.2). Seis rodadas para o Agente de Cotação, e um orçamento de tempo que nunca corta uma rodada: cada uma pode
# esperar um especialista inteiro. Os demais agentes continuam com uma.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  def caixa_com_mensagem(agente)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi')
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  def rodadas_pedidas(agente)
    agent_inbox = caixa_com_mensagem(agente)
    recebido = nil
    allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
      recebido = kwargs.slice(:max_rodadas, :max_segundos)
      original.call(**kwargs)
    end
    allow_any_instance_of(Autonomia::Agents::Answerer).to receive(:answer).and_return(nil) # rubocop:disable RSpec/AnyInstance
    described_class.new(conversation: conversation, agent_inbox: agent_inbox,
                        reply_to_message_id: conversation.messages.incoming.last.id).perform
    recebido
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  it 'a Lia do Agente de Cotação tem seis rodadas, e o relógio não corta nenhuma' do
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'X').call

    pedido = rodadas_pedidas(lia)

    expect(pedido[:max_rodadas]).to eq(6)
    espera_de_um_especialista = Autonomia::Agents::Specialists::Runner::SEGUNDOS_DE_FERRAMENTA + 120
    expect(pedido[:max_segundos]).to be >= 6 * espera_de_um_especialista
  end

  it 'os outros agentes continuam com uma rodada e o orçamento padrão' do
    outro = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')

    expect(rodadas_pedidas(outro)).to eq(max_rodadas: 1, max_segundos: nil)
  end
end
