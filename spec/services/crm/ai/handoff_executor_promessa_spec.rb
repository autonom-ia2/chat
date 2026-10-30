require 'rails_helper'

# IA entende a conversa F1 (regra f do Rodrigo; D2 do plano): o nosso assistente prometeu ao cliente que uma pessoa vai
# assumir, ninguém assumiu e o problema não foi resolvido depois (o modelo lê e devolve `promised_by_our_assistant`).
# Com a flag, a IA do CRM cumpre a promessa mesmo com o agente dono da conversa (exceção ao #1673), menos com o agente
# protegido. As outras guardas continuam.
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

  it 'com a promessa, entrega a uma pessoa mesmo com o agente nosso no nome e deixa a linha', :aggregate_failures do
    allow(Rails.logger).to receive(:info).and_call_original

    expect(entregar(prometida)).to have_attributes(status: :handed_off, assignee: pessoa)
    expect(conversation.reload.assignee_id).to eq(pessoa.id)
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=promessa_do_robo'))
  end

  it 'sem a promessa, o agente nosso segue com a conversa (#1673)' do
    expect(entregar(sem_promessa)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
  end

  it 'o agente protegido segue com a conversa mesmo com a promessa' do
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:instrucao_mantida?).and_return(true) # rubocop:disable RSpec/AnyInstance

    expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'alguém já assumiu: corta como sempre' do
    conversation.update!(assignee: pessoa)

    expect(entregar(prometida).error).to eq('already_assigned')
  end

  it 'a promessa é fato à parte da intenção: com o agente nosso dono, cumpre mesmo com "continuar"' do
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
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:instrucao_mantida?).and_return(true) # rubocop:disable RSpec/AnyInstance

    expect(entregar(prometida.merge(intent: 'continuar', should_handoff: false))).to have_attributes(status: :skipped, error: 'not_requested')
  end

  it 'ninguém online: a espera fica com o motivo do pedido do robô, e a fila não a devolve ao agente', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

    expect(entregar(prometida).status).not_to eq(:handed_off)
    marca = Crm::Entrega::Marca.dados(conversation.reload)
    expect(marca).to include('modo' => Crm::Entrega::Marca::SEGURANDO, 'motivo' => described_class::MOTIVO_DA_PROMESSA)
    expect(Crm::Ai::HandoffDrainJob.new.send(:da_ia_do_crm_com_agente_nosso?, conversation, marca)).to be(false)
  end

  it 'sem a flag, a promessa não muda nada (como antes)' do
    account.disable_features!(Crm::Ai::FatosDaConversa::FLAG)

    expect(entregar(prometida)).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
  end
end
