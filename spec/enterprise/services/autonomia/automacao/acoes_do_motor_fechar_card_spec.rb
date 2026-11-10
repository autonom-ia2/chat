require 'rails_helper'

# G25 (#2650): o passo "fechar o card" pela mesma porta da tela (POST crm/cards/:id/close, Crm::Cards::Closer), com a
# permissão de quem ligou. Ganho sem valor mantém o valor do card; perdido leva o motivo; é ação de funil, então sem a
# chave de funis a automação pausa (#2633). Fica em spec/enterprise: a função personalizada é EE.
RSpec.describe Autonomia::Automacao::AcoesDoMotor, :aggregate_failures, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL',
                              value_cents: 250_000, inbox: conversa.inbox, primary_conversation: conversa, contact: conversa.contact)
  end
  let(:dono) { pessoa_com(base) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def base = %w[automation_manage crm_manage_pipelines crm_view crm_manage_cards conversation_manage]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: conversa.inbox)
    user
  end

  # O passo de verdade: o card do gatilho de card (`$valor card.id`).
  def fechar(corpo, card_id = { '$valor' => 'card.id' })
    { 'id' => 'f1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/close', 'descricao' => 'Fechar o card',
      'caminho' => { 'id' => card_id }, 'corpo' => corpo }
  end

  def rodar(passos)
    gatilho = { 'tipo' => 'card.criado', 'funil_id' => funil_e_etapa.first.id }
    definicao = automacao_ligada(account, dono, passos, gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.criado').call
    end
    definicao.execucoes.order(:id).last
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  it 'fecha como ganho sem valor: mantém o valor do card, e a atividade diz que foi a automação' do
    execucao = rodar([fechar('result' => 'won')])

    expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['f1', 'ok', nil]]])
    expect([card.reload.status, card.value_cents]).to eq(%w[won] + [250_000])
    atividade = card.activities.order(:id).last
    expect(atividade.event_type).to eq('won')
    expect(atividade.payload.slice('by', 'origem', 'automacao_id'))
      .to eq('by' => 'automacao', 'origem' => 'livre', 'automacao_id' => execucao.automacao_id)
  end

  it 'fecha como perdido com o motivo' do
    execucao = rodar([fechar('result' => 'lost', 'lost_reason' => 'Preço')])

    expect(execucao.reload.estado).to eq('concluida')
    expect([card.reload.status, card.lost_reason]).to eq(%w[lost Preço])
  end

  # No gatilho de card, quem perde a chave pausa já no começo (Acesso, sem_permissao_funil); o motor reconfere a chave no
  # passo, então aqui o gatilho é de conversa, com o id do card escrito.
  it 'sem a chave de funis, pausa sem fechar o card' do
    definicao = automacao_ligada(account, dono, [fechar({ 'result' => 'won' }, card.id)])
    AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base - ['crm_manage_pipelines'])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end

    expect(registros(definicao.execucoes.last)).to eq([%w[f1 falhou sem_chave_de_funis]])
    expect(card.reload.status).to eq('open')
  end
end
