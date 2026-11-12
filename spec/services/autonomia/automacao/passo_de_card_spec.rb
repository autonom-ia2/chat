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

  # "Convive" do termo: o card de Melhorias liga à mesma conversa sem virar o assunto atual dela nem desligar o pedido.
  it 'o card do pedido continua o principal da conversa, ligado a ela, mesmo escolhido por uma pessoa', :aggregate_failures do
    pedido = Crm::Cards::Creator.new(account: account, user: admin, conversation: conversa,
                                     params: { pipeline_id: vendas.id, stage_id: novo.id }).perform

    rodar

    melhoria = melhorias.cards.sole
    finder = Crm::Cards::ConversationCardFinder.new(account: account)
    expect(finder.find(conversa)).to eq(pedido)
    expect(finder.all(conversa)).to contain_exactly(pedido, melhoria)
    expect(Crm::CardConversation.find_by!(card: melhoria, conversation: conversa).focused_at).to be_nil
    expect(Crm::CardConversation.find_by!(card: pedido, conversation: conversa)).to have_attributes(is_primary: true)
  end

  it 'sem foco marcado no pedido, ele continua o principal (o card novo não toma o lugar)' do
    pedido = card_vendas

    rodar

    expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversa)).to eq(pedido)
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

  # F6.8 (#2499): a trava de 30 dias do "não é negócio" (#2395) vale também para o card que a automação cria.
  describe 'conversa com card arquivado pela IA como "não é negócio"' do
    def arquivado_pela_ia(motivo: 'fora_do_negocio')
      card = account.crm_cards.create!(pipeline: vendas, stage: novo, title: 'Lixo', primary_conversation: conversa, contact: contato)
      Crm::Cards::Archiver.new(card: card, actor: nil, payload: { by: 'ai', motivo: motivo }).perform
      card
    end

    it 'há menos de 30 dias: pula sem criar, com o motivo no histórico', :aggregate_failures do
      arquivado_pela_ia

      execucao = rodar

      expect(melhorias.cards).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado nao_e_negocio]])
    end

    it 'há mais de 30 dias: cria o card' do
      card = arquivado_pela_ia
      Crm::Activity.where(card: card, event_type: 'archive').update_all(created_at: 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { rodar }.to change { melhorias.cards.count }.from(0).to(1)
    end

    # Só o "fora_do_negocio" trava, como no #2395 (decisão de 30/10): o "duplicado" deixa aberto o card que fica.
    it 'arquivado como repetido (outro motivo da IA): cria o card' do
      arquivado_pela_ia(motivo: 'duplicado')

      expect { rodar }.to change { melhorias.cards.count }.from(0).to(1)
    end

    it 'no alvo contato, o card do contato arquivado assim também pula', :aggregate_failures do
      arquivado_pela_ia

      execucao = rodar(contato)

      expect(melhorias.cards).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado nao_e_negocio]])
    end

    it 'no alvo contato, um card aberto por uma pessoa depois do arquivamento libera' do
      arquivado_pela_ia
      card_vendas

      expect { rodar(contato) }.to change { melhorias.cards.count }.from(0).to(1)
    end

    # G49: o contato vem de um valor (`criado.<passo>`); aqui o valor lido é o id do contato que tem o card arquivado.
    it 'no contato do valor (G49), o card do contato arquivado assim também pula', :aggregate_failures do
      arquivado_pela_ia
      definicao = automacao_ligada(account, admin, [card_passo])
      passo = card_passo.merge('contato' => { '$valor' => 'criado.p0' })
      valores = instance_double(Autonomia::Automacao::Valores, ler: contato.id)
      acesso = Autonomia::Automacao::Acesso.new(definicao)

      resultado = described_class.new(execucao: Autonomia::Automacao::Execucao.new(account: account, automacao: definicao),
                                      passo: passo, alvo: conversa, acesso: acesso, valores: valores).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'nao_e_negocio'])
      expect(melhorias.cards).to be_empty
    end
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
