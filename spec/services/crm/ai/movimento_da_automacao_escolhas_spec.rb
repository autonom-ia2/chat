require 'rails_helper'

# O que conta como escolha da pessoa para a IA do funil (Evaluator e FecharCard). Pega o `move` com `motivo` (etapa de
# entrada do pedido da API, #2501; funil arquivado; etapa apagada) travando a IA, e o filtro largo demais que tiraria
# também o fechamento aceito da sugestão da IA, que grava `motivo` e é da pessoa.
RSpec.describe Crm::Ai::MovimentoDaAutomacao do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL') }

  def atividade(event_type, payload)
    Crm::Activity.create!(account_id: account.id, card_id: card.id, actor_type: 'user', actor_id: admin.id, event_type: event_type,
                          payload: payload)
  end

  def escolhas = described_class.escolhas_da_pessoa(Crm::Activity.where(card_id: card.id))

  it 'tira o movimento da automação e o movimento com motivo; fica o da pessoa e o fechamento aceito com motivo', :aggregate_failures do
    Crm::Activity.where(card_id: card.id).delete_all
    da_pessoa = atividade('move', { to_stage_id: 1 })
    fechamento_aceito = atividade('lost', { sugestao_da_ia: 9, motivo: 'adiou' })
    atividade('move', { to_stage_id: 2, motivo: Crm::Cards::EtapaDeEntrada::SEM_ETAPA })
    atividade('move', { to_stage_id: 3, motivo: Crm::Pipelines::Archiver::MOTIVO })
    atividade('move', { to_stage_id: 4, by: 'automacao', origem: 'livre', automacao_id: 5 })

    expect(escolhas).to contain_exactly(da_pessoa, fechamento_aceito)
  end
end
