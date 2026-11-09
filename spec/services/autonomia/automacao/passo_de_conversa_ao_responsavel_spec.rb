require 'rails_helper'

# G66 (#2843, decisão 14): o passo "passar a conversa para o responsável do card" de ponta a ponta. A troca do dono do
# card não mexe na conversa; o passo a passa a quem cuida do card agora, pelo mesmo pedido do "Atribuir", como quem ligou.
RSpec.describe Autonomia::Automacao::PassoDeConversaAoResponsavel, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Paula') }
  let(:julia) { create(:user, account: account, role: :agent, name: 'Júlia') }
  let(:renata) { create(:user, account: account, role: :agent, name: 'Renata') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin, julia, renata]) }
  let(:contato) { account.contacts.create!(name: 'Maria', phone_number: '+5511987650066') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato, assignee: julia) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, inbox: inbox, contact: contato,
                              primary_conversation: conversa, title: 'Proposta da Maria', owner: julia)
  end
  let(:gatilho) { { 'tipo' => 'card.responsavel_mudou' } }
  let(:passo) { { 'id' => 'conversa', 'tipo' => 'conversa_ao_responsavel' } }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def rodar(alvo = card, por: admin)
    definicao = automacao_ligada(account, por, [passo], gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: 'card.responsavel_mudou').call
    end
    Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  it 'a Paula troca o dono do card: a conversa segue com a Júlia até o passo, e o passo a passa para a Renata', :aggregate_failures do
    card.update!(owner: renata)
    expect(conversa.reload.assignee).to eq(julia)

    execucao = rodar

    expect(conversa.reload).to have_attributes(assignee_id: renata.id, ai_assignee_id: nil)
    expect(registros(execucao)).to eq([['conversa', 'ok', nil]])
    registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao)
    expect(registro.dados).to include('responsavel_id' => renata.id, 'trocou' => true,
                                      'acao' => described_class::ACAO, 'codigo' => 200)
    expect(Autonomia::Guide::Execucao.find(registro.dados['caderno_id']).user).to eq(admin)
  end

  it 'a conversa já está com o responsável: segue sem pedir nada', :aggregate_failures do
    execucao = rodar

    expect(conversa.reload.assignee).to eq(julia)
    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao).dados).to eq('responsavel_id' => julia.id, 'trocou' => false)
  end

  it 'o card sem responsável: pula, e a conversa fica com quem estava', :aggregate_failures do
    card.update!(owner: nil)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[conversa pulado card_sem_responsavel]])
    expect(conversa.reload.assignee).to eq(julia)
  end

  it 'o responsável não está na caixa da conversa: pula sem passar a quem não a vê', :aggregate_failures do
    de_fora = create(:user, account: account, role: :agent, name: 'Bia')
    card.update!(owner: de_fora)

    execucao = rodar

    expect(registros(execucao)).to eq([%w[conversa pulado responsavel_nao_ve_a_conversa]])
    expect(conversa.reload.assignee).to eq(julia)
  end

  it 'o card sem conversa: pula com sem_conversa', :aggregate_failures do
    sem_conversa = account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, contact: contato,
                                             title: 'Sem conversa', owner: renata)

    execucao = rodar(sem_conversa)

    expect(registros(execucao)).to eq([%w[conversa pulado sem_conversa]])
  end

  it 'a conversa com a agente de IA (robô no nome) passa para a pessoa e tira o robô', :aggregate_failures do
    robo = create(:agent_bot, account: account)
    conversa.update!(assignee: nil, ai_assignee: robo)
    card.update!(owner: renata)

    rodar

    expect(conversa.reload).to have_attributes(assignee_id: renata.id, ai_assignee_id: nil)
  end

  it 'quem ligou perde a chave no meio da rodada: a automação pausa e a conversa fica com a Júlia', :aggregate_failures do
    card.update!(owner: renata)
    sem_chave = Autonomia::Automacao::AcoesDoMotor::SemPermissao.new('quem_ligou_sem_permissao')
    allow(Autonomia::Automacao::AcoesDoMotor).to receive(:new).and_wrap_original do |original, **argumentos|
      original.call(**argumentos).tap { |porta| allow(porta).to receive(:conferir!).and_raise(sem_chave) }
    end

    execucao = rodar

    expect(registros(execucao)).to eq([%w[conversa falhou quem_ligou_sem_permissao]])
    expect([execucao.reload.estado, execucao.automacao.ativa]).to eq(['parada', false])
    expect(conversa.reload.assignee).to eq(julia)
  end

  describe 'ao salvar' do
    def problemas(receita) = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

    it 'vale com gatilho de card' do
      expect(problemas('gatilho' => gatilho, 'passos' => [passo])).to be_empty
    end

    it 'com gatilho de conversa, diz que só vale com gatilho de card' do
      expect(problemas('gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo]))
        .to eq([I18n.t('autonomia.automacao.receita.responsavel_so_com_card', passo: 'conversa')])
    end

    it 'o esquema aceita o passo só com id e tipo' do
      expect(Autonomia::Automacao::Receita.esquema_valido?('gatilho' => gatilho, 'passos' => [passo])).to be(true)
      expect(Autonomia::Automacao::Receita.esquema_valido?('gatilho' => gatilho, 'passos' => [passo.merge('pessoa_id' => 1)])).to be(false)
    end
  end
end
