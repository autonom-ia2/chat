require 'rails_helper'

# #2414 F1.4: mover pela automação um contato sem card cria o card na etapa certa, sem duplicar.
RSpec.describe Autonomia::Automacao::CardNaEtapa do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }
  let(:conversation) { create(:conversation, account: account).reload }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def card_na_etapa(etapa = proposta)
    described_class.new(conversation: conversation, stage: etapa).perform
  end

  it 'cria o card na etapa quando a conversa não tem nenhum, e na segunda vez não duplica' do
    expect { card_na_etapa }.to change(Crm::Card, :count).by(1)
    expect { card_na_etapa }.not_to change(Crm::Card, :count)

    card = Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)
    expect(card).to have_attributes(pipeline_id: pipeline.id, stage_id: proposta.id, contact_id: conversation.contact_id)
  end

  it 'move o card que já existe, sem criar outro' do
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                                     primary_conversation: conversation, title: 'Lead')

    expect { card_na_etapa }.not_to change(Crm::Card, :count)
    expect(card.reload.stage_id).to eq(proposta.id)
  end

  it 'não mexe em card ganho nem cria outro no lugar (isso é a ação "criar card")' do
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                                     primary_conversation: conversation, title: 'Lead', status: :won)

    expect { card_na_etapa }.not_to change(Crm::Card, :count)
    expect(card.reload.stage_id).to eq(stage.id)
  end

  it 'roda as automações de entrada da etapa no card criado' do
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: proposta, name: 'Entrou',
                                                      trigger_event: :on_enter, created_by: user)
    automacao.steps.create!(account: account, position: 0, delay_seconds: 0, action_type: :assign_owner,
                            action_config: { owner_id: user.id })

    card = card_na_etapa

    expect(card.reload.owner_id).to eq(user.id)
  end

  it 'ignora etapa de outra conta' do
    outra = create(:account)
    _, etapa_de_fora = create_crm_pipeline(account: outra, user: create(:user, account: outra))

    expect { card_na_etapa(etapa_de_fora) }.not_to change(Crm::Card, :count)
  end

  describe 'pela regra de automação (crm_move_card_stage)' do
    let(:rule) { create(:automation_rule, account: account, actions: [{ action_name: 'crm_move_card_stage', action_params: [proposta.id] }]) }

    def rodar_regra
      AutomationRules::ActionService.new(rule, account, conversation).perform
    end

    it 'com a flag automacao_fundacao, contato sem card ganha o card na etapa' do
      account.enable_features!('automacao_fundacao')

      expect { rodar_regra }.to change(Crm::Card, :count).by(1)
    end

    it 'sem a flag, faz o de antes: sem card, nada acontece' do
      expect { rodar_regra }.not_to change(Crm::Card, :count)
    end
  end
end
