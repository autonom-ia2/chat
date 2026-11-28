require 'rails_helper'

# #3270 — o agente contratado PAUSADO (os 7 dias grátis acabaram e a conta não tem a liberação) não responde: o turno do
# ReplyJob não roda (nenhuma chamada ao modelo), a conversa passa para a equipe pelo caminho do robô que passa
# (`bot_handoff!`, motivo `contratado_pausado`, à espera de pessoa e com o aviso de passagem), a equipe recebe a nota da
# pausa uma vez por conversa, e nada é apagado nem desligado. Ligada a liberação, ele responde na mensagem seguinte.
#
# Como em produção: o vínculo nasce antes da conversa, e o espelho dele é o `ai_assignee` (a resposta do robô reivindica
# a conversa, #1377).
RSpec.describe Autonomia::Agents::Operate::ReplyJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  # O começo do grátis é agora (o vínculo com a caixa nasce junto); os exemplos andam para a frente a partir dele.
  let(:comeco) { Time.current.beginning_of_minute }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end
  let(:agent) do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', status: :active, enabled: true,
                                              instruction: 'retrato', config: { 'contratado' => marca, 'with_knowledge' => false })
    agente.update_columns(created_at: comeco) # rubocop:disable Rails/SkipsModelValidations
    agente
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:nota_da_pausa) { Autonomia::Agents::Contratados::AvisoDaPausa::CHAVE }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'false', AI_HUMANIZE_DELIVERY: 'false') { example.run }
  end

  before do
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    answer = Autonomia::Agents::AnswerResult.new(reply: 'Claro, te ajudo.', confidence: 0.9, handoff: { should: false, reason: nil },
                                                 used_knowledge: [], answered_from_knowledge: false)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
    agent_inbox
    conversation.update!(ai_assignee: agent_bot)
  end

  def cliente_escreve(texto = 'oi')
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
  end

  # O turno inteiro de uma mensagem: o gatilho e o settle (sem esperar a janela).
  def turno!(mensagem = cliente_escreve)
    described_class.perform_now(conversation.id, mensagem.id, 'trigger')
    described_class.perform_now(conversation.id, mensagem.id, 'settle')
  end

  def respostas = conversation.messages.reload.where(message_type: :outgoing, private: false, sender_type: 'AgentBot')
  def notas_da_pausa = conversation.messages.reload.where(private: true).select { |m| m.content_attributes.to_h[nota_da_pausa] }
  def passagens = agent.events.where(event_type: :handed_off)
  def aviso_de_passagem = have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)

  def liberar!
    Autonomia::Agents::Contratados::Liberacao.atribuir(account, ['seguro_viagem_universal'])
    account.save!
  end

  it 'no período grátis, responde como sempre' do
    travel_to(comeco + 3.days)

    turno!

    expect(Autonomia::Agents::Answerer).to have_received(:new)
    expect(respostas.count).to eq(1)
    expect(notas_da_pausa).to be_empty
  end

  describe 'depois dos 7 dias, sem a liberação' do
    before { travel_to(comeco + 8.days) }

    it 'o turno não roda: nenhuma chamada ao modelo e nada ao cliente' do
      turno!

      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(respostas).to be_empty
    end

    it 'a conversa passa para a equipe: à espera de pessoa, evento contratado_pausado e o aviso de passagem' do
      expect(conversation.reload.awaiting_person?).to be(false)

      turno!

      expect(conversation.reload.awaiting_person?).to be(true)
      expect(conversation.bot_handoff_waiting?).to be(true)
      expect(passagens.pluck(:handoff_reason)).to eq(['contratado_pausado'])
      expect(Rails.configuration.dispatcher).to aviso_de_passagem
    end

    it 'a equipe recebe a nota da pausa, privada, com o texto do catálogo' do
      account.update!(locale: 'pt_BR')

      turno!

      nota = notas_da_pausa.sole
      expect(nota).to have_attributes(private: true, message_type: 'outgoing', sender_type: 'AgentBot', sender_id: agent_bot.id)
      expect(nota.content).to eq(I18n.t('autonomia.contratados.pausado.nota', locale: :pt_BR))
      expect(nota.content).not_to include('Bia', 'Corretora Exemplo')
    end

    it 'a nota e a passagem saem uma vez por conversa, por mais mensagens que o cliente mande' do
      3.times { |vez| turno!(cliente_escreve("mensagem #{vez}")) }

      expect(notas_da_pausa.size).to eq(1)
      expect(passagens.count).to eq(1)
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    end

    it 'no turno da passagem (sem mensagem nova do cliente), o mesmo: passa, nota, e nenhuma chamada ao modelo' do
      described_class.perform_now(conversation.id, 987_654, Autonomia::Agents::Operate::AoReceberPassagem::FASE)

      expect(conversation.reload.awaiting_person?).to be(true)
      expect(passagens.pluck(:handoff_reason)).to eq(['contratado_pausado'])
      expect(notas_da_pausa.size).to eq(1)
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    end

    it 'nada é apagado nem desligado no agente' do
      turno!

      expect(agent.reload).to have_attributes(enabled: true, status: 'active', deleted_at: nil)
      expect(agent_inbox.reload.deleted_at).to be_nil
      expect(agent.config['contratado']).to eq(marca)
    end

    it 'com uma pessoa na conversa, nem nota nem passagem: a conversa já é dela' do
      conversation.update!(assignee: create(:user, account: account, role: :agent))

      turno!

      expect(notas_da_pausa).to be_empty
      expect(passagens).to be_empty
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    end

    it 'ligada a liberação, responde na mensagem seguinte, sem nada a refazer' do
      turno!
      expect(respostas).to be_empty
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)

      liberar!
      turno!(cliente_escreve('ainda está aí?'))

      expect(Autonomia::Agents::Answerer).to have_received(:new)
      expect(respostas.count).to eq(1)
      expect(notas_da_pausa.size).to eq(1)
    end
  end

  it 'conta liberada: depois dos 7 dias continua respondendo, sem nota' do
    liberar!
    travel_to(comeco + 30.days)

    turno!

    expect(Autonomia::Agents::Answerer).to have_received(:new)
    expect(respostas.count).to eq(1)
    expect(notas_da_pausa).to be_empty
    expect(passagens).to be_empty
  end
end
