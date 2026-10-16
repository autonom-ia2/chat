require 'rails_helper'

# Dono do card vê a conversa em "Só as suas" (#1652, R4, decisão do Rodrigo em 15/10). A Ana é dona do card "Seguro do
# Onix", mas quem atende é o Bruno: ela precisa ler a conversa para retomar o pedido. Vale em todo ponto de acesso, e
# a regra em SQL (lista, link) e a em memória (tempo real, notificação, rodízio) dão o mesmo resultado. Card aberto manda
# (#1339): com card aberto na conversa, só o dono de um aberto vê; ganho e perdido só contam sem nenhum aberto.
RSpec.describe 'Acesso por funil: dono do card vê a conversa em "Só as suas"' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana_and_account_user) { create_crm_agent(account: account, name: 'Ana') }
  let(:ana) { ana_and_account_user.first }
  let(:bruno) { create_crm_agent(account: account, name: 'Bruno').first }
  let(:carla_and_account_user) { create_crm_agent(account: account, name: 'Carla') }
  let(:carla) { carla_and_account_user.first }
  let(:inbox) { create_crm_inbox(account: account, members: [ana, bruno, carla]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:contact) { account.contacts.create!(name: 'Harry Onix', phone_number: "+55119#{rand(10_000_000..99_999_999)}") }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: bruno) }

  before do
    only_own(ana)
    only_own(carla)
    restrict(bruno, vendas)
  end

  def only_own(user)
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false, only_own: true)
  end

  def restrict(user, (pipeline, _stage))
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  # linked: o card entra pela crm_card_conversations, sem ser a conversa principal dele.
  def card((pipeline, stage), owner:, status: :open, linked: false, target: conversa)
    created = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Seguro do Onix', inbox: inbox, owner: owner,
                                        contact: target.contact, primary_conversation: linked ? nil : target)
    Crm::CardConversation.create!(account: account, card: created, conversation: target) if linked
    created.update_columns(status: Crm::Card.statuses[status]) unless status == :open # rubocop:disable Rails/SkipsModelValidations
    created
  end

  def sees_by_link?(user, target = conversa)
    Crm::Access::ConversationScope.new(user: user, account: account).allows?(target.reload)
  end

  def sees_by_realtime?(user, target = conversa)
    Crm::Access::Recipients.inbox_members(target.reload).include?(user)
  end

  def expect_sees(user, expected, target = conversa)
    expect(sees_by_link?(user, target)).to be(expected), "link (SQL) de #{user.name}"
    expect(sees_by_realtime?(user, target)).to be(expected), "tempo real (memória) de #{user.name}"
  end

  describe 'regra' do
    it 'a dona de card aberto vê; quem não é dona continua sem ver' do
      card(sinistro, owner: ana)

      expect_sees(ana, true)
      expect_sees(carla, false)
    end

    it 'card ligado pela crm_card_conversations também libera a dona' do
      card(sinistro, owner: ana, linked: true)

      expect_sees(ana, true)
      expect_sees(carla, false)
    end

    it 'a ex-dona para de ver e a nova dona passa a ver' do
      onix = card(sinistro, owner: ana)

      onix.update!(owner: carla)

      expect_sees(ana, false)
      expect_sees(carla, true)
    end

    it 'card sem dono não libera ninguém em "Só as suas"' do
      card(sinistro, owner: nil)

      expect_sees(ana, false)
      expect_sees(carla, false)
    end

    it 'card aberto manda: a dona de um ganho não vê se a conversa tem outro card aberto' do
      card(sinistro, owner: ana, status: :won)
      card(vendas, owner: bruno)

      expect_sees(ana, false)
      expect_sees(bruno, true)
    end

    it 'sem card aberto, a dona do ganho ou perdido vê (o card ainda prende a conversa)' do
      card(sinistro, owner: ana, status: :lost)

      expect_sees(ana, true)
      expect_sees(carla, false)
    end

    %i[resolved cancelled archived].each do |released|
      it "card #{released} solta a conversa: a dona não vê mais" do
        card(sinistro, owner: ana, status: released)

        expect_sees(ana, false)
      end
    end

    it 'ser dona de card de outra conversa não libera esta' do
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: bruno)
      card(sinistro, owner: ana, target: outra)

      expect_sees(ana, false)
      expect_sees(ana, true, outra)
    end

    it 'a lista traz a conversa da dona e esconde a da outra pessoa' do
      card(sinistro, owner: ana)
      visible = ->(user) { Crm::Access::ConversationScope.new(user: user, account: account).apply(account.conversations).to_a }

      expect(visible.call(ana)).to contain_exactly(conversa)
      expect(visible.call(carla)).to be_empty
    end
  end

  describe 'cada ponto de acesso' do
    before do
      card(sinistro, owner: ana)
      create(:message, account: account, inbox: inbox, conversation: conversa, content: 'Mensagem do Harry Onix')
    end

    it 'lista (PermissionFilterService)' do
      expect(Conversations::PermissionFilterService.new(account.conversations, ana, account).perform).to contain_exactly(conversa)
      expect(Conversations::PermissionFilterService.new(account.conversations, carla, account).perform).to be_empty
    end

    it 'link (ConversationPolicy)' do
      expect(ConversationPolicy.new({ user: ana, account: account, account_user: ana_and_account_user.last }, conversa).show?)
        .to be(true)
      expect(ConversationPolicy.new({ user: carla, account: account, account_user: carla_and_account_user.last }, conversa).show?)
        .to be(false)
    end

    describe 'busca (SearchService)' do
      before { Current.account = account }
      after { Current.account = nil }

      def search(user, type)
        SearchService.new(current_user: user, current_account: account, params: { q: 'Harry' }, search_type: type).perform
      end

      it 'conversas e mensagens' do
        expect(search(ana, 'Conversation')[:conversations]).to contain_exactly(conversa)
        expect(search(ana, 'Message')[:messages].map(&:conversation_id)).to contain_exactly(conversa.id)
        expect(search(carla, 'Conversation')[:conversations]).to be_empty
        expect(search(carla, 'Message')[:messages]).to be_empty
      end
    end

    it 'notificação de conversa nova (NotificationListener)' do
      builder = instance_double(NotificationBuilder, perform: true)
      allow(NotificationBuilder).to receive(:new).and_return(builder)

      NotificationListener.instance.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversa))

      expect(NotificationBuilder).to have_received(:new).with(hash_including(user: ana))
      expect(NotificationBuilder).not_to have_received(:new).with(hash_including(user: carla))
    end

    it 'tempo real (ActionCableListener)' do
      message = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming)
      sent = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) { |tokens, *_rest| sent << tokens }

      ActionCableListener.instance.message_created(Events::Base.new(:'message.created', Time.zone.now, message: message))

      expect(sent).not_to be_empty
      expect(sent).to all(include(ana.pubsub_token))
      expect(sent.flatten).not_to include(carla.pubsub_token)
    end

    it 'contadores: o aviso de não lidas e a contagem por caixa' do
      _account, members = Conversations::UnreadCounts::BroadcastScope.new(
        Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conversa)
      ).perform
      allow(Conversations::UnreadCounts::Store).to receive(:members_for_keys) { |keys| keys.index_with { [conversa.id] } }
      count = lambda do |user|
        counter = Conversations::UnreadCounts::Counter.new(account: account, user: user)
        allow(counter).to receive(:visible_inbox_ids).and_return([inbox.id])
        counter.send(:unread_inbox_counts)
      end

      expect(members).to include(ana)
      expect(members).not_to include(carla)
      expect(count.call(ana)).to eq(inbox.id.to_s => 1)
      expect(count.call(carla)).to eq({})
    end

    it 'CRM (Crm::Conversations::Visibility)' do
      visible = lambda do |user, account_user|
        Crm::Conversations::Visibility.new(account: account, user: user, account_user: account_user).visible?(conversa)
      end

      expect(visible.call(ana, ana_and_account_user.last)).to be(true)
      expect(visible.call(carla, carla_and_account_user.last)).to be(false)
    end

    it 'Copiloto (EE)' do
      reader = Class.new { include Captain::Copilot::ConversationAccess }.new

      expect(reader.send(:accessible_conversation, account: account, user: ana, display_id: conversa.display_id)).to eq(conversa)
      expect(reader.send(:accessible_conversation, account: account, user: carla, display_id: conversa.display_id)).to be_nil
    end

    it 'ligações (CallStreams)' do
      streams = Crm::Access::CallStreams.for(conversa)

      expect(streams).to include(ana.pubsub_token)
      expect(streams).not_to include(carla.pubsub_token)
    end
  end

  describe 'invalidação quando o dono muda' do
    # Funil do Bruno: ele segue atendendo (a saída da triagem não mexe), e só a troca de dono muda quem vê.
    let!(:onix) { card(vendas, owner: ana) }

    # A sincronização de quando o card nasceu já rodou (sem isso a mudança cai na que está na fila).
    before { Crm::Access::CountInvalidation.sync_started!([conversa.id]) }

    it 'trocar o dono vence o cache dos contadores e agenda a sincronização da conversa' do
      invalidator = instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, conversation_changed!: true)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)

      expect { onix.update!(owner: carla) }.to have_enqueued_job(Crm::Access::VisibilitySyncJob).with(array_including(conversa.id))
      expect(invalidator).to have_received(:conversation_changed!)
    end

    it 'trocar o dono de um card ligado sincroniza a conversa ligada' do
      ligada = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: bruno)
      Crm::CardConversation.create!(account: account, card: onix, conversation: ligada)
      Crm::Access::CountInvalidation.sync_started!([conversa.id, ligada.id])

      expect { onix.update!(owner: carla) }.to have_enqueued_job(Crm::Access::VisibilitySyncJob).with(array_including(ligada.id))
    end

    it 'a sincronização tira a conversa da ex-dona e entrega à nova dona' do
      onix.update!(owner: carla)
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      Crm::Access::VisibilitySync.perform(conversa)

      expect(ActionCableBroadcastJob).to have_received(:perform_later)
        .with(array_including(carla.pubsub_token), Events::Types::CONVERSATION_UPDATED, anything).at_least(:once)
      expect(ActionCableBroadcastJob).to have_received(:perform_later)
        .with([ana.pubsub_token], Crm::Access::VisibilitySync::REVOKED, hash_including(id: conversa.id))
    end

    it 'sem ninguém em "Só as suas" na conta, trocar o dono não agenda sincronização (o dono não muda a visão)' do
      Crm::InboxAgentAccess.where(only_own: true).destroy_all

      expect { onix.update!(owner: bruno) }.not_to have_enqueued_job(Crm::Access::VisibilitySyncJob)
    end

    it 'mudar outro campo do card (título) não agenda sincronização' do
      expect { onix.update!(title: 'Seguro do Onix 2024') }.not_to have_enqueued_job(Crm::Access::VisibilitySyncJob)
    end
  end

  describe 'paridade da regra (memória do Recipients × SQL do link) com o dono' do
    it 'decide igual para cada combinação de acesso, dono e status' do
      ganho_sem_aberto = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      card(sinistro, owner: ana, status: :won, target: ganho_sem_aberto)
      ganho_com_aberto = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      card(sinistro, owner: ana, status: :won, target: ganho_com_aberto)
      card(vendas, owner: carla, target: ganho_com_aberto)
      ligada = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      card(vendas, owner: ana, linked: true, target: ligada)
      arquivado = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      card(sinistro, owner: ana, status: :archived, target: arquivado)
      sem_dono = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      card(sinistro, owner: nil, target: sem_dono)
      triagem = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      conversas = [ganho_sem_aberto, ganho_com_aberto, ligada, arquivado, sem_dono, triagem]
      combos = [
        { all_pipelines: false, triage: false, only_own: true }, { all_pipelines: true, triage: true, only_own: true },
        { all_pipelines: false, triage: false, only_own: false }, { all_pipelines: false, triage: true, only_own: false },
        { all_pipelines: true, triage: false, only_own: false }
      ]

      combos.each do |combo|
        Crm::InboxAgentAccess.find_by(user: ana).update!(combo)
        conversas.each do |item|
          expect(sees_by_realtime?(ana, item)).to eq(sees_by_link?(ana, item)), "acesso #{combo}, conversa #{item.id}"
        end
      end
    end
  end
end
