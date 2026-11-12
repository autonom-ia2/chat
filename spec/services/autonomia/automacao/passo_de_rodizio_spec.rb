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
