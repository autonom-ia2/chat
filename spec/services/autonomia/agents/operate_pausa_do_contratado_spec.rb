require 'rails_helper'

# #3270 — a pausa do contratado no contrato do turno (`Operate.authorized_agent_inbox`), o ponto por onde passam a
# mensagem, o evento da cotação, a passagem e a entrega em segundo plano. `vinculo_que_atenderia` é o mesmo contrato
# sem a pausa, para a nota saber que o agente pausado é quem responderia. E a nota da pausa (`Contratados::AvisoDaPausa`).
RSpec.describe Autonomia::Agents::Operate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:comeco) { Time.current.beginning_of_minute }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end

  before { allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true) }

  def ligar(agente)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  def contratado
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', status: :active, enabled: true,
                                              instruction: 'retrato', config: { 'contratado' => marca })
    agente.update_columns(created_at: comeco) # rubocop:disable Rails/SkipsModelValidations
    agente
  end

  describe '.authorized_agent_inbox e .eligible_agent_inbox' do
    it 'no grátis, o contratado atende' do
      vinculo = ligar(contratado)

      travel_to(comeco + 6.days) do
        expect(described_class.authorized_agent_inbox(conversation)).to eq(vinculo)
        expect(described_class.eligible_agent_inbox(conversation)).to eq(vinculo)
      end
    end

    it 'pausado, ninguém atende; o vínculo que atenderia continua sendo o dele' do
      vinculo = ligar(contratado)

      travel_to(comeco + 7.days) do
        expect(described_class.authorized_agent_inbox(conversation)).to be_nil
        expect(described_class.eligible_agent_inbox(conversation)).to be_nil
        expect(described_class.no_comando?(conversation, vinculo)).to be(false)
        expect(described_class.vinculo_que_atenderia(conversation)).to eq(vinculo)
      end
    end

    it 'liberado, atende depois dos 7 dias' do
      vinculo = ligar(contratado)
      Autonomia::Agents::Contratados::Liberacao.atribuir(account, ['seguro_viagem_universal'])
      account.save!

      travel_to(comeco + 30.days) do
        expect(described_class.authorized_agent_inbox(conversation)).to eq(vinculo)
      end
    end

    it 'o agente comum não tem pausa' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true)
      vinculo = ligar(comum)

      travel_to(comeco + 30.days) do
        expect(described_class.authorized_agent_inbox(conversation)).to eq(vinculo)
      end
    end
  end

  describe Autonomia::Agents::Contratados::AvisoDaPausa do
    let(:chave) { described_class::CHAVE }

    def notas = conversation.messages.reload.where(private: true).select { |m| m.content_attributes.to_h[chave] }

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'pausado: uma nota privada, uma vez por conversa' do
      ligar(contratado)

      travel_to(comeco + 8.days) do
        2.times { described_class.postar(conversation) }
      end

      expect(notas.size).to eq(1)
      expect(notas.sole.content).to eq(I18n.t('autonomia.contratados.pausado.nota'))
      expect(conversation.messages.where(private: false, message_type: :outgoing)).to be_empty
    end

    it 'no grátis, nenhuma nota' do
      ligar(contratado)

      travel_to(comeco + 2.days) { described_class.postar(conversation) }

      expect(notas).to be_empty
    end

    it 'agente parado (desligado) não é pausa: nenhuma nota' do
      agente = contratado
      ligar(agente)
      agente.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations

      travel_to(comeco + 8.days) { described_class.postar(conversation) }

      expect(notas).to be_empty
    end

    it 'sem agente na caixa: nada' do
      expect(described_class.postar(conversation)).to be(false)
      expect(notas).to be_empty
    end

    it 'com o espelho no comando, passa para a equipe uma vez, com o motivo contratado_pausado' do
      agente = contratado
      ligar(agente)
      conversation.update!(ai_assignee: agent_bot)

      travel_to(comeco + 8.days) { 2.times { described_class.postar(conversation.reload) } }

      expect(conversation.reload.awaiting_person?).to be(true)
      expect(agente.events.where(event_type: :handed_off).pluck(:handoff_reason)).to eq(['contratado_pausado'])
      expect(notas.size).to eq(1)
    end
  end

  # A Atribuição (ou uma pessoa) passou a conversa ao agente pausado: nenhum turno abre para ele, então a passagem para a
  # equipe sai na troca de dono, com o cliente ativo; cliente parado espera a próxima mensagem dele (ReplyJob).
  describe 'Autonomia::Agents::Operate::ReenfileirarTurno.ao_trocar_dono' do
    let(:agente) { contratado }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      allow(Autonomia::Agents::Fase2).to receive(:ligada?).and_return(true)
      ligar(agente)
      conversation.update!(ai_assignee: agent_bot)
    end

    def notas = conversation.messages.reload.where(private: true).select { |m| m.content_attributes.to_h['autonomia_contratado_pausado'] }

    it 'cliente ativo: passa para a equipe e deixa a nota' do
      travel_to(comeco + 8.days) do
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'resposta antiga')
        create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi', created_at: 2.hours.ago)
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'da equipe')

        expect(Autonomia::Agents::Operate::ReenfileirarTurno.ao_trocar_dono(conversation: conversation.reload, por: :crm)).to be(true)
      end

      expect(conversation.reload.awaiting_person?).to be(true)
      expect(notas.size).to eq(1)
    end

    it 'cliente parado há mais de um dia: nada agora' do
      travel_to(comeco + 8.days) do
        create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi', created_at: 3.days.ago)
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'da equipe')

        Autonomia::Agents::Operate::ReenfileirarTurno.ao_trocar_dono(conversation: conversation.reload, por: :crm)
      end

      expect(conversation.reload.awaiting_person?).to be(false)
      expect(notas).to be_empty
    end
  end
end
