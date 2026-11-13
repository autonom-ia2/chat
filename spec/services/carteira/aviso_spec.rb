require 'rails_helper'

# E5 (#2898) — o aviso da carteira no sino: "N seguros entraram em renovação hoje". Um por pessoa por dia, com a
# contagem do dia da conta, só no painel, para quem vê contatos e enxerga o funil das renovações. Tudo fictício.
RSpec.describe Carteira::Aviso do
  # 23h30 de 12/11/2026 em São Paulo: no servidor (UTC) já é dia 13.
  let(:agora) { Time.utc(2026, 11, 13, 2, 30) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Renovação') }
  let(:funil) { funil_e_etapa.first }
  let(:config) { create(:carteira_renovacao_config, account: account, pipeline: funil, stage: funil_e_etapa.last) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    admin
  end

  # Um seguro cujo card de renovação nasceu em `quando`.
  def nasceu(numero, quando: Time.current, pessoa: marina)
    criar_apolice(pessoa, numero: numero, fim_vigencia: Date.new(2026, 12, 20)).eventos.create!(tipo: 'card_nasceu', quando: quando)
  end

  def avisar(conta = account, ajustes = config)
    described_class.new(conta, ajustes).entraram
  end

  def avisos
    Notification.where(notification_type: 'carteira_renovacao')
  end

  def texto(aviso)
    I18n.with_locale(:pt_BR) { [aviso.push_message_title, aviso.push_message_body] }
  end

  it 'avisa quem vê contatos e o funil, com quantos seguros entraram em renovação no dia da conta' do
    agente = create(:user, account: account, role: :agent)
    nasceu('EX-000001')
    # Meia-noite de 12/11 em São Paulo: já é hoje. Um minuto antes ainda era ontem.
    nasceu('EX-000002', quando: Time.utc(2026, 11, 12, 3, 0))
    nasceu('EX-000003', quando: Time.utc(2026, 11, 12, 2, 59))

    avisar

    expect(avisos.pluck(:user_id)).to contain_exactly(admin.id, agente.id)
    aviso = avisos.find_by(user: admin).reload
    expect(aviso).to have_attributes(account_id: account.id, primary_actor: config, meta: { 'quantos' => 2 })
    expect(texto(aviso)).to eq(['Seguros entraram em renovação', '2 seguros entraram em renovação hoje'])
    expect(aviso.push_event_data[:primary_actor]).to eq(id: config.id)
  end

  it 'com um seguro só, fala no singular' do
    nasceu('EX-000001')

    avisar

    expect(texto(avisos.sole.reload).last).to eq('1 seguro entrou em renovação hoje')
  end

  it 'fica só no painel: não manda push nem e-mail' do
    nasceu('EX-000001')

    expect { avisar }.to have_enqueued_job(Notification::RemoveDuplicateNotificationJob).once

    expect(enqueued_jobs.pluck('job_class')).not_to include('Notification::PushNotificationJob', 'Notification::EmailNotificationJob')
  end

  it 'a segunda passada do dia deixa um aviso só por pessoa, com o total' do
    nasceu('EX-000001')
    avisar
    travel 1.hour
    nasceu('EX-000002')

    perform_enqueued_jobs(only: Notification::RemoveDuplicateNotificationJob) { avisar }

    expect(avisos.sole.meta).to eq('quantos' => 2)
  end

  it 'sem card nascido hoje não avisa ninguém' do
    nasceu('EX-000001', quando: agora - 1.day)

    avisar

    expect(avisos).to be_empty
  end

  it 'quem não enxerga o funil das renovações não recebe' do
    agente = create_crm_agent(account: account, name: 'Vendas').first
    caixa = create_crm_inbox(account: account, members: [agente])
    vendas, = create_crm_pipeline(account: account, user: admin, name: 'Vendas')
    [funil, vendas].each { |ligado| Crm::PipelineInbox.create!(account: account, inbox: caixa, pipeline: ligado) }
    acesso = Crm::InboxAgentAccess.create!(account: account, inbox: caixa, user: agente, all_pipelines: false, triage: false, only_own: false)
    acesso.agent_pipelines.create!(account: account, pipeline: vendas)
    nasceu('EX-000001')

    avisar

    expect(avisos.pluck(:user_id)).to eq([admin.id])
  end

  it 'cada conta conta e avisa só os seus' do
    outra = conta_com_carteira
    dona = create(:user, account: outra, role: :administrator)
    funil_de_fora, etapa_de_fora = create_crm_pipeline(account: outra, user: dona, name: 'Renovação')
    de_fora = create(:carteira_renovacao_config, account: outra, pipeline: funil_de_fora, stage: etapa_de_fora)
    nasceu('EX-000001')
    nasceu('EX-000002')
    nasceu('EX-000003', pessoa: create(:contact, account: outra))

    avisar
    avisar(outra, de_fora)

    expect(avisos.order(:id).map { |aviso| [aviso.user_id, aviso.account_id, aviso.meta['quantos']] })
      .to eq([[admin.id, account.id, 2], [dona.id, outra.id, 1]])
  end

  it 'o aviso de uma pessoa que falha não para o das outras' do
    agente = create(:user, account: account, role: :agent)
    nasceu('EX-000001')
    allow(Rails.logger).to receive(:error)
    allow(Notification).to receive(:create!).and_wrap_original do |criar, **dados|
      raise ActiveRecord::StatementTimeout, 'canceling statement' if dados[:user] == admin

      criar.call(**dados)
    end

    avisar

    expect(avisos.pluck(:user_id)).to eq([agente.id])
    expect(Rails.logger).to have_received(:error)
      .with("[carteira][aviso] não saiu conta=#{account.id} user=#{admin.id} ActiveRecord::StatementTimeout")
  end
end
