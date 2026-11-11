require 'rails_helper'

# G3 (#2629): o passo "criar retorno" de ponta a ponta. Cria o Crm::FollowUp pelo mesmo pedido da tela, como quem ligou;
# o Creator decide o que vale (envio automático só no card com WhatsApp) e o histórico diz o motivo do que não saiu.
RSpec.describe Autonomia::Automacao::PassoDeRetorno, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Rafa') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin, atendente]) }
  let(:contato) { account.contacts.create!(name: 'Mariana', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:card) do
    funil, etapa = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: funil, stage: etapa, inbox: inbox, contact: contato, primary_conversation: conversa,
                              title: 'Plano anual', owner: atendente)
  end

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before { ligar_motor(account) }

  after { Current.reset }

  def retorno(id = 'r1', **campos)
    { 'id' => id, 'tipo' => 'retorno', 'titulo' => ['Ligar para ', { '$valor' => 'contato.nome' }],
      'daqui' => { 'valor' => 2, 'unidade' => 'dias' } }.merge(campos.stringify_keys)
  end

  def rodar(passos, alvo, por: admin, gatilho: { 'tipo' => 'conversa.resolvida' })
    definicao = automacao_ligada(account, por, passos, gatilho: gatilho)
    execucao = nil
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      execucao = Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: 'conversa.resolvida').call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last || execucao
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  describe 'só o lembrete' do
    it 'no card, cria o retorno do card para quem cuida, como quem ligou, daqui a 2 dias', :aggregate_failures do
      freeze_time do
        execucao = rodar([retorno], card)
        follow_up = Crm::FollowUp.last

        expect(registros(execucao)).to eq([['r1', 'ok', nil]])
        expect(follow_up).to have_attributes(card_id: card.id, conversation_id: conversa.id, title: 'Ligar para Mariana',
                                             created_by_id: admin.id, recipient_mode: 'card_owner',
                                             automation_mode: 'reminder_only', follow_up_type: 'task')
        expect(follow_up.due_at).to eq(2.days.from_now)
      end
    end

    it 'na conversa, é do contato e vai para o responsável da conversa', :aggregate_failures do
      conversa.update!(assignee: atendente)

      execucao = rodar([retorno], conversa)

      expect(registros(execucao)).to eq([['r1', 'ok', nil]])
      expect(Crm::FollowUp.last).to have_attributes(card_id: nil, contact_id: contato.id, recipient_mode: 'users',
                                                    recipient_user_ids: [atendente.id])
    end

    it 'na conversa sem responsável, não cria nada e diz por quê', :aggregate_failures do
      execucao = rodar([retorno], conversa)

      expect(registros(execucao)).to eq([%w[r1 pulado retorno_sem_responsavel]])
      expect(Crm::FollowUp.count).to eq(0)
    end

    # Sem dono, o Followup cairia em quem criou (quem ligou a automação): o passo pula, como na conversa.
    it 'no card sem dono, não cria nada e diz por quê', :aggregate_failures do
      card.update!(owner: nil)

      execucao = rodar([retorno], card)

      expect(registros(execucao)).to eq([%w[r1 pulado retorno_sem_responsavel]])
      expect(Crm::FollowUp.count).to eq(0)
    end

    it 'o horário sai no fuso da conta', :aggregate_failures do
      account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })

      freeze_time do
        rodar([retorno('r1', daqui: { 'valor' => 3, 'unidade' => 'horas' })], card)

        expect(Crm::FollowUp.last).to have_attributes(timezone: 'America/Sao_Paulo', due_at: 3.hours.from_now)
      end
    end

    # G57 (#2769, ex. 1, passo 7): "para hoje" no fuso da conta, nunca "daqui a 1 hora" (que depois das 23h cai amanhã).
    describe 'quando: hoje ou amanhã' do
      let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

      before { account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }

      def quando(dia, hora = nil) = retorno('r1', daqui: nil, quando: { 'dia' => dia, 'hora' => hora }.compact).compact

      def due_at_com(passo, agora)
        travel_to(agora) { rodar([passo], card) }
        Crm::FollowUp.last.due_at
      end

      it 'hoje sem hora vale o fim do dia, mesmo às 23h30' do
        expect(due_at_com(quando('hoje'), fuso.local(2026, 11, 9, 23, 30))).to eq(fuso.local(2026, 11, 9, 23, 59, 59))
      end

      it 'hoje com hora que ainda vem vale essa hora; a que já passou vale em seguida, nunca amanhã', :aggregate_failures do
        expect(due_at_com(quando('hoje', 14), fuso.local(2026, 11, 9, 10))).to eq(fuso.local(2026, 11, 9, 14))
        expect(due_at_com(quando('hoje', 9), fuso.local(2026, 11, 9, 10))).to eq(fuso.local(2026, 11, 9, 10))
      end

      it 'amanhã sem hora vale o fim de amanhã; com hora, a hora de amanhã', :aggregate_failures do
        expect(due_at_com(quando('amanha'), fuso.local(2026, 11, 9, 23, 30))).to eq(fuso.local(2026, 11, 10, 23, 59, 59))
        expect(due_at_com(quando('amanha', 9), fuso.local(2026, 11, 9, 10))).to eq(fuso.local(2026, 11, 10, 9))
      end

      it '"hoje" é o dia no fuso da conta, não o do servidor', :aggregate_failures do
        account.update!(custom_attributes: { 'timezone' => 'Asia/Tokyo' })
        toquio = ActiveSupport::TimeZone['Asia/Tokyo']

        expect(due_at_com(quando('hoje'), Time.utc(2026, 11, 9, 20))).to eq(toquio.local(2026, 11, 10, 23, 59, 59))
        expect(Crm::FollowUp.last.timezone).to eq('Asia/Tokyo')
      end
    end

    # G69 (#2879, ex. 16, passo 6: "grava um retorno para daqui a 11 meses"): meses contam no calendário, no fuso da conta.
    describe 'daqui em meses' do
      let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

      before { account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }

      def meses(valor) = retorno('r1', daqui: { 'valor' => valor, 'unidade' => 'meses' })

      def due_at_com(passo, agora)
        travel_to(agora) { rodar([passo], card) }
        Crm::FollowUp.last.due_at
      end

      it '11 meses a partir de 15/01 vencem em 15/12, na mesma hora' do
        expect(due_at_com(meses(11), fuso.local(2026, 1, 15, 10))).to eq(fuso.local(2026, 12, 15, 10))
      end

      it 'o dia que o mês não tem vira o último dia dele', :aggregate_failures do
        expect(due_at_com(meses(1), fuso.local(2026, 1, 31, 10))).to eq(fuso.local(2026, 2, 28, 10))
        expect(due_at_com(meses(1), fuso.local(2028, 1, 31, 10))).to eq(fuso.local(2028, 2, 29, 10))
      end

      it 'o calendário é o da conta, não o do servidor' do
        account.update!(custom_attributes: { 'timezone' => 'Asia/Tokyo' })
        toquio = ActiveSupport::TimeZone['Asia/Tokyo']

        # 31/01 às 8h em Tóquio é 30/01 no UTC: pelo UTC, venceria em 01/03 em Tóquio.
        expect(due_at_com(meses(1), toquio.local(2026, 1, 31, 8))).to eq(toquio.local(2026, 2, 28, 8))
      end

      it 'o esquema aceita meses só no retorno, até 120', :aggregate_failures do
        valido = ->(passo) { Autonomia::Automacao::Receita.esquema_valido?({ 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }) }

        expect(valido.call(meses(120))).to be(true)
        expect(valido.call(meses(121))).to be(false)
        expect(valido.call({ 'id' => 'e1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'meses' } })).to be(false)
      end
    end

    it 'para pessoas escolhidas ou para um time', :aggregate_failures do
      time = create(:team, account: account)
      rodar([retorno('r1', para: { 'quem' => 'pessoas', 'pessoas' => [admin.id] }),
             retorno('r2', para: { 'quem' => 'time', 'time' => time.id })], card)

      expect(Crm::FollowUp.order(:id).map { |item| [item.recipient_mode, item.recipient_user_ids, item.recipient_team_id] })
        .to eq([['users', [admin.id], nil], ['team', [], time.id]])
    end

    it 'valor vazio no título pula o passo, sem criar', :aggregate_failures do
      contato.update!(name: '')

      execucao = rodar([retorno], card)

      expect(registros(execucao)).to eq([%w[r1 pulado faltou_valor]])
      expect(Crm::FollowUp.count).to eq(0)
    end
  end

  describe 'com a mensagem ao cliente' do
    let(:envio) { { 'mensagem' => ['Oi, ', { '$valor' => 'contato.nome' }, '! Tudo certo?'] } }

    # A mensagem só vale com gatilho de card (conferido ao salvar).
    let(:card_ganho) { { 'tipo' => 'card.ganho' } }

    before do
      ligar_mensagens(account)
      account.enable_features!('automacao_gatilhos')
    end

    it 'no card com WhatsApp e a janela aberta, marca a mensagem automática', :aggregate_failures do
      create_incoming_message(conversation: conversa)

      execucao = rodar([retorno(envio: envio)], card, gatilho: card_ganho)

      expect(registros(execucao)).to eq([['r1', 'ok', nil]])
      expect(Crm::FollowUp.last).to have_attributes(automation_mode: 'auto_send_message', follow_up_type: 'message')
      expect(Crm::FollowUp.last.metadata['message_body']).to eq('Oi, Mariana! Tudo certo?')
    end

    # Sem conversa no card não há para onde mandar: quem recusa é a plataforma (o Creator), não o passo.
    it 'card sem conversa: a plataforma recusa e o histórico mostra', :aggregate_failures do
      card.update!(primary_conversation: nil)

      execucao = rodar([retorno(envio: envio)], card, gatilho: card_ganho)

      expect(registros(execucao)).to eq([%w[r1 falhou erro_permanente]])
      expect(Crm::FollowUp.count).to eq(0)
    end

    it 'sem a mensagem automática ligada na conta, pula sem criar', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [retorno(envio: envio)], gatilho: card_ganho)
      account.disable_features!('automacao_mensagens')

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'conversa.resolvida').call
      end
      execucao = Autonomia::Automacao::Execucao.where(automacao: definicao).last

      expect(registros(execucao)).to eq([%w[r1 pulado mensagens_desligadas]])
      expect(Crm::FollowUp.count).to eq(0)
    end
  end

  # O gate do retorno é o da API: no EE, crm_manage_cards. O salvar já confere; quem perde a chave depois de ligar não
  # cria retorno, e a automação pausa como em qualquer ação sem acesso.
  it 'quem ligou perdeu o poder de criar retorno: a automação pausa e nada é criado', :aggregate_failures do
    skip 'só no EE' unless ChatwootApp.enterprise?

    funcao = create(:custom_role, account: account,
                                  permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
    atendente.account_users.find_by(account: account).update!(custom_role: funcao)
    conversa.update!(assignee: atendente)
    definicao = automacao_ligada(account, atendente, [retorno])
    funcao.update!(permissions: funcao.permissions - %w[crm_manage_cards])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end
    execucao = Autonomia::Automacao::Execucao.where(automacao: definicao).last

    expect(registros(execucao)).to eq([%w[r1 falhou quem_ligou_sem_acesso]])
    expect(execucao.automacao.reload.ativa).to be(false)
    expect(Crm::FollowUp.count).to eq(0)
  end

  # O salvar pede a chave de funis para o retorno; quem a perde depois de ligar pausa a automação já na execução seguinte
  # (#2633), com o motivo dela no histórico.
  it 'quem ligou perdeu a chave de funis: pausa com o motivo e nada é criado', :aggregate_failures do
    skip 'só no EE' unless ChatwootApp.enterprise?

    funcao = create(:custom_role, account: account,
                                  permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
    atendente.account_users.find_by(account: account).update!(custom_role: funcao)
    conversa.update!(assignee: atendente)
    definicao = automacao_ligada(account, atendente, [retorno])
    funcao.update!(permissions: funcao.permissions - %w[crm_manage_pipelines])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end
    execucao = Autonomia::Automacao::Execucao.where(automacao: definicao).last

    expect(registros(execucao)).to eq([%w[r1 falhou sem_chave_de_funis]])
    expect(execucao.automacao.reload.ativa).to be(false)
    expect(Crm::FollowUp.count).to eq(0)
  end

  describe 'ao salvar' do
    def problemas(passo, conta: account)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: conta.account_users.find_by(user: admin)).problemas
    end

    it 'aceita o retorno pronto' do
      expect(problemas(retorno)).to eq([])
    end

    it 'a mensagem só com gatilho de card', :aggregate_failures do
      ligar_mensagens(account)
      account.enable_features!('automacao_gatilhos')
      com_mensagem = retorno(envio: { 'mensagem' => ['Oi'] })
      no_card = { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [com_mensagem] }

      expect(problemas(com_mensagem)).to eq([I18n.t('autonomia.automacao.receita.retorno_mensagem_sem_card', passo: 'r1')])
      expect(Autonomia::Automacao::Receita.new(no_card, conta: account, account_user: account.account_users.find_by(user: admin)).problemas)
        .to eq([])
    end

    it 'recusa pessoa e time de outra conta, valor desconhecido e mensagem sem a flag', :aggregate_failures do
      outra = create(:account)
      de_fora = create(:user, account: outra)
      time_de_fora = create(:team, account: outra)

      expect(problemas(retorno(para: { 'quem' => 'pessoas', 'pessoas' => [de_fora.id] })).join).to include(de_fora.id.to_s)
      expect(problemas(retorno(para: { 'quem' => 'time', 'time' => time_de_fora.id })).join).to include(time_de_fora.id.to_s)
      expect(problemas(retorno(titulo: [{ '$valor' => 'contato.inventado' }]))).not_to be_empty
      desligado = I18n.t('autonomia.automacao.receita.passo_desligado', passo: 'r1')
      expect(problemas(retorno(envio: { 'mensagem' => ['Oi'] }))).to include(desligado)
    end

    # Funções (parecer G3): quem salva precisa poder criar retorno, senão a automação pausaria na 1ª rodada.
    it 'recusa quem não pode criar retorno, no EE' do
      skip 'só no EE' unless ChatwootApp.enterprise?

      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_view crm_manage_pipelines])
      vinculo = atendente.account_users.find_by(account: account)
      vinculo.update!(custom_role: funcao)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [retorno] }

      expect(Autonomia::Automacao::Receita.new(receita, conta: account, account_user: vinculo).problemas)
        .to eq([I18n.t('autonomia.automacao.receita.sem_criar_retorno', passo: 'r1')])
    end

    it 'o esquema recusa pessoas vazias e envio sem mensagem', :aggregate_failures do
      receita = ->(passo) { { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] } }

      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(retorno))).to be(true)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(retorno(para: { 'quem' => 'pessoas', 'pessoas' => [] }))))
        .to be(false)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(retorno(envio: {})))).to be(false)
    end

    it 'o esquema pede daqui ou quando, nunca os dois, e confere o dia e a hora (G57)', :aggregate_failures do
      valido = ->(passo) { Autonomia::Automacao::Receita.esquema_valido?({ 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }) }
      sem_daqui = retorno.except('daqui')

      expect(valido.call(sem_daqui.merge('quando' => { 'dia' => 'hoje' }))).to be(true)
      expect(valido.call(sem_daqui.merge('quando' => { 'dia' => 'amanha', 'hora' => 23 }))).to be(true)
      expect(valido.call(sem_daqui)).to be(false)
      expect(valido.call(retorno.merge('quando' => { 'dia' => 'hoje' }))).to be(false)
      expect(valido.call(sem_daqui.merge('quando' => { 'dia' => 'hoje', 'hora' => 24 }))).to be(false)
      expect(valido.call(sem_daqui.merge('quando' => { 'dia' => 'ontem' }))).to be(false)
    end
  end
end
