require 'rails_helper'

# #3211: o turno em andamento (AgentInbox#turno_em_andamento?) mede a janela do settle gravada na marca do debounce
# (EsperaDaFala.janela_do_settle) mais a folga de 2 min. Sem as opções e com a marca de 6 s, a mesma janela de antes
# (debounce + folga = 126 s); com a espera pela fala (P1) a janela é a gravada; com a fila (P2) soma o teto da fila.
RSpec.describe Autonomia::Agents::AgentInbox do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom') }
  let(:link) { described_class.new(account: account, inbox: inbox, agent: agent, agent_bot: AgentBot.create!(account: account, name: 'Espelho')) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:mensagem) { create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi') }

  before { freeze_time }

  def grava_marca!(stamp)
    conversation.update!(additional_attributes: { Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => stamp })
  end

  # A marca da mensagem, gravada `atras` (Duration) atrás; `espera_ms` nil = marca sem a chave (antes do #3211).
  def marca!(atras, espera_ms = nil)
    stamp = { 'pending_message_id' => mensagem.id, 'at' => atras.ago.to_f }
    grava_marca!(espera_ms.nil? ? stamp : stamp.merge('espera_ms' => espera_ms))
  end

  def em_andamento? = link.turno_em_andamento?(conversation, mensagem)

  it 'sem as opções, marca de 6 s: 126 s de janela, como antes', :aggregate_failures do
    marca!(126.seconds, 6000)
    expect(em_andamento?).to be(true)

    marca!(127.seconds, 6000)
    expect(em_andamento?).to be(false)
  end

  it 'marca sem espera_ms (gravada antes do #3211): o debounce do agente, como antes', :aggregate_failures do
    marca!(126.seconds)
    expect(em_andamento?).to be(true)

    marca!(127.seconds)
    expect(em_andamento?).to be(false)
  end

  it 'P1: a espera gravada na marca (25 s) entra na janela' do
    marca!(140.seconds, 25_000)

    expect(em_andamento?).to be(true)
  end

  it 'P2: com a fila do agente, soma o teto da fila', :aggregate_failures do
    marca!(200.seconds, 6000)
    expect(em_andamento?).to be(false)

    agent.update!(config: agent.config.to_h.merge('conversa_em_fila' => true))
    expect(em_andamento?).to be(true)

    marca!(277.seconds, 6000)
    expect(em_andamento?).to be(false)
  end

  it 'a marca aponta para outra mensagem: não está em andamento' do
    grava_marca!({ 'pending_message_id' => mensagem.id + 1, 'at' => Time.current.to_f })

    expect(em_andamento?).to be(false)
  end
end
