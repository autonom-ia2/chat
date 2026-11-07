require 'rails_helper'

# #2633: a ação de funil (recurso crm/) pede a chave de funis (crm_manage_pipelines ou crm_admin) de quem ligou, como no
# salvar, e o motor a reconfere a cada execução. Quem perde a chave depois de salvar pausa a automação no passo de
# funil, sem mexer no card; o passo fora do funil segue. Fica em spec/enterprise: a função personalizada é EE.
RSpec.describe Autonomia::Automacao::AcoesDoMotor, :aggregate_failures, :automacao_motor do
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

  def renomear_card(id, titulo = 'Renomeado', card_id: card.id)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Renomear o card',
      'caminho' => { 'id' => card_id }, 'corpo' => { 'title' => titulo } }
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

  it 'perdeu a chave entre dois passos de funil da mesma rodada: o segundo pausa' do
    definicao = automacao_ligada(account, dono, [renomear_card('c1'), renomear_card('c2', 'Segundo')])
    allow(Autonomia::Automacao::PassoDeAcao).to receive(:new).and_wrap_original do |original, **args|
      tirar('crm_manage_pipelines') if args[:passo]['id'] == 'c2'
      original.call(**args)
    end

    execucao = rodar(definicao)

    expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [['c1', 'ok', nil], %w[c2 falhou sem_chave_de_funis]]])
    expect([definicao.reload.ativa, card.reload.title]).to eq([false, 'Renomeado'])
  end

  it 'sem a chave, pausa antes de montar o pedido, mesmo quando o passo pularia por falta de valor' do
    definicao = automacao_ligada(account, dono, [renomear_card('c1')])
    tirar('crm_manage_pipelines')
    execucao = create(:autonomia_automacao_execucao, versao: definicao.versao_ativa, alvo: conversa)
    passo = renomear_card('c1', card_id: { '$valor' => 'conversa.id' })
    valores = instance_double(Autonomia::Automacao::Valores, ler: nil)

    resultado = Autonomia::Automacao::PassoDeAcao.new(execucao: execucao, passo: passo, valores: valores,
                                                      acesso: Autonomia::Automacao::Acesso.new(definicao)).executar

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'sem_chave_de_funis'])
  end

  it 'crm_admin vale pela chave de funis' do
    definicao = automacao_ligada(account, dono, [renomear_card('c1')])
    AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base - ['crm_manage_pipelines'] + ['crm_admin'])

    expect(rodar(definicao).reload.estado).to eq('concluida')
  end
end
