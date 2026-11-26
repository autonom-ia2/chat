require 'rails_helper'

# IA entende a conversa F1 (regra f do Rodrigo; D2 do plano): o nosso assistente prometeu ao cliente que uma pessoa vai
# assumir, ninguém assumiu e o problema não foi resolvido depois (o modelo lê e devolve `promised_by_our_assistant`).
# Com a flag, a IA do CRM cumpre a promessa mesmo com o agente dono da conversa (exceção ao #1673), menos com o agente
# protegido. As outras guardas continuam. #3256: a promessa só vale com o aviso que o agente gravou (o evento
# `avisou_que_chama_alguem`) depois da última vez que a conversa voltou para a IA.
RSpec.describe Crm::Ai::HandoffExecutor do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }
  let(:prometida) { { intent: 'transferir', should_handoff: true, reason: 'o assistente prometeu uma pessoa', promised_by_our_assistant: true } }
  let(:sem_promessa) { prometida.merge(promised_by_our_assistant: false) }
  let(:card) do
    card = create_card(pipeline: comercial)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card.reload
  end

  before do
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
    account.enable_features!(Crm::Ai::FatosDaConversa::FLAG)
  end

  def entregar(handoff) = described_class.new(card: card, handoff: handoff, trigger: Crm::Ai::FatosDaConversa::TRIGGER_DO_ROBO).perform

  # O registro do turno que o agente grava quando avisa o cliente que vai chamar alguém (AgenteSoInforma.fala_comecou!).
  def avisar!(agente: agente_da_porta, quando: Time.current)
    Autonomia::Agents::AgentEvent.create!(agent: agente, account: account, conversation_id: conversation.id,
                                          event_type: :avisou_que_chama_alguem, created_at: quando)
  end

  # Uma pessoa recebeu a conversa e a devolveu (Crm::Passagens): o marco da DevolucaoAIa.
  def passou_e_voltou!(passou_em:, voltou_em:)
    Crm::Passagem.create!(account_id: account.id, conversation_id: conversation.id, para_type: 'User', para_id: pessoa.id,
                          motivo: described_class::MOTIVO_DA_PROMESSA, em: passou_em, devolvida_em: voltou_em)
  end

  it 'com a promessa, entrega a uma pessoa mesmo com o agente nosso no nome e deixa a linha', :aggregate_failures do
    allow(Rails.logger).to receive(:info).and_call_original
    avisar!

    expect(entregar(prometida)).to have_attributes(status: :handed_off, assignee: pessoa)
    expect(conversation.reload.assignee_id).to eq(pessoa.id)
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=promessa_do_robo'))
  end

  it 'sem a promessa, o agente nosso segue com a conversa (#1673)' do
    expect(entregar(sem_promessa)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
  end

  it 'o agente protegido segue com a conversa mesmo com a promessa' do
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:protegido_no_crm?).and_return(true) # rubocop:disable RSpec/AnyInstance

    expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'alguém já assumiu: corta como sempre' do
    conversation.update!(assignee: pessoa)

    expect(entregar(prometida).error).to eq('already_assigned')
  end

  it 'a promessa é fato à parte da intenção: com o agente nosso dono, cumpre mesmo com "continuar"' do
    avisar!

    expect(entregar(prometida.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :handed_off, assignee: pessoa)
  end

  it 'problema resolvido depois da promessa (o modelo devolve false) não passa' do
    expect(entregar(sem_promessa.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :skipped, error: 'not_requested')
  end

  it 'sem agente nosso dono da conversa, a promessa não vira pedido (só a intenção de sempre)' do
    allow(Autonomia::Agents::QuemResponde).to receive(:dono_ativo).and_return(nil)

    expect(entregar(prometida.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :skipped, error: 'not_requested')
  end

  it 'o agente protegido: a promessa sozinha não vira pedido' do
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:protegido_no_crm?).and_return(true) # rubocop:disable RSpec/AnyInstance

    expect(entregar(prometida.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :skipped, error: 'not_requested')
  end

  it 'ninguém online: a espera fica com o motivo do pedido do robô, e a fila não a devolve ao agente', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
    avisar!

    expect(entregar(prometida).status).not_to eq(:handed_off)
    marca = Crm::Entrega::Marca.dados(conversation.reload)
    expect(marca).to include('modo' => Crm::Entrega::Marca::SEGURANDO, 'motivo' => described_class::MOTIVO_DA_PROMESSA)
    expect(Crm::Ai::HandoffDrainJob.new.send(:da_ia_do_crm_com_agente_nosso?, conversation, marca)).to be(false)
  end

  it 'sem a flag, a promessa não muda nada (como antes)' do
    account.disable_features!(Crm::Ai::FatosDaConversa::FLAG)

    expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
  end

  describe 'o aviso do agente (#3256)' do
    it 'sem o aviso, a promessa do modelo não passa: o agente segue dono e fica a linha', :aggregate_failures do
      allow(Rails.logger).to receive(:info).and_call_original

      expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=promessa_sem_aviso'))
      expect(Rails.logger).not_to have_received(:info).with(a_string_including('desfecho=promessa_do_robo'))
    end

    it 'sem o aviso e com "continuar", a promessa sozinha não vira pedido' do
      expect(entregar(prometida.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :skipped, error: 'not_requested')
    end

    it 'o aviso de outro agente não é a promessa do dono' do
      avisar!(agente: area)

      expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
    end

    it 'o aviso de antes da devolução já foi cumprido: não passa de novo', :aggregate_failures do
      allow(Rails.logger).to receive(:info).and_call_original
      avisar!(quando: 30.minutes.ago)
      passou_e_voltou!(passou_em: 20.minutes.ago, voltou_em: 10.minutes.ago)

      expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
      expect(conversation.reload.assignee_id).to be_nil
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=promessa_sem_aviso', 'motivo=depois_da_devolucao'))
    end

    it 'o aviso de depois da devolução é promessa nova: passa', :aggregate_failures do
      passou_e_voltou!(passou_em: 20.minutes.ago, voltou_em: 10.minutes.ago)
      fala = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                              content: 'Vou chamar uma pessoa da equipe para te atender', sender: porta)
      avisar!(quando: fala.created_at)

      expect(entregar(prometida)).to have_attributes(status: :handed_off, assignee: pessoa)
      expect(conversation.reload.assignee_id).to eq(pessoa.id)
    end
  end
end
