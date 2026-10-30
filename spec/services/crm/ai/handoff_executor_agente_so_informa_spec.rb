require 'rails_helper'

# #2154 (regra do Rodrigo, 24/10): nenhum agente nosso passa a conversa; quem decide é a IA de Atribuição. Com a flag
# `agente_so_informa`, a avaliação que roda DEPOIS da fala do agente (gatilho `fala_do_agente`) não esbarra no bloqueio
# `owned_by_our_agent` do #1673 e entrega pelo Crm::Entrega de sempre. Os outros gatilhos e a conta sem a flag seguem
# como hoje.
RSpec.describe Crm::Ai::HandoffExecutor do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }
  let(:pedido) { { intent: 'transferir', should_handoff: true, reason: 'cliente pediu uma pessoa' } }
  let(:depois_da_fala) { Crm::Ai::AvaliacaoDepoisDaFala::TRIGGER }
  let(:card) do
    card = create_card(pipeline: comercial)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card.reload
  end

  before do
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
    Redis::Alfred.delete(Autonomia::Agents::Operate::TurnoEmCurso.chave(conversation.id))
  end

  def entregar(trigger:, handoff: pedido) = described_class.new(card: card, handoff: handoff, trigger: trigger).perform

  context 'with a flag ligada' do
    before { account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG) }

    it 'depois da fala do agente, entrega a uma pessoa mesmo com o agente nosso no nome', :aggregate_failures do
      allow(Rails.logger).to receive(:info).and_call_original

      expect(entregar(trigger: depois_da_fala)).to have_attributes(status: :handed_off, assignee: pessoa)
      expect(conversation.reload).to have_attributes(assignee_id: pessoa.id, ai_assignee: nil)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=depois_da_fala_do_agente'))
    end

    it 'a entrega vai com o motivo do pedido do robô que avisou, pela regra de sempre' do
      allow(Crm::Entrega).to receive(:new).and_call_original

      entregar(trigger: depois_da_fala)

      expect(Crm::Entrega).to have_received(:new)
        .with(hash_including(motivo: Crm::Ai::HandoffExecutor::MOTIVO_DA_PROMESSA, origem: depois_da_fala, card: card))
    end

    it 'ninguém online: segura com o motivo do robô, e a fila não larga a espera de volta ao agente', :aggregate_failures do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
      card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'prefer_online' => true } })

      expect(entregar(trigger: depois_da_fala).status).to eq(:held_online)
      expect(Crm::Entrega::Marca.dados(conversation.reload)['motivo']).to eq(Crm::Ai::HandoffExecutor::MOTIVO_DA_PROMESSA)
      expect(Crm::Ai::HandoffDrainJob.new.send(:da_ia_do_crm_com_agente_nosso?, conversation, Crm::Entrega::Marca.dados(conversation)))
        .to be(false)
    end

    it 'a fila entrega quando alguém fica online, e a nota "Antes de encaminhar" sai com as recusas guardadas', :aggregate_failures do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
      card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'prefer_online' => true } })
      Autonomia::Agents::Tools::RecusasRecentes.anotar(conversation.id, 'especialista_falhou')
      Autonomia::Agents::Tools::RecusasRecentes.guardar_ate_a_passagem(conversation.id)
      entregar(trigger: depois_da_fala)

      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
      Crm::Ai::HandoffDrainJob.new.send(:drain_conversation, conversation.reload)

      expect(conversation.reload.assignee_id).to eq(pessoa.id)
      nota = conversation.messages.where(private: true).last
      expect(nota.content_attributes[Autonomia::Agents::NotaDoEncaminhamento::CHAVE]).to be(true)
      expect(nota.content).to include(Autonomia::Agents::Tools::Recusa::MOTIVOS.fetch('especialista_falhou'))
    end

    # Corrida com o turno seguinte: o modelo levou 20 s, o cliente escreveu e o agente está "digitando" em pedaços.
    it 'com o turno seguinte em curso, não entrega no meio dele: volta depois', :aggregate_failures do
      Autonomia::Agents::Operate::TurnoEmCurso.abrir(conversation.id, 77)

      expect { expect(entregar(trigger: depois_da_fala)).to have_attributes(status: :skipped, error: 'fala_em_curso') }
        .to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(card.id, nil, depois_da_fala, 1)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)

      Autonomia::Agents::Operate::TurnoEmCurso.soltar(conversation.id, 77)
      expect(entregar(trigger: depois_da_fala)).to have_attributes(status: :handed_off, assignee: pessoa)
    end

    it 'a IA de Atribuição decide: sem pedido ("continuar"), o agente segue com a conversa' do
      expect(entregar(trigger: depois_da_fala, handoff: pedido.merge(intent: 'continuar', should_handoff: false)))
        .to have_attributes(status: :skipped, error: 'not_requested')
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
    end

    it 'a mensagem do cliente (antes da fala do agente) segue sem passar: a ordem é fala primeiro, avaliação depois' do
      expect(entregar(trigger: 'message')).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'as outras guardas continuam: alguém já assumiu' do
      conversation.update!(assignee: pessoa)

      expect(entregar(trigger: depois_da_fala).error).to eq('already_assigned')
    end

    it 'a regra desligada no funil continua cortando' do
      card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => false } })

      expect(entregar(trigger: depois_da_fala).error).to eq('disabled')
    end
  end

  it 'sem a flag, nada muda: o gatilho da fala do agente também esbarra no agente nosso' do
    expect(entregar(trigger: depois_da_fala)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
  end
end
