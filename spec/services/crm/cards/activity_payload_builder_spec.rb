require 'rails_helper'

RSpec.describe Crm::Cards::ActivityPayloadBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  # A timeline mostra "Reunião passou para <nome>": o nome de quem recebeu vem resolvido em labels.to_user_id.
  it 'resolve o nome de quem recebeu a reunião reatribuída' do
    activity = Crm::Activity.create!(account: account, card: world.card, actor_type: 'system', event_type: 'meeting_host_reassigned',
                                     payload: { 'meeting_id' => 1, 'from_user_id' => 999_999, 'to_user_id' => world.host.id })

    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first, activities: [activity]).perform

    expect(payload.first[:labels]).to eq('to_user_id' => world.host.name)
  end

  # Etapa apagada: o histórico continua com o nome dela, gravado na atividade `move` (Crm::Cards::Mover).
  it 'mostra o nome gravado da etapa que não existe mais' do
    pipeline, inicio = create_crm_pipeline(account: account, user: admin)
    proposta = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    card = account.crm_cards.create!(pipeline: pipeline, stage: inicio, title: 'Pedido')
    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: proposta, automation_context: { skip_automations: true }).perform
    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: inicio, automation_context: { skip_automations: true }).perform
    Crm::PipelineStages::Destroyer.new(stage: proposta).perform

    activities = card.activities.where(event_type: 'move').order(:id).to_a
    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first, activities: activities).perform

    expect(payload.map { |item| item[:labels] }).to eq(
      [{ 'from_stage_id' => 'Novo Lead', 'to_stage_id' => 'Proposta' }, { 'from_stage_id' => 'Proposta', 'to_stage_id' => 'Novo Lead' }]
    )
  end

  # #2509: o movimento feito por uma automação traz o nome dela, por origem, e se a pessoa pode abri-la.
  describe 'atividade feita por uma automação' do
    let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
    let(:card) { account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Pedido') }

    def mover_por(automacao, etapa)
      Crm::Cards::Mover.new(card: card, actor: admin, target_stage: etapa, automation_context: { skip_automations: true },
                            automacao: automacao).perform
    end

    def payload_para(account_user)
      activities = card.activities.where(event_type: 'move').order(:id).to_a
      described_class.new(account: account, user: account_user.user, account_user: account_user, activities: activities).perform
    end

    it 'resolve o nome da Automação livre, da regra e da automação de etapa' do
      account.enable_features!('automacao_editor', 'automations')
      livre = create(:autonomia_automacao, account: account, nome: 'Boas-vindas')
      regra = create(:automation_rule, account: account, name: 'Regra do lead')
      proposta = create_crm_stage(account: account, pipeline: pipeline_and_stage.first, name: 'Proposta')
      da_etapa = account.crm_stage_automations.create!(pipeline: pipeline_and_stage.first, stage: proposta, name: 'Entrou na proposta',
                                                       trigger_event: :on_enter, created_by: admin)
      mover_por({ origem: 'livre', id: livre.id }, proposta)
      mover_por({ origem: 'regra', id: regra.id }, pipeline_and_stage.last)
      mover_por({ origem: 'etapa', id: da_etapa.id }, proposta)

      automacoes = payload_para(admin.account_users.first).pluck(:automacao)

      expect(automacoes).to eq(
        [{ origem: 'livre', id: livre.id, nome: 'Boas-vindas', pode_abrir: true },
         { origem: 'regra', id: regra.id, nome: 'Regra do lead', pode_abrir: true },
         { origem: 'etapa', id: da_etapa.id, nome: 'Entrou na proposta', pode_abrir: false }]
      )
    end

    it 'não abre a automação para quem não vê as automações, e o movimento de pessoa fica sem automação' do
      account.enable_features!('automacao_editor')
      agente = create(:user, account: account, role: :agent)
      livre = create(:autonomia_automacao, account: account, nome: 'Boas-vindas')
      proposta = create_crm_stage(account: account, pipeline: pipeline_and_stage.first, name: 'Proposta')
      mover_por({ origem: 'livre', id: livre.id }, proposta)
      mover_por(nil, pipeline_and_stage.last)

      automacoes = payload_para(agente.account_users.first).pluck(:automacao)

      expect(automacoes).to eq([{ origem: 'livre', id: livre.id, nome: 'Boas-vindas', pode_abrir: false }, nil])
    end

    it 'não lê a automação de outra conta' do
      alheia = create(:autonomia_automacao, nome: 'De outra conta')
      proposta = create_crm_stage(account: account, pipeline: pipeline_and_stage.first, name: 'Proposta')
      mover_por({ origem: 'livre', id: alheia.id }, proposta)

      automacoes = payload_para(admin.account_users.first).pluck(:automacao)

      expect(automacoes).to eq([{ origem: 'livre', id: alheia.id, nome: nil, pode_abrir: false }])
    end
  end

  # #2114: SuperAdmin é subclasse de User; a ação dele aparece com o nome, como a de qualquer pessoa.
  it 'mostra o nome do super admin que mexeu no card' do
    super_admin = create(:super_admin, name: 'Admin da Plataforma')
    create(:account_user, account: account, user: super_admin, role: :administrator)
    Crm::ActivityLogger.new(card: world.card, actor: super_admin, event_type: 'archive').perform

    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first,
                                  activities: world.card.activities.where(event_type: 'archive').to_a).perform

    expect(payload.first).to include(actor_type: 'user', actor_id: super_admin.id, actor_name: 'Admin da Plataforma')
  end
end
