require 'rails_helper'

# #1606: toda troca de PESSOA vira passagem por um escritor só (Crm::PassagensListener, síncrono, depois do commit),
# com o motivo e o card que quem atribuiu deixou no contexto (Crm::Passagens.com_motivo). O convite, que não atribui, a
# Entrega grava ela mesma. Nenhuma troca é gravada duas vezes.
RSpec.describe Crm::PassagensListener do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Fora') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Vendas') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia Suporte') }
  let(:tito) { create(:user, account: account, role: :agent, name: 'Tito Triagem') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Robô') }
  let(:contact) { create(:contact, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [ana, bia, tito].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    online(ana, bia, tito)
  end

  after { Current.reset }

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def acesso(user, funil = nil, triage: false)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: triage)
    row.agent_pipelines.create!(account: account, pipeline: funil.first) if funil
  end

  def regra!(funil, extra = {})
    funil.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(extra) })
  end

  def conversa_do_robo
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
    conversation.update!(ai_assignee: bot, assignee: nil)
    conversation
  end

  def card_em(conversation, (pipeline, stage), focused_at: Time.current)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                                     primary_conversation: conversation, inbox: conversation.inbox)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: focused_at)
    card
  end

  def passagens(conversation)
    Crm::Passagem.where(conversation_id: conversation.id).order(:id)
  end

  def como(user)
    Current.user = user
    yield
  ensure
    Current.user = nil
  end

  def atribuir(conversation, user)
    Conversations::AssignmentService.new(conversation: conversation.reload, assignee_id: user&.id).perform
  end

  describe 'a Entrega' do
    # Pega: a passagem do robô grava uma vez, pelo listener, com o motivo e o card do contexto.
    it 'robô pediu, regra direta: uma passagem do robô para a pessoa, pedida pelo robô, com card e motivo', :aggregate_failures do
      online(ana) # só a Ana pode receber: o teste não depende do rodízio entre quem está online
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)
      regra!(vendas)
      acesso(ana, vendas)

      conversa.bot_handoff!

      passagem = passagens(conversa).sole
      expect(conversa.reload.assignee_id).to eq(ana.id)
      expect(passagem.de).to have_attributes(classe: 'AgentBot', id: bot.id)
      expect(passagem.para).to have_attributes(classe: 'User', id: ana.id)
      expect(passagem.pedida_por).to have_attributes(classe: 'AgentBot', id: bot.id)
      expect(passagem).to have_attributes(card_id: card.id, pipeline_id: vendas.first.id, motivo: 'robo_pediu', devolvida_em: nil)
    end

    # Pega: sem regra do funil antes nada gravava a passagem (o pingue-pongue "sem regra").
    it 'sem regra do funil: grava uma vez do mesmo jeito' do
      conversa = conversa_do_robo
      card_em(conversa, vendas)

      conversa.bot_handoff!

      expect(passagens(conversa).sole).to have_attributes(para_id: conversa.reload.assignee_id, para_type: 'User', motivo: 'robo_pediu')
    end

    it 'IA do CRM: uma passagem, pedida pelo sistema, com o motivo da IA do CRM' do
      online(ana) # só a Ana pode receber: o teste não depende do rodízio entre quem está online
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)
      regra!(vendas)
      acesso(ana, vendas)

      Crm::Entrega.new(conversation: conversa, card: card, motivo: 'ia_crm', origem: 'message').call

      expect(passagens(conversa).sole).to have_attributes(pedida_por_type: nil, motivo: 'ia_crm', de_type: 'AgentBot', para_id: ana.id)
    end

    # Pega: a saída da triagem roda dentro do SyncLock (transação de fora): o commit vem depois do fim do com_motivo, e
    # o motivo tem de chegar mesmo assim.
    it 'saída da triagem dentro do SyncLock: uma passagem de quem fazia a triagem para quem cuida do funil, motivo triagem',
       :aggregate_failures do
      acesso(tito, triage: true)
      acesso(ana, vendas)
      allow(Crm::Access::AccountFlag).to receive(:any?).and_return(true)
      conversa = conversa_do_robo
      atribuir(conversa, tito)
      card_em(conversa, vendas)

      Crm::Access::TriageExit.new(conversa.reload).perform

      expect(conversa.reload.assignee_id).to eq(ana.id)
      ultima = passagens(conversa).last
      expect(ultima).to have_attributes(de_type: 'User', de_id: tito.id, para_id: ana.id, motivo: 'triagem')
      expect(passagens(conversa).where(motivo: 'triagem').count).to eq(1)
    end

    it 'segurar (ninguém pode receber) não é passagem' do
      online
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      regra!(vendas, 'prefer_online' => true)
      acesso(ana, vendas)

      conversa.bot_handoff!

      expect(passagens(conversa)).to be_empty
    end

    # Pega a corrida (c): a IA do CRM avaliou o card de Vendas, o assunto virou Suporte; a entrega relê o assunto sob a
    # trava e segue a regra do funil atual.
    it 'o card passado pela IA do CRM ficou velho: entrega pelo assunto atual', :aggregate_failures do
      conversa = conversa_do_robo
      velho = card_em(conversa, vendas, focused_at: 1.minute.ago)
      atual = card_em(conversa, suporte)
      regra!(vendas)
      regra!(suporte)
      acesso(ana, vendas)
      acesso(bia, suporte)

      resultado = Crm::Entrega.new(conversation: conversa, card: velho, motivo: 'ia_crm', origem: 'message').call

      expect(resultado).to have_attributes(status: :entregue, pessoa: bia, card: atual)
      expect(passagens(conversa).sole).to have_attributes(card_id: atual.id, pipeline_id: suporte.first.id)
    end
  end

  describe 'o convite (gravado pela Entrega, porque não atribui)' do
    before do
      regra!(vendas, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600)
      acesso(ana, vendas)
      acesso(bia, vendas)
    end

    it 'grava o convite para a convidada, sem atribuir' do
      online(ana)
      conversa = conversa_do_robo
      card_em(conversa, vendas)

      conversa.bot_handoff!

      expect(conversa.reload.assignee_id).to be_nil
      expect(passagens(conversa).sole).to have_attributes(para_id: ana.id, motivo: 'convite', devolvida_em: nil)
    end

    it 'aceitou ("Atribuir a mim"): a atribuição é gravada e o convite fecha; nunca duas abertas', :aggregate_failures do
      online(ana)
      conversa = conversa_do_robo
      card_em(conversa, vendas)
      conversa.bot_handoff!

      como(ana) { atribuir(conversa, ana) }

      convite, atribuicao = passagens(conversa).to_a
      expect(convite.reload.devolvida_em).to be_present
      expect(atribuicao).to have_attributes(para_id: ana.id, pedida_por_id: ana.id, motivo: 'atribuicao', devolvida_em: nil)
      expect(passagens(conversa).abertas.count).to eq(1)
    end

    it 'venceu e foi re-convidado: o convite da Ana fecha, o do Bruno abre; o Bruno aceita e fica uma aberta', :aggregate_failures do
      bruno = bia
      online(ana)
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)
      conversa.bot_handoff!
      online(bruno)

      travel 7.hours do
        Crm::Entrega.new(conversation: conversa.reload, card: card, motivo: 'robo_pediu', origem: 'fila').call
        como(bruno) { atribuir(conversa, bruno) }
      end

      expect(passagens(conversa).pluck(:motivo, :para_id)).to eq([['convite', ana.id], ['convite', bruno.id], ['atribuicao', bruno.id]])
      expect(passagens(conversa).abertas.sole).to have_attributes(para_id: bruno.id, motivo: 'atribuicao')
    end
  end

  describe 'atribuição pela tela, devolução e conversa resolvida' do
    it '"Atribuir a mim": uma passagem de quem estava (a IA) para a pessoa, pedida por ela' do
      conversa = conversa_do_robo

      como(ana) { atribuir(conversa, ana) }

      expect(passagens(conversa).sole).to have_attributes(de_type: 'AgentBot', de_id: bot.id, para_id: ana.id, pedida_por_id: ana.id,
                                                          motivo: 'atribuicao')
    end

    it 'atribuição dentro de com_motivo("passar_para"), como o POST /passar_para do #1593 vai chamar: grava uma vez com esse motivo' do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      como(ana) { Crm::Passagens.com_motivo('passar_para') { atribuir(conversa, bia) } }

      expect(passagens(conversa).pluck(:motivo)).to eq(%w[atribuicao passar_para])
      expect(passagens(conversa).last).to have_attributes(de_id: ana.id, para_id: bia.id, pedida_por_id: ana.id)
    end

    it 'atribuição sem pessoa por trás (rodízio nativo, automação): grava, pedida pelo sistema' do
      conversa = conversa_do_robo

      atribuir(conversa, ana)

      expect(passagens(conversa).sole).to have_attributes(para_id: ana.id, pedida_por_type: nil, motivo: 'atribuicao')
    end

    it 'devolução pela tela: a pessoa sai e a conversa volta ao robô; a ida fecha sozinha', :aggregate_failures do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      como(ana) { atribuir(conversa, nil) }

      ida, volta = passagens(conversa).to_a
      expect(conversa.reload.ai_assignee).to eq(bot)
      expect(ida.reload).to have_attributes(devolvida_em: be_present, devolvida_por_id: ana.id)
      expect(volta).to have_attributes(de_id: ana.id, para_type: 'AgentBot', para_id: bot.id, motivo: 'devolucao', devolvida_em: nil)
    end

    it 'troca para a IA dentro de com_motivo("passar_para_ia"), o contrato do PassarParaIa: o listener não grava de novo' do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      como(ana) do
        Crm::Passagens.com_motivo('passar_para_ia') do
          Crm::Passagens.registrar!(conversation: conversa, de: ana, para: bot, pedida_por: ana, motivo: 'passar_para_ia')
          Conversations::AssignmentService.new(conversation: conversa.reload, assignee_id: bot.id, assignee_type: 'AgentBot').perform
        end
      end

      expect(passagens(conversa).pluck(:motivo)).to eq(%w[atribuicao passar_para_ia])
    end

    # O PassarParaIa recusa com :pessoa_atribuida quando há pessoa no nome (decisão "a"): nada muda e nada é gravado.
    it 'PassarParaIa recusado com pessoa no nome: a conversa fica com ela e não há passagem nova' do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      recusa = Crm::Passagens.com_motivo('passar_para_ia') { :pessoa_atribuida }

      expect(recusa).to eq(:pessoa_atribuida)
      expect(conversa.reload.assignee_id).to eq(ana.id)
      expect(passagens(conversa).pluck(:motivo)).to eq(%w[atribuicao])
      expect(Crm::Passagens.ultima_aberta(conversa).para).to have_attributes(classe: 'User', id: ana.id)
    end

    it 'desatribuição sem destino (caixa sem robô): encerra a passagem em aberto' do
      inbox.agent_bot_inbox.destroy!
      conversa = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
      como(admin) { atribuir(conversa, ana) }

      como(ana) { atribuir(conversa, nil) }

      expect(passagens(conversa).sole).to have_attributes(devolvida_em: be_present, devolvida_por_id: ana.id)
    end

    it 'conversa resolvida encerra a passagem em aberto' do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      como(ana) { conversa.reload.update!(status: :resolved) }

      expect(Crm::Passagens.aberta?(conversa)).to be(false)
    end

    # Pega o achado do revisor: resolver tirando a pessoa numa caixa com robô (TriageExit, ramo sem passagem) deixava
    # uma passagem pessoa → robô aberta, porque os after_commit rodam em ordem inversa.
    it 'resolvida no mesmo save em que a pessoa sai e o robô fica: nada fica em aberto' do
      conversa = conversa_do_robo
      como(ana) { atribuir(conversa, ana) }

      como(ana) { conversa.reload.update!(status: :resolved, assignee: nil, ai_assignee: bot) }

      expect(Crm::Passagens.aberta?(conversa)).to be(false)
      expect(passagens(conversa).count).to eq(1)
    end

    it 'vários saves de pessoa na mesma transação viram uma passagem: do primeiro "antes" para a pessoa do fim' do
      conversa = conversa_do_robo

      como(admin) do
        Conversation.transaction do
          conversa.update!(assignee: ana, ai_assignee: nil)
          conversa.update!(assignee: bia)
        end
      end

      expect(passagens(conversa).sole).to have_attributes(de_type: 'AgentBot', de_id: bot.id, para_id: bia.id)
    end

    # Pega a troca velha presa no objeto: robô → Ana desfeita deixaria o "antes" = robô; a conversa muda por fora para
    # a Bia; o save seguinte (Bia → Tito) tem de sair da Bia, não do robô.
    it 'troca de uma transação desfeita não vale para a próxima: o "antes" é o do banco' do
      conversa = conversa_do_robo

      como(admin) do
        Conversation.transaction do
          conversa.update!(assignee: ana, ai_assignee: nil)
          raise ActiveRecord::Rollback
        end
        Conversation.where(id: conversa.id).update_all(assignee_id: bia.id, assignee_agent_bot_id: nil, ai_assignee_type: nil) # rubocop:disable Rails/SkipsModelValidations
        conversa.reload.update!(assignee: tito)
      end

      expect(passagens(conversa).sole).to have_attributes(de_type: 'User', de_id: bia.id, para_id: tito.id)
    end

    it 'vários saves na mesma transação guardam o primeiro motivo e card (o segundo save fora do com_motivo)' do
      conversa = conversa_do_robo
      card = card_em(conversa, vendas)

      como(admin) do
        Conversation.transaction do
          Crm::Passagens.com_motivo('passar_para', card: card) { conversa.update!(assignee: ana, ai_assignee: nil) }
          conversa.update!(assignee: bia)
        end
      end

      expect(passagens(conversa).sole).to have_attributes(motivo: 'passar_para', card_id: card.id, para_id: bia.id)
    end

    it 'uma falha ao gravar a passagem não desfaz a atribuição' do
      conversa = conversa_do_robo
      allow(Crm::Passagens).to receive(:registrar!).and_raise(ActiveRecord::StatementInvalid)

      como(ana) { atribuir(conversa, ana) }

      expect(conversa.reload.assignee_id).to eq(ana.id)
    end
  end
end
