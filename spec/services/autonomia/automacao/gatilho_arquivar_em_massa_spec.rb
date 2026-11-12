require 'rails_helper'

# F6.4 (#2499): o arquivamento em massa não dispara "saiu da etapa" nem "entrou na etapa". Arquivar cards em lote (a
# barra da Lista do CRM) grava a atividade `archive`, que o emissor do CRM despacha como crm.card.archived, fora dos
# gatilhos de etapa. Arquivar o funil levando os cards abertos para outro grava as atividades `move` em lote
# (insert_all), sem o emissor: é a conta reorganizando funis, não o cliente avançando. O mover em lote, ao contrário,
# passa pelo Mover e dispara: é o controle de que a escuta está ouvindo.
RSpec.describe 'Automação livre: arquivar em massa não dispara a etapa', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:account_user) { account.account_users.find_by!(user: admin) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 1) }
  let(:destino) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda').last }
  let(:cards) do
    Array.new(2) do |indice|
      conversa = create(:conversation, account: account, status: :open)
      account.crm_cards.create!(pipeline: funil, stage: novo, title: "Pedido #{indice}", currency: 'BRL',
                                primary_conversation: conversa, contact: conversa.contact)
    end
  end
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    cards
    proposta
    destino
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila: o job enfileirado dentro de outro só roda depois dele.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  def de_card(tipo, etapa)
    automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => tipo, 'etapa_id' => etapa.id })
  end

  def em_lote(acao, payload = {})
    Crm::Cards::BulkAction.new(account: account, user: admin, account_user: account_user, ids: cards.map(&:id), action: acao,
                               payload: payload).perform
  end

  it 'arquivar os cards em lote não abre execução de "saiu da etapa"', :aggregate_failures do
    saiu = de_card('card.saiu_da_etapa', novo)

    resultado = em_lote('delete')
    drenar

    expect(resultado[:updated]).to match_array(cards.map(&:id))
    expect(cards.map { |card| card.reload.status }).to all(eq('archived'))
    expect(execucoes.where(automacao: saiu)).to be_empty
  end

  it 'arquivar o funil levando os cards abertos para outro não abre "saiu" nem "entrou"', :aggregate_failures do
    saiu = de_card('card.saiu_da_etapa', novo)
    entrou = de_card('card.entrou_na_etapa', destino)

    Crm::Pipelines::Archiver.new(pipeline: funil, actor: admin, target_stage: destino, new_default: destino.pipeline).perform
    drenar

    expect(cards.map { |card| card.reload.stage_id }).to all(eq(destino.id))
    expect(execucoes.where(automacao: [saiu, entrou])).to be_empty
  end

  # Controle: a mesma automação dispara quando os cards são movidos em lote pelo Mover.
  it 'mover os cards em lote abre uma execução de "saiu da etapa" por card' do
    saiu = de_card('card.saiu_da_etapa', novo)

    em_lote('move', stage_id: proposta.id)
    drenar

    expect(execucoes.where(automacao: saiu).pluck(:alvo_id)).to match_array(cards.map(&:id))
  end
end
