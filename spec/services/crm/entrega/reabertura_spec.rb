require 'rails_helper'

# Reabertura com o dono ausente (#1140, decisão 5): o cliente volta a uma conversa resolvida no nome da Ana. Entra pela
# mensagem do cliente (Message#reopen_conversation), como em produção. A regra é a do outro canal (Crm::Entrega::Dono):
# dono online fica; offline, vale a regra de Atribuição do funil (inclusive o agente de IA); sem regra, espera o dono.
RSpec.describe Crm::Entrega::Reabertura do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:joao) { create(:contact, account: account, name: 'João') }
  let(:seguros) { create_crm_pipeline(account: account, user: admin, name: 'Seguros') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: joao, assignee: ana, status: :resolved) }

  before do
    account.enable_features!(Crm::Conversations::OutroCanal::FLAG)
    [ana, bruno].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    account.crm_cards.create!(pipeline: seguros.first, stage: seguros.last, contact: joao, title: 'Seguro do Onix',
                              primary_conversation: conversa, inbox: inbox, owner: ana)
    online(bruno)
  end

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def regra!(extra = {})
    seguros.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(extra) })
  end

  def joao_volta
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'Oi, voltei')
    conversa.reload
  end

  # Pega: a conversa reabria no nome da Ana de férias, e ninguém procurava outra pessoa.
  it 'dona offline e regra no funil: a regra decide, e o Bruno (online) recebe', :aggregate_failures do
    regra!

    joao_volta

    expect(conversa).to have_attributes(status: 'open', assignee_id: bruno.id)
    expect(Crm::Entrega::Marca.dados(conversa)).to be_nil
  end

  # Pega: tirar a conversa da dona que está trabalhando (ela só respondia mais tarde).
  it 'dona online: fica com ela, sem passar pelo motor' do
    regra!
    online(ana, bruno)
    allow(Crm::Entrega).to receive(:new).and_call_original

    joao_volta

    expect(conversa).to have_attributes(status: 'open', assignee_id: ana.id)
    expect(Crm::Entrega).not_to have_received(:new)
  end

  # Pega: sem regra, a conversa cair para outra pessoa (a regra é esperar a dona) ou ficar no nome dela calando a IA.
  it 'dona offline e sem regra: espera por ela, e a fila entrega quando ela entra', :aggregate_failures do
    joao_volta

    expect(conversa.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.dados(conversa)).to include('modo' => Crm::Entrega::Marca::SEGURANDO, 'dono_id' => ana.id,
                                                           'motivo' => described_class::MOTIVO)

    online(ana, bruno)
    Crm::Ai::HandoffDrainJob.perform_now

    expect(conversa.reload.assignee_id).to eq(ana.id)
  end

  # Pega: a regra valendo nas contas fora do piloto.
  it 'conta sem a flag crm_outro_canal: nada muda' do
    account.disable_features!(Crm::Conversations::OutroCanal::FLAG)
    regra!

    joao_volta

    expect(conversa).to have_attributes(status: 'open', assignee_id: ana.id)
  end

  # Pega: entregar no escuro com a presença fora do ar (pode ser que a Ana esteja online).
  it 'presença fora do ar: fica com a dona' do
    regra!
    allow(OnlineStatusTracker).to receive(:get_available_users).and_raise(Redis::CannotConnectError)

    joao_volta

    expect(conversa).to have_attributes(status: 'open', assignee_id: ana.id)
  end

  # Pega: mensagem nossa (ou nota) mexendo no dono de uma conversa que o cliente não reabriu.
  it 'mensagem de saída na conversa resolvida: não reabre nem troca de pessoa' do
    regra!

    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, sender: ana)

    expect(conversa.reload).to have_attributes(status: 'resolved', assignee_id: ana.id)
  end
end
