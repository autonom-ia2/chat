require 'rails_helper'

# #2750, revisão: a troca em lote pela Lista do CRM (Crm::Cards::BulkAction) grava card a card, e o emissor do CRM
# pergunta à Automação livre (Escuta.assinante?) no after_commit de cada um, dentro do pedido. No lote, a pergunta e a
# conta do emissor saem uma vez (EmLote): 3 ou 9 cards fazem as mesmas consultas. O despacho continua um por card.
RSpec.describe 'Automação livre: o gate do emissor na troca em lote', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:destino) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 1) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => destino.id })
  end

  after { Current.reset }

  def novos_cards(quantos)
    Array.new(quantos) { |indice| account.crm_cards.create!(pipeline: funil, stage: novo, title: "Card #{indice}", currency: 'BRL') }
  end

  # As consultas do gate (a tabela das automações) e as leituras da conta pelo emissor (Account.find_by), enquanto
  # o bloco roda. A conta que o card carrega para a tela (PayloadBuilder) é outra leitura e não entra.
  def consultas_do_gate_e_da_conta(&)
    contadas = { gate: 0, conta: 0 }
    contar = ->(*, payload) { contadas[:gate] += 1 if payload[:sql].to_s.include?('FROM "autonomia_automacoes"') }
    allow(Account).to receive(:find_by).and_wrap_original do |original, *args, **opcoes|
      contadas[:conta] += 1
      original.call(*args, **opcoes)
    end
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    contadas
  end

  def mover_em_lote(cards)
    account_user = account.account_users.find_by(user: admin)
    Crm::Cards::BulkAction.new(account: account, user: admin, account_user: account_user, ids: cards.map(&:id),
                               action: 'move', payload: { stage_id: destino.id }).perform
  end

  def despachos = enqueued_jobs.count { |job| job[:job] == EventDispatcherJob }

  it '3 e 9 cards fazem as mesmas consultas do gate e da conta; cada card ainda despacha', :aggregate_failures do
    poucos = novos_cards(3)
    muitos = novos_cards(9)
    clear_enqueued_jobs

    com_poucos = consultas_do_gate_e_da_conta { expect(mover_em_lote(poucos)[:updated].size).to eq(3) }
    expect(despachos).to eq(3)
    com_muitos = consultas_do_gate_e_da_conta { expect(mover_em_lote(muitos)[:updated].size).to eq(9) }

    expect(com_poucos[:gate]).to be_positive
    expect(com_muitos).to eq(com_poucos)
    expect(despachos).to eq(12)
  end

  it 'fora do lote nada é lembrado: cada card pergunta de novo', :aggregate_failures do
    um, dois, tres = novos_cards(3)
    mover = ->(card) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: destino).perform }

    com_um = consultas_do_gate_e_da_conta { mover.call(um) }
    com_dois = consultas_do_gate_e_da_conta { [dois, tres].each(&mover) }

    expect(com_um[:gate]).to be_positive
    expect(com_dois[:gate]).to eq(2 * com_um[:gate])
  end

  it 'sem automação do evento, o lote não despacha', :aggregate_failures do
    Autonomia::Automacao::Definicao.where(account: account).update_all(ativa: false) # rubocop:disable Rails/SkipsModelValidations
    cards = novos_cards(3)
    clear_enqueued_jobs

    mover_em_lote(cards)

    expect(despachos).to eq(0)
  end
end
