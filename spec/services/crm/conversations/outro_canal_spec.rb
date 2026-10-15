require 'rails_helper'

# Outro canal (#1150, R13; decisão do Rodrigo em 12/10): o cliente com card aberto que escreve por outra caixa tem a
# conversa nova ligada ao card aberto mais recente e entregue ao dono dele pelo motor de entrega (Crm::Entrega), sem
# passar pela triagem. Card sem dono, dono sem o funil na caixa nova, card fechado e contato diferente seguem o fluxo
# de sempre. Entra pela sincronização do card (CardSyncer), como em produção.
RSpec.describe 'Outro canal (R13): conversa nova ligada ao card aberto' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno triagem') }
  let(:whatsapp) { create(:inbox, account: account, enable_auto_assignment: false) }
  # Caixa nova com o rodízio nativo: ele pôs o Bruno (triagem) na criação da conversa, antes da sincronização do card.
  let(:email) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:seguros) { create_crm_pipeline(account: account, user: admin, name: 'Seguros') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:joao) { create(:contact, account: account, name: 'João', email: 'joao@example.com', phone_number: '+5511999990000') }
  let!(:onix) { card_aberto(title: 'Seguro do Onix', owner: ana, last_activity_at: 2.days.ago) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [ana, bruno].each { |user| create(:inbox_member, inbox: email, user: user) }
    create(:inbox_member, inbox: whatsapp, user: ana)
    account.crm_inbox_settings.create!(inbox: email, crm_enabled: true)
    account.crm_pipeline_inboxes.create!(inbox: email, pipeline: seguros.first)
    online(ana, bruno)
  end

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def card_aberto(title:, owner:, last_activity_at:)
    primeira = create(:conversation, account: account, inbox: whatsapp, contact: joao, assignee: owner)
    account.crm_cards.create!(pipeline: seguros.first, stage: seguros.last, contact: joao, title: title,
                              primary_conversation: primeira, inbox: whatsapp, owner: owner, last_activity_at: last_activity_at)
  end

  def acesso(user, funil = nil, triage: false, inbox: email)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: triage, only_own: false)
    row.agent_pipelines.create!(account: account, pipeline: funil.first) if funil
  end

  # O e-mail do João: conversa nova na caixa de e-mail, aberta pela mensagem dele (o rodízio nativo já pôs o Bruno).
  def email_do_joao(contact: joao, assignee: bruno, **attrs)
    conversation = create(:conversation, account: account, inbox: email, contact: contact, assignee: assignee, **attrs)
    message = create(:message, account: account, inbox: email, conversation: conversation, message_type: :incoming,
                               content: 'Segue o documento do Onix')
    [conversation, message]
  end

  def sincronizar(conversation, message)
    Crm::Conversations::CardSyncer.new(conversation: conversation, message: message).perform
    conversation.reload
  end

  def ligada?(conversation, card = onix)
    Crm::CardConversation.exists?(card: card, conversation: conversation)
  end

  it 'e-mail do João com card aberto: liga ao card, entrega à dona e não cria card duplicado', :aggregate_failures do
    account.crm_pipeline_inboxes.find_by(inbox: email).update!(auto_create_card: true)
    account.crm_inbox_settings.find_by(inbox: email).update!(auto_create_card: true, default_pipeline: seguros.first)
    conversation, message = email_do_joao

    sincronizar(conversation, message)
    sincronizar(conversation, message)

    expect(ligada?(conversation)).to be(true)
    expect(conversation.assignee_id).to eq(ana.id)
    expect(Crm::Entrega::Marca.dados(conversation)).to be_nil
    expect(account.crm_cards.where(contact: joao).count).to eq(1)
    # O card continua do canal de origem e da Ana: a conversa vinculada não o arrasta para a caixa de e-mail.
    expect(onix.reload).to have_attributes(inbox_id: whatsapp.id, owner_id: ana.id)
  end

  it 'dono sem o funil do card na caixa nova: não liga e a conversa segue a triagem', :aggregate_failures do
    acesso(ana, pos_venda)
    acesso(bruno, triage: true)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect(ligada?(conversation)).to be(false)
    expect(conversation.assignee_id).to eq(bruno.id)
  end

  it 'dono que não é membro da caixa nova: não liga' do
    email.inbox_members.where(user: ana).destroy_all
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  it 'dona em "Só as suas" na caixa nova: não liga (o mesmo critério do participante na saída da triagem)' do
    row = Crm::InboxAgentAccess.create!(account: account, inbox: email, user: ana, all_pipelines: false, triage: false, only_own: true)
    row.agent_pipelines.create!(account: account, pipeline: seguros.first)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  it 'falha na entrega: a conversa fica ligada, com quem estava, e a sincronização segue', :aggregate_failures do
    allow_any_instance_of(Crm::Entrega).to receive(:na_passagem).and_raise(ActiveRecord::StatementInvalid) # rubocop:disable RSpec/AnyInstance
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))
    conversation, message = email_do_joao

    expect { sincronizar(conversation, message) }.not_to raise_error
    expect([ligada?(conversation), conversation.assignee_id]).to eq([true, bruno.id])
    expect(ChatwootExceptionTracker).to have_received(:new)
  end

  it 'card sem dono: não liga e a conversa segue a triagem' do
    onix.update!(owner: nil)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  it 'dois cards abertos: o de atividade mais recente, e o dono dele recebe', :aggregate_failures do
    create(:inbox_member, inbox: email, user: admin)
    online(ana, bruno, admin)
    recente = card_aberto(title: 'Sinistro', owner: admin, last_activity_at: 1.hour.ago)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation, recente), ligada?(conversation)]).to eq([true, false])
    expect(conversation.assignee_id).to eq(admin.id)
  end

  it 'o card mais recente sem dono: segue a triagem, sem cair para um card mais antigo' do
    card_aberto(title: 'Sinistro', owner: nil, last_activity_at: 1.hour.ago)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([Crm::CardConversation.exists?(conversation: conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  it 'caixa nova sem CRM, ou sem funil ligado: nada muda', :aggregate_failures do
    account.crm_inbox_settings.find_by(inbox: email).update!(crm_enabled: false)
    desligada, message = email_do_joao
    sincronizar(desligada, message)
    expect([ligada?(desligada), desligada.assignee_id]).to eq([false, bruno.id])

    account.crm_inbox_settings.find_by(inbox: email).update!(crm_enabled: true)
    account.crm_pipeline_inboxes.where(inbox: email).destroy_all
    sem_funil, message = email_do_joao
    sincronizar(sem_funil, message)
    expect([ligada?(sem_funil), sem_funil.assignee_id]).to eq([false, bruno.id])
  end

  it 'dona offline, sem regra de Atribuição: liga, tira da triagem e segura até a Ana entrar', :aggregate_failures do
    online(bruno)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect(ligada?(conversation)).to be(true)
    expect(conversation.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.dados(conversation)).to include('modo' => 'segurando', 'motivo' => 'outro_canal', 'dono_id' => ana.id)

    # A fila tenta de novo: com o Bruno online e a Ana não, continua segurando para ela.
    Crm::Ai::HandoffDrainJob.perform_now
    expect(conversation.reload.assignee_id).to be_nil

    online(ana, bruno)
    Crm::Ai::HandoffDrainJob.perform_now
    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(Crm::Entrega::Marca.dados(conversation)).to be_nil
  end

  it 'regra de convite no funil: convida a dona, sem atribuir' do
    seguros.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite' } })
    allow(Crm::Ai::HandoffInviter).to receive(:new).and_return(instance_double(Crm::Ai::HandoffInviter, perform: true))
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect(Crm::Ai::HandoffInviter).to have_received(:new).with(hash_including(conversation: conversation, agent: ana))
    expect(Crm::Entrega::Marca.dados(conversation)).to include('modo' => 'convite')
  end

  it 'contato diferente com o mesmo e-mail e telefone: não liga' do
    # E-mail é único por conta: o mesmo nome e o mesmo telefone bastam para "parece o João".
    outro = create(:contact, account: account, name: joao.name, email: 'joao.outro@example.com')
    outro.update_columns(phone_number: joao.phone_number) # rubocop:disable Rails/SkipsModelValidations
    conversation, message = email_do_joao(contact: outro)

    sincronizar(conversation, message)

    expect([Crm::CardConversation.exists?(conversation: conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  it 'card fechado (ganho, perdido, resolvido, cancelado, arquivado): não liga' do
    %i[won lost resolved cancelled archived].each do |status|
      # Direto na coluna: o desfecho que cada tipo de funil aceita não importa aqui.
      onix.update_columns(status: Crm::Card.statuses[status]) # rubocop:disable Rails/SkipsModelValidations
      conversation, message = email_do_joao

      sincronizar(conversation, message)

      expect([ligada?(conversation), conversation.assignee_id]).to eq([false, bruno.id]), "status #{status}"
    end
  end

  it 'quem já respondeu não perde: liga ao card e mantém o atendente' do
    conversation, message = email_do_joao
    create(:message, account: account, inbox: email, conversation: conversation, message_type: :outgoing, sender: bruno)

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([true, bruno.id])
  end

  it 'caixa sem rodízio nativo: quem alguém pôs no nome fica, mesmo sem ter respondido' do
    email.update!(enable_auto_assignment: false)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([true, bruno.id])
  end

  it 'caixa sem rodízio e conversa sem ninguém: vai para a dona' do
    email.update!(enable_auto_assignment: false)
    conversation, message = email_do_joao(assignee: nil)

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([true, ana.id])
  end

  it 'só a conversa que o cliente abriu, e só na mensagem que a abriu', :aggregate_failures do
    campanha = create(:conversation, account: account, inbox: email, contact: joao, assignee: bruno)
    create(:message, account: account, inbox: email, conversation: campanha, message_type: :outgoing, sender: bruno)
    resposta = create(:message, account: account, inbox: email, conversation: campanha, message_type: :incoming)
    sincronizar(campanha, resposta)
    expect(ligada?(campanha)).to be(false)

    conversation, = email_do_joao
    segunda = create(:message, account: account, inbox: email, conversation: conversation, message_type: :incoming)
    sincronizar(conversation, segunda)
    expect(ligada?(conversation)).to be(false)
  end

  it 'card da mesma caixa fica com a deduplicação de sempre' do
    onix.update!(inbox: email)
    conversation, message = email_do_joao

    sincronizar(conversation, message)

    expect([ligada?(conversation), conversation.assignee_id]).to eq([false, bruno.id])
  end

  describe 'caixa nova com robô' do
    let(:robo) { create(:agent_bot, account: account) }

    before { create(:agent_bot_inbox, inbox: email, agent_bot: robo) }

    def conversa_do_robo
      conversation, message = email_do_joao(assignee: nil, status: :pending)
      conversation.update!(ai_assignee: robo)
      [conversation, message]
    end

    it 'passa direto para a dona: o robô sai, sem triagem', :aggregate_failures do
      conversation, message = conversa_do_robo

      sincronizar(conversation, message)

      expect(ligada?(conversation)).to be(true)
      expect(conversation).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
    end

    it 'dona offline: o robô segue respondendo, à espera da Ana', :aggregate_failures do
      online(bruno)
      conversation, message = conversa_do_robo

      sincronizar(conversation, message)

      expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: robo)
      expect(conversation).to be_bot_handoff_waiting
      expect(Crm::Entrega::Marca.dados(conversation)).to include('modo' => 'segurando', 'dono_id' => ana.id)
    end
  end
end
