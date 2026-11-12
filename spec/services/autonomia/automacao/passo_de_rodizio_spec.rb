require 'rails_helper'

# #2502: o passo "atribuir em rodízio" de ponta a ponta. Quem escolhe é o rodízio da própria caixa (só quem está
# online); a troca vira o pedido do "Atribuir", como quem ligou. O ensaio só lê e nunca gira a fila.
RSpec.describe Autonomia::Automacao::PassoDeRodizio, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Paula') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [ana, bia]) }
  let(:contato) { account.contacts.create!(name: 'Maria', phone_number: '+5511987650502') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:time) { create(:team, account: account, name: 'Vendas') }
  let(:passo) { { 'id' => 'p1', 'tipo' => 'rodizio' } }

  before do
    ligar_motor(account)
    inbox.update!(enable_auto_assignment: false)
    conversa
  end

  after { Current.reset }

  def online(*pessoas)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(pessoas.to_h { |pessoa| [pessoa.id.to_s, 'online'] })
  end

  def rodar(passos = [passo])
    definicao = automacao_ligada(account, admin, passos, gatilho: { 'tipo' => 'conversa.criada' })
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa.reload, chave_gatilho: 'conversa.criada').call
    end
    Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  it 'passa a conversa para quem da caixa está online, pelo pedido do Atribuir, como quem ligou', :aggregate_failures do
    online(bia)

    execucao = rodar

    expect(conversa.reload.assignee).to eq(bia)
    expect(registros(execucao)).to eq([['p1', 'ok', nil]])
    registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao)
    expect(registro.dados).to include('responsavel_id' => bia.id, 'acao' => described_class::ACAO, 'codigo' => 200)
    expect(Autonomia::Guide::Execucao.find(registro.dados['caderno_id']).user).to eq(admin)
  end

  it 'com o time, só quem é do time e está online entra no rodízio' do
    create(:team_member, team: time, user: ana)
    online(ana, bia)

    rodar([passo.merge('time_id' => time.id)])

    expect(conversa.reload.assignee).to eq(ana)
  end

  it 'ninguém online: pula, e a conversa fica sem responsável', :aggregate_failures do
    online

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado ninguem_online]])
    expect(conversa.reload.assignee).to be_nil
  end

  it 'o time sem ninguém na caixa: pula sem chamar o rodízio', :aggregate_failures do
    online(ana, bia)
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

    execucao = rodar([passo.merge('time_id' => time.id)])

    expect(registros(execucao)).to eq([%w[p1 pulado ninguem_no_rodizio]])
  end

  it 'a conversa que já tem responsável fica com ele', :aggregate_failures do
    conversa.update!(assignee: ana)
    online(bia)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado conversa_ja_atribuida]])
    expect(conversa.reload.assignee).to eq(ana)
  end

  it 'a conversa resolvida: pula sem chamar o rodízio', :aggregate_failures do
    conversa.update!(status: :resolved)
    online(bia)
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado conversa_resolvida]])
    expect(conversa.reload.assignee).to be_nil
  end

  # O agente de IA fica na mesma coluna do robô (assignee_agent_bot_id, pelo robô espelho dele).
  it 'a conversa com robô ou agente de IA: pula sem chamar o rodízio', :aggregate_failures do
    robo = create(:agent_bot, account: account)
    conversa.update_columns(assignee_agent_bot_id: robo.id, ai_assignee_type: 'AgentBot') # rubocop:disable Rails/SkipsModelValidations
    online(bia)
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado robo_atende]])
    expect(conversa.reload).to have_attributes(assignee_id: nil, assignee_agent_bot_id: robo.id)
  end

  # Revisão: a marca do motor de entrega do CRM (#1454) diz que a Atribuição está segurando a conversa ou esperando o
  # convidado. O rodízio nativo pula; o passo também, senão a troca apagaria a marca e o convite morreria sem aviso.
  it 'a Atribuição segurando a conversa: pula sem chamar o rodízio, e a marca fica', :aggregate_failures do
    Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'robo_pediu', falha: 'ninguem_online')
    conversa.save!
    online(bia)
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado entrega_cuidando]])
    expect(conversa.reload.assignee).to be_nil
    expect(conversa).to be_crm_delivery_pending
  end

  it 'a Atribuição convida alguém enquanto o rodízio escolhia: confere de novo e não passa por cima', :aggregate_failures do
    online(bia)
    allow(AutoAssignment::AgentAssignmentService).to receive(:new).and_wrap_original do |original, **argumentos|
      original.call(**argumentos).tap do |servico|
        allow(servico).to receive(:find_assignee).and_wrap_original do |escolher|
          convidada = Conversation.find(conversa.id)
          Crm::Entrega::Marca.marcar(convidada, modo: Crm::Entrega::Marca::CONVITE, motivo: 'ia_crm', ate: 1.hour.from_now, convidado: ana)
          convidada.save!
          escolher.call
        end
      end
    end

    execucao = rodar

    expect(registros(execucao)).to eq([%w[p1 pulado entrega_cuidando]])
    expect(conversa.reload.assignee).to be_nil
    expect(Crm::Entrega::Marca.dados(conversa)).to include('modo' => Crm::Entrega::Marca::CONVITE, 'convidado_id' => ana.id)
  end

  # O gatilho de card age na conversa principal do card (Contexto#conversa).
  describe 'com gatilho de card' do
    let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }

    around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

    before { account.enable_features!('automacao_gatilhos') }

    def card_com(principal)
      account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, inbox: inbox, contact: contato,
                                primary_conversation: principal, title: 'Proposta da Maria')
    end

    def rodar_no_card(card)
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'card.responsavel_mudou' })
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.responsavel_mudou').call
      end
      Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
    end

    it 'passa a conversa principal do card, sem responsável, para quem está online', :aggregate_failures do
      online(bia)

      execucao = rodar_no_card(card_com(conversa))

      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      expect(conversa.reload.assignee).to eq(bia)
    end

    it 'o card sem conversa principal: pula com sem_conversa' do
      online(bia)

      expect(registros(rodar_no_card(card_com(nil)))).to eq([%w[p1 pulado sem_conversa]])
    end
  end

  describe '.ensaiar' do
    it 'diz entre quem seria, sem girar a fila da caixa', :aggregate_failures do
      expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)
      expect(Redis::Alfred).not_to receive(:lpush)
      create(:team_member, team: time, user: ana)

      expect(described_class.ensaiar(passo, conversa)).to eq(['rodizio', {}])
      expect(described_class.ensaiar(passo.merge('time_id' => time.id), conversa)).to eq(['rodizio', { time: 'Vendas' }])
    end

    it 'diz por que pularia', :aggregate_failures do
      expect(described_class.ensaiar(passo.merge('time_id' => time.id), conversa)).to eq(['ninguem_no_rodizio'])

      conversa.update!(assignee: ana)
      expect(described_class.ensaiar(passo, conversa.reload)).to eq(['conversa_ja_atribuida'])
    end

    it 'diz que a Atribuição está cuidando da conversa' do
      Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'robo_pediu')
      conversa.save!

      expect(described_class.ensaiar(passo, conversa.reload)).to eq(['entrega_cuidando'])
    end

    it 'no ensaio da automação, o passo mostra o rodízio' do
      receita = { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [passo] }
      no = Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos].first

      expect(no).to eq(id: 'p1', tipo: 'rodizio', faria: 'rodizio', dados: {})
    end
  end

  describe '.problemas_ao_salvar' do
    def problemas(receita) = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

    it 'aceita no gatilho de conversa e recusa onde não há conversa ou com time de outra conta', :aggregate_failures do
      outro_time = create(:team)

      expect(problemas({ 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [passo] })).to eq([])
      expect(problemas({ 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [passo.merge('time_id' => outro_time.id)] }))
        .to eq([I18n.t('autonomia.automacao.receita.time_de_fora', passo: 'p1', id: outro_time.id)])
      expect(described_class.problemas_ao_salvar(account, passo, Autonomia::Automacao::Gatilhos::CONTATO))
        .to eq([I18n.t('autonomia.automacao.receita.rodizio_sem_conversa', passo: 'p1')])
    end
  end
end
