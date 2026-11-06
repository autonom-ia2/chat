require 'rails_helper'

# O passo "criar card" de ponta a ponta (#2414 G4): a automação começa, o executor cria o card na etapa escolhida,
# ligado à conversa (ou ao contato) do alvo, como quem ligou, sem duplicar no mesmo funil.
RSpec.describe Autonomia::Automacao::PassoDeCard, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_e_novo) { create_crm_pipeline(account: account, user: admin) }
  let(:vendas) { vendas_e_novo.first }
  let(:novo) { vendas_e_novo.last }
  let(:melhorias_e_entrada) { create_crm_pipeline(account: account, user: admin, name: 'Melhorias') }
  let(:melhorias) { melhorias_e_entrada.first }
  let(:entrada) { melhorias_e_entrada.last }
  let(:contato) { create(:contact, account: account, name: 'Paulo') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def card_passo(id = 'p1', etapa = entrada) = { 'id' => id, 'tipo' => 'card', 'etapa_id' => etapa.id }

  def rodar(alvo = conversa, passos = [card_passo], chave: 'conversa.resolvida')
    definicao = automacao_ligada(account, admin, passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: chave).call
    end
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def card_vendas
    account.crm_cards.create!(pipeline: vendas, stage: novo, title: 'Pedido', primary_conversation: conversa, contact: contato)
  end

  it 'cria o card na etapa, ligado à conversa, com a marca da automação e quem ligou', :aggregate_failures do
    execucao = rodar

    card = melhorias.cards.sole
    expect(card).to have_attributes(stage_id: entrada.id, contact_id: contato.id, conversation_id: conversa.id, status: 'open')
    expect(Crm::Cards::ConversationCardFinder.new(account: account).all(conversa)).to include(card)
    criacao = Crm::Activity.where(card: card, event_type: 'create').sole
    expect(criacao.payload).to include('by' => 'automacao', 'origem' => 'livre', 'automacao_id' => execucao.automacao_id)
    expect(criacao.actor_id).to eq(admin.id)
    expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao).dados).to include('card_id' => card.id, 'etapa_id' => entrada.id)
  end

  it 'com card aberto em outro funil, cria o de Melhorias e não mexe no de Vendas', :aggregate_failures do
    pedido = card_vendas

    rodar

    expect(melhorias.cards.count).to eq(1)
    expect(pedido.reload).to have_attributes(pipeline_id: vendas.id, stage_id: novo.id, status: 'open')
  end

  it 'com card aberto no mesmo funil, pula sem duplicar e diz qual card já existe', :aggregate_failures do
    rodar
    existente = melhorias.cards.sole

    execucao = rodar

    expect(melhorias.cards.count).to eq(1)
    expect(registros(execucao)).to eq([%w[p1 pulado card_ja_existe]])
    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao).dados).to include('card_id' => existente.id)
  end

  it 'card ganho ou perdido no funil não conta: abre um card novo (o "abrir card de retenção" de novo)' do
    account.crm_cards.create!(pipeline: melhorias, stage: entrada, title: 'Antigo', primary_conversation: conversa, contact: contato,
                              status: :lost)

    expect { rodar }.to change { melhorias.cards.open.count }.from(0).to(1)
  end

  it 'no gatilho de card, liga o card novo à conversa principal do card do gatilho', :aggregate_failures do
    pedido = card_vendas

    execucao = rodar(pedido, chave: 'card.ganho')

    card = melhorias.cards.sole
    expect(card).to have_attributes(conversation_id: conversa.id, contact_id: contato.id)
    expect(registros(execucao)).to eq([['p1', 'ok', nil]])
  end

  it 'no contato, cria o card só do contato, com o nome dele', :aggregate_failures do
    execucao = rodar(contato, chave: 'conversa.resolvida')

    card = melhorias.cards.sole
    expect(card).to have_attributes(contact_id: contato.id, conversation_id: nil, title: 'Paulo')
    expect(registros(execucao)).to eq([['p1', 'ok', nil]])
  end

  it 'contato fora do funil não vira card' do
    account.enable_features!('contato_relacao')
    contato.update!(relacao: :parceiro)

    execucao = rodar

    expect(melhorias.cards).to be_empty
    expect(registros(execucao)).to eq([%w[p1 pulado fora_do_funil]])
  end

  it 'etapa apagada depois de salvar: pula com o motivo' do
    definicao = automacao_ligada(account, admin, [card_passo])
    entrada.destroy!

    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end

    expect(registros(execucao)).to eq([%w[p1 pulado etapa_sumiu]])
  end

  it 'com a flag dos gatilhos de card desligada depois de salvar, para sem criar (rollback)', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [card_passo])
    account.disable_features!('automacao_gatilhos')

    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    end

    expect(melhorias.cards).to be_empty
    expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 pulado card_desligado]]])
  end

  describe 'ao salvar (Receita)' do
    def problemas(passos)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    it 'aceita a etapa da conta' do
      expect(problemas([card_passo])).to be_empty
    end

    it 'recusa a etapa de outra conta' do
      outra = create(:account)
      _, de_fora = create_crm_pipeline(account: outra, user: create(:user, account: outra))

      expect(problemas([card_passo('p1', de_fora)])).to eq([I18n.t('autonomia.automacao.receita.etapa_do_card_de_fora', passo: 'p1', id: de_fora.id)])
    end

    it 'recusa sem a flag dos gatilhos de card' do
      account.disable_features!('automacao_gatilhos')

      expect(problemas([card_passo])).to eq([I18n.t('autonomia.automacao.receita.card_desligado', passo: 'p1')])
    end
  end
end
