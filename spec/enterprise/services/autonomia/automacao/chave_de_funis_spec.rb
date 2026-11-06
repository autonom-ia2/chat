require 'rails_helper'

# #2633: a ação de funil (recurso crm/) pede a chave de funis (crm_manage_pipelines ou crm_admin) de quem ligou, como no
# salvar, e o motor a reconfere a cada execução. Quem perde a chave depois de salvar pausa a automação no passo de
# funil, sem mexer no card; o passo fora do funil segue. Fica em spec/enterprise: a função personalizada é EE.
RSpec.describe 'Automação livre: chave de funis reconferida a cada execução (#2633)', :aggregate_failures, :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL',
                              inbox: conversa.inbox, primary_conversation: conversa, contact: conversa.contact)
  end
  let(:dono) { pessoa_com(base) }

  before { ligar_motor(account) }

  after { Current.reset }

  def base = %w[automation_manage crm_manage_pipelines crm_view crm_manage_cards conversation_manage]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: conversa.inbox)
    user
  end

  def renomear_card(id)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Renomear o card',
      'caminho' => { 'id' => card.id }, 'corpo' => { 'title' => 'Renomeado' } }
  end

  def tirar(chave) = AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base - [chave])

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def rodar(definicao)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end
    definicao.execucoes.order(:id).last
  end

  it 'com a chave de funis, a ação de funil roda' do
    execucao = rodar(automacao_ligada(account, dono, [renomear_card('c1')]))

    expect([execucao.reload.estado, registros(execucao), card.reload.title]).to eq(['concluida', [['c1', 'ok', nil]], 'Renomeado'])
  end

  it 'perdeu a chave de funis depois de salvar: pausa no passo de funil, sem mexer no card' do
    definicao = automacao_ligada(account, dono, [prioridade_passo('p1', 'high'), renomear_card('c1')])
    tirar('crm_manage_pipelines')

    execucao = rodar(definicao)

    expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [['p1', 'ok', nil], %w[c1 falhou sem_chave_de_funis]]])
    expect([definicao.reload.ativa, card.reload.title, conversa.reload.priority]).to eq([false, 'Pedido', 'high'])
  end

  it 'sem a chave de funis, o passo fora do funil segue' do
    definicao = automacao_ligada(account, dono, [prioridade_passo('p1', 'high')])
    tirar('crm_manage_pipelines')

    execucao = rodar(definicao)

    expect([execucao.reload.estado, conversa.reload.priority]).to eq(%w[concluida high])
  end

  it 'crm_admin vale pela chave de funis' do
    definicao = automacao_ligada(account, dono, [renomear_card('c1')])
    AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base - ['crm_manage_pipelines'] + ['crm_admin'])

    expect(rodar(definicao).reload.estado).to eq('concluida')
  end
end
