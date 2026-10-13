require 'rails_helper'

# Motor único de entrega (#1454): cenários da auditoria §4.8, reproduzindo as contas reais. Salvo onde dito, a caixa
# está com o rodízio nativo DESLIGADO, como nas contas 16, 18, 3, 27, 40, 43 e 44. Cada cenário diz que falha pega.
RSpec.describe Crm::Entrega do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Fora') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Vendas') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia Vendas') }
  let(:tito) { create(:user, account: account, role: :agent, name: 'Tito Triagem') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    online
  end

  def membros(*users, caixa: inbox)
    users.each { |user| create(:inbox_member, inbox: caixa, user: user) }
  end

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def acesso(user, funil = nil, triage: false, only_own: false)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false,
                                        triage: triage, only_own: only_own)
    row.agent_pipelines.create!(account: account, pipeline: funil.first) if funil
  end

  def regra!(funil, extra = {})
    funil.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(extra) })
  end

  # Conversa com o robô no nome, aberta: como nasce numa caixa de robô (#1377).
  def conversa_do_robo(caixa: inbox)
    conversation = create(:conversation, account: account, inbox: caixa, contact: contact, status: :open).reload
    conversation.update!(ai_assignee: bot, assignee: nil)
    conversation
  end

  def card_em(conversation, (pipeline, stage))
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                              primary_conversation: conversation, inbox: conversation.inbox)
  end

  def marca(conversation)
    Crm::Entrega::Marca.dados(conversation.reload)
  end

  def atribuicoes_de(conversation)
    have_received(:dispatch).with(Events::Types::ASSIGNEE_CHANGED, anything, hash_including(conversation: conversation))
  end

  describe 'robô passando a conversa (bot_handoff!)' do
    before do
      membros(ana, bia, tito)
      acesso(ana, vendas)
      acesso(bia, pos_venda)
      acesso(tito, triage: true)
    end

    # Pega: com o nativo desligado, antes ninguém era escolhido e a conversa ficava "à espera" para sempre (G1).
    it 'rodízio nativo desligado: quem cuida do funil e está online recebe, e o robô sai', :aggregate_failures do
      online(ana, bia, tito)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas)

      conversa.bot_handoff!

      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
      expect(conversa).not_to be_bot_handoff_waiting
      expect(marca(conversa)).to be_nil
    end

    # Pega: "ninguém online" virava espera eterna; agora o motor segura e a fila entrega quando alguém entra, mesmo
    # sem a IA do CRM ligada (o drain não pode depender de CRM_AI_ENABLED).
    it 'ninguém online: o robô segue respondendo, a conversa espera, e a fila entrega quando alguém entra', :aggregate_failures do
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas)

      conversa.bot_handoff!

      expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
      expect(conversa).to be_bot_handoff_waiting
      expect(marca(conversa)).to include('modo' => 'segurando', 'motivo' => 'robo_pediu')

      online(ana)
      Crm::Ai::HandoffDrainJob.perform_now

      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      expect(conversa).not_to be_bot_handoff_waiting
      expect(marca(conversa)).to be_nil
    end

    # Pega: a regra do funil com "Só entregar para quem está online" desligado tem de entregar mesmo sem ninguém
    # online (o comportamento de sempre da Atribuição), e não segurar.
    it 'regra sem "só online": entrega mesmo sem ninguém online, para quem tem menos conversas abertas' do
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas, 'prefer_online' => false)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(ana.id)
    end

    # Pega: entregar a conversa do card de Vendas para quem só cuida de Pós-venda ou só da triagem.
    it 'ninguém que cuida do funil: não entrega para quem cuida de outro assunto', :aggregate_failures do
      online(bia, tito)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to be_nil
      expect(marca(conversa)).to include('modo' => 'segurando')
    end

    # Pega: o convite da regra (r3) não atribui, não cala o robô e deixa a marca que o nativo respeita; vencido, a
    # marca sai.
    it 'convite: convida quem cuida do funil, o robô segue, e a marca sai quando o convite vence', :aggregate_failures do
      online(ana)
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)
      regra!(vendas, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600)

      conversa.bot_handoff!

      expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
      expect(conversa.conversation_participants.pluck(:user_id)).to include(ana.id)
      expect(marca(conversa)).to include('modo' => 'convite')
      expect(card.reload.metadata.dig('ai', 'handoff', 'invited_agent_id')).to eq(ana.id)

      travel 2.hours do
        Crm::Ai::HandoffDrainJob.perform_now
      end

      expect(marca(conversa)).to be_nil
      expect(conversa.reload.assignee_id).to be_nil
    end

    # Pega: a conversa viva está noutra caixa do mesmo card; a fila tem de ser da caixa onde o cliente fala (#553).
    it 'conversa em outra caixa: a fila é a da caixa da conversa viva', :aggregate_failures do
      outra_caixa = create(:inbox, account: account, enable_auto_assignment: false)
      create(:agent_bot_inbox, inbox: outra_caixa, agent_bot: bot)
      membros(bia, caixa: outra_caixa)
      online(ana, bia)
      primaria = create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved).reload
      card = card_em(primaria, vendas)
      regra!(vendas)
      viva = conversa_do_robo(caixa: outra_caixa)
      card.card_conversations.create!(account: account, conversation: viva, is_primary: false)

      viva.bot_handoff!

      expect(viva.reload.assignee_id).to eq(bia.id)
      expect(primaria.reload.assignee_id).to be_nil
    end
  end

  describe 'Agentes IA: o Responder chama o motor sem mudar uma linha' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda o cliente.')
    end
    let(:vinculo) { Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: bot) }
    let(:conversa) { conversa_do_robo }

    around do |example|
      with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
        example.run
      end
    end

    before do
      membros(ana)
      card_em(conversa, vendas)
      regra!(vendas)
      create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'quero falar com alguém')
    end

    # Pega: o sinal de passagem do agente Autonomia (handoff_if_signaled) só tentava o nativo.
    it 'robô Autonomia sinaliza a passagem: a resposta sai e quem cuida do funil recebe', :aggregate_failures do
      online(ana)
      resposta = Autonomia::Agents::AnswerResult.new(reply: 'Vou chamar a equipe.', confidence: 0.9,
                                                     handoff: { should: true, reason: 'human_requested' },
                                                     used_knowledge: [], answered_from_knowledge: false)
      allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: resposta))

      result = Autonomia::Agents::Operate::Responder.new(conversation: conversa, agent_inbox: vinculo).perform

      expect(result.status).to eq(:replied)
      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    end

    # Pega: sábado, fora do horário (porta fechada do Responder), ninguém online. A conversa não pode ficar sem
    # resposta nem presa: o robô segue respondendo e, na segunda, quem entra recebe.
    it 'sábado fora do horário: segura com o robô e entrega na segunda, quando alguém entra', :aggregate_failures do
      agente.update!(config: { 'response_window' => 'business_hours' })
      inbox.update!(working_hours_enabled: true)
      allow_any_instance_of(Inbox).to receive(:out_of_office?).and_return(true) # rubocop:disable RSpec/AnyInstance

      travel_to Time.zone.local(2026, 10, 17, 9, 0) do # sábado
        result = Autonomia::Agents::Operate::Responder.new(conversation: conversa, agent_inbox: vinculo).perform

        expect(result.status).to eq(:skipped)
        expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
        expect(marca(conversa)).to include('modo' => 'segurando')
      end

      travel_to Time.zone.local(2026, 10, 19, 9, 0) do # segunda
        online(ana)
        Crm::Ai::HandoffDrainJob.perform_now
      end

      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    end
  end

  describe 'saída da triagem' do
    before do
      membros(ana, tito)
      acesso(ana, vendas)
      acesso(tito, triage: true)
      online(ana, tito)
    end

    # Pega: a saída da triagem só reatribuía pelo nativo (G6); com ele desligado, a conversa ficava sem ninguém.
    it 'com robô: quem fazia a triagem sai e quem cuida do funil recebe, sem rodízio nativo', :aggregate_failures do
      conversa = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: tito).reload
      card_em(conversa, vendas)

      Crm::Access::VisibilitySync.perform(conversa.reload)

      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      expect(conversa).not_to be_bot_handoff_waiting
    end

    it 'sem robô na caixa: quem cuida do funil recebe' do
      inbox.agent_bot_inbox.destroy!
      inbox.reload
      conversa = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: tito).reload
      card_em(conversa, vendas)

      Crm::Access::VisibilitySync.perform(conversa.reload)

      expect(conversa.reload.assignee_id).to eq(ana.id)
    end
  end

  describe 'quem entra na fila' do
    # Pega: em contas como a 16 todos da caixa são administradores; sem eles na fila, ninguém receberia.
    it 'administrador da caixa recebe por padrão' do
      chefe = create(:user, account: account, role: :administrator, name: 'Chefe')
      membros(chefe)
      online(chefe)
      conversa = conversa_do_robo

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(chefe.id)
    end

    it 'administrador entra mesmo quando o funil restringe as outras pessoas', :aggregate_failures do
      chefe = create(:user, account: account, role: :administrator, name: 'Chefe')
      membros(chefe, bia)
      acesso(bia, pos_venda)
      online(chefe, bia)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(chefe.id)
    end

    # Pega: o usuário de integração (token do n8n ou do MCP) vira membro da caixa e nunca pode receber conversa; nem
    # quem está em "Só as que atende".
    it 'usuário de integração e "Só as que atende" não recebem: a conversa fica segura com o robô', :aggregate_failures do
      integracao = create(:user, account: account, role: :agent, name: 'n8n')
      AccountUser.find_by(account: account, user: integracao).update!(integration: true)
      membros(integracao, bia)
      acesso(bia, vendas, only_own: true)
      online(integracao, bia)
      conversa = conversa_do_robo

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to be_nil
      expect(marca(conversa)).to include('modo' => 'segurando', 'motivo' => 'robo_pediu')
    end

    # Pega: caixa sem CRM (sem card, sem "Quem cuida do quê") e sem nativo: antes nada; agora quem está online e tem
    # menos conversas abertas.
    it 'caixa sem CRM: quem está online e tem menos conversas abertas recebe', :aggregate_failures do
      membros(ana, bia)
      online(ana, bia)
      2.times { create(:conversation, account: account, inbox: inbox, assignee: ana, status: :open) }
      conversa = conversa_do_robo

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(bia.id)
    end

    # Pega: id de pessoa de outra conta gravado na regra (pessoa fixa) nunca recebe; a fila cai para quem cuida.
    it 'cross-account: pessoa fixa de outra conta é ignorada e a fila da caixa recebe', :aggregate_failures do
      outra_conta = create(:account)
      estranho = create(:user, account: outra_conta, role: :administrator)
      membros(ana)
      online(ana, estranho)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas, 'pool_type' => 'user', 'pool_id' => estranho.id)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(ana.id)
    end

    it 'pessoa fixa da regra recebe, mesmo com outra pessoa com menos conversas' do
      membros(ana, bia)
      online(ana, bia)
      create(:conversation, account: account, inbox: inbox, assignee: bia, status: :open)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas, 'pool_type' => 'user', 'pool_id' => bia.id)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(bia.id)
    end
  end

  describe 'convivência com o rodízio nativo' do
    before { membros(ana, bia) }

    # Pega: o nativo V1 ligado e o motor atribuindo a mesma conversa na passagem.
    it 'nativo V1 ligado: uma atribuição só' do
      inbox.update!(enable_auto_assignment: true)
      online(ana)
      conversa = conversa_do_robo
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to eq(ana.id)
      expect(Rails.configuration.dispatcher).to atribuicoes_de(conversa).once
    end

    # Pega: o motor segurando e o job do nativo V2 entregando por cima (atribuição dupla / fora da regra).
    it 'nativo V2 ligado: o job pula a conversa que o motor segura, e a fila do motor entrega uma vez só', :aggregate_failures do
      account.enable_features('assignment_v2')
      account.save!
      inbox.update!(enable_auto_assignment: true)
      create(:inbox_assignment_policy, inbox: inbox, assignment_policy: create(:assignment_policy, account: account, enabled: true))
      conversa = conversa_do_robo
      conversa.bot_handoff!
      expect(marca(conversa)).to include('modo' => 'segurando')
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      online(ana, bia)
      expect(AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment(limit: 10)).to eq(0)
      Crm::Ai::HandoffDrainJob.perform_now

      expect(conversa.reload.assignee_id).to be_in([ana.id, bia.id])
      expect(Rails.configuration.dispatcher).to atribuicoes_de(conversa).once
    end

    it 'nativo V1 não atribui por cima da conversa que o motor segura' do
      inbox.update!(enable_auto_assignment: true)
      conversa = conversa_do_robo
      conversa.bot_handoff!(keep_bot: false)
      expect(marca(conversa)).to include('modo' => 'segurando', 'motivo' => 'robo_desligado')
      online(ana)

      AutoAssignment::AgentAssignmentService.new(conversation: conversa.reload, allowed_agent_ids: inbox.member_ids_with_assignment_capacity).perform

      expect(conversa.reload.assignee_id).to be_nil
    end
  end

  describe 'concorrência' do
    before do
      membros(ana, bia)
      online(ana, bia)
    end

    # Pega a corrida R1: o executor da IA do CRM lia o atendente fora da trava; quem atribuía no meio (uma pessoa, o
    # nativo) era sobrescrito. Agora o motor relê sob a trava e não grava por cima.
    it 'a IA do CRM não sobrescreve quem foi atribuído depois que ela leu a conversa', :aggregate_failures do
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)
      regra!(vendas)
      executor = Crm::Ai::HandoffExecutor.new(card: card, handoff: { intent: 'transferir' })
      Conversations::AssignmentService.new(conversation: Conversation.find(conversa.id), assignee_id: bia.id).perform

      resultado = executor.perform

      expect(resultado).to have_attributes(status: :skipped, error: 'already_assigned')
      expect(conversa.reload.assignee_id).to eq(bia.id)
    end

    it 'duas passagens seguidas: a segunda não muda nada' do
      conversa = conversa_do_robo
      conversa.bot_handoff!
      primeira = conversa.reload.assignee_id
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      Conversation.find(conversa.id).bot_handoff!

      expect(conversa.reload.assignee_id).to eq(primeira)
      expect(Rails.configuration.dispatcher).not_to atribuicoes_de(conversa)
    end
  end
end
