require 'rails_helper'

RSpec.describe Crm::InboxSettings::PipelineLinkSyncer do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }

  def configurar(pipeline:, stage:, crm_enabled: true, auto_create_card: true)
    setting = account.crm_inbox_settings.find_or_initialize_by(inbox: inbox)
    setting.update!(
      crm_enabled: crm_enabled,
      auto_create_card: auto_create_card,
      default_pipeline_id: pipeline&.id,
      default_stage_id: stage&.id
    )
    setting
  end

  def vinculo_de(pipeline)
    account.crm_pipeline_inboxes.find_by(pipeline_id: pipeline.id, inbox_id: inbox.id)
  end

  it 'cria o vínculo funil↔caixa que o CardSyncer exige' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    setting = configurar(pipeline: pipeline, stage: stage)

    described_class.new(inbox_setting: setting, user: admin).perform

    vinculo = vinculo_de(pipeline)
    expect(vinculo).to be_present
    expect(vinculo.default_stage_id).to eq(stage.id)
    expect(vinculo.auto_create_card).to be(true)
    expect(vinculo.created_by_id).to eq(admin.id)
  end

  it 'atualiza o vínculo que já existe, em vez de criar outro' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    outra_etapa = create_crm_stage(account: account, pipeline: pipeline, name: 'Qualificação')
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: false)

    setting = configurar(pipeline: pipeline, stage: outra_etapa)
    described_class.new(inbox_setting: setting, user: admin).perform

    expect(account.crm_pipeline_inboxes.where(inbox_id: inbox.id).count).to eq(1)
    expect(vinculo_de(pipeline).default_stage_id).to eq(outra_etapa.id)
    expect(vinculo_de(pipeline).auto_create_card).to be(true)
  end

  it 'respeita a caixa que alimenta outro funil de propósito, quando não houve troca' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Suporte')
    account.crm_pipeline_inboxes.create!(pipeline: outro_funil, inbox: inbox, default_stage: outra_etapa, auto_create_card: true)

    setting = configurar(pipeline: pipeline, stage: stage)
    described_class.new(inbox_setting: setting, user: admin, pipeline_trocado: false).perform

    expect(vinculo_de(outro_funil).auto_create_card).to be(true)
    expect(vinculo_de(pipeline).auto_create_card).to be(true)
  end

  it 'na troca de funil, liga no novo e desliga no antigo, sem apagar o vínculo' do
    antigo, etapa_antiga = create_crm_pipeline(account: account, user: admin, name: 'Funil antigo')
    novo, etapa_nova = create_crm_pipeline(account: account, user: admin, name: 'Funil novo')
    account.crm_pipeline_inboxes.create!(pipeline: antigo, inbox: inbox, default_stage: etapa_antiga, auto_create_card: true)

    setting = configurar(pipeline: novo, stage: etapa_nova)
    described_class.new(inbox_setting: setting, user: admin, pipeline_trocado: true).perform

    expect(vinculo_de(novo).auto_create_card).to be(true)
    expect(vinculo_de(antigo)).to be_present
    expect(vinculo_de(antigo).auto_create_card).to be(false)
  end

  it 'desligar o CRM na caixa para a criação automática em todos os funis' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true)

    setting = configurar(pipeline: pipeline, stage: stage, crm_enabled: false, auto_create_card: false)
    described_class.new(inbox_setting: setting, user: admin).perform

    expect(vinculo_de(pipeline).auto_create_card).to be(false)
  end

  it 'desmarcar a criação automática desliga o vínculo, mantendo o funil padrão' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    setting = configurar(pipeline: pipeline, stage: stage, auto_create_card: false)

    described_class.new(inbox_setting: setting, user: admin).perform

    expect(vinculo_de(pipeline)).to be_present
    expect(vinculo_de(pipeline).auto_create_card).to be(false)
  end

  # Dois salvamentos simultâneos da mesma caixa: o segundo esbarra no índice
  # único e precisa reaproveitar o vínculo recém-criado, não estourar 500.
  it 'aproveita o vínculo criado por outro salvamento simultâneo' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    setting = configurar(pipeline: pipeline, stage: stage)
    syncer = described_class.new(inbox_setting: setting, user: admin)

    chamadas = 0
    allow(account.crm_pipeline_inboxes).to receive(:find_by).and_wrap_original do |original, *args|
      chamadas += 1
      # Na primeira busca finge que não existe, e cria o vínculo por fora: é o
      # que a requisição concorrente teria feito no meio do caminho.
      if chamadas == 1
        account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: false)
        nil
      else
        original.call(*args)
      end
    end
    allow(setting.account).to receive(:crm_pipeline_inboxes).and_return(account.crm_pipeline_inboxes)

    expect { syncer.perform }.not_to raise_error
    expect(account.crm_pipeline_inboxes.where(inbox_id: inbox.id).count).to eq(1)
    expect(vinculo_de(pipeline).auto_create_card).to be(true)
  end

  it 'não cria vínculo quando a caixa não tem funil padrão' do
    setting = configurar(pipeline: nil, stage: nil)

    described_class.new(inbox_setting: setting, user: admin).perform

    expect(account.crm_pipeline_inboxes.where(inbox_id: inbox.id)).to be_empty
  end
end
