require 'rails_helper'

# Envio ao CRM em lote (#680, frente B). Cada lead é um envio independente: o resumo conta criados, já existentes e
# falhas com motivo, e a automação de entrada do estágio roda uma vez por card criado agora.
RSpec.describe Autonomia::Prospecting::CrmCardBatch do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def create_leads(count, target_account: account)
    Array.new(count) do |index|
      Autonomia::Prospecting::Lead.create!(
        account: target_account,
        provider: 'mock',
        provider_place_id: "mock-place-#{target_account.id}-#{index}",
        name: "Empresa #{index}",
        phone: format('+55 31 9%<n>04d-%<m>04d', n: 1000 + index, m: 2000 + index),
        city: 'Divinopolis',
        state: 'MG',
        country: 'BR',
        score: 70 + (index % 10),
        priority_score: 60.5,
        search_rank: index + 1,
        enrichment_summary: "Resumo da empresa #{index}",
        # Só o primeiro tem CNPJ válido no site; os outros, sem CNPJ nem site, viram cada um a sua empresa.
        enriched_cnpj: index.zero? ? '11222333000181' : nil
      )
    end
  end

  def perform(lead_ids)
    described_class.new(account: account, user: user, lead_ids: lead_ids, pipeline_id: pipeline.id, stage_id: stage.id).perform
  end

  def create_follow_up_automation
    automation = account.crm_stage_automations.create!(
      pipeline: pipeline, stage: stage, name: 'Entrada prospecção', trigger_event: :on_enter, created_by: user
    )
    # Passo inofensivo: só uma tarefa de lembrete, nenhuma mensagem ao cliente.
    automation.steps.create!(
      account: account, position: 0, delay_seconds: 0, action_type: :create_follow_up,
      action_config: { title: 'Ligar para o decisor', automation_mode: 'reminder_only' }
    )
    automation
  end

  it '30 leads geram 30 cards, 30 contatos e 30 empresas, cada card com empresa, contato e resumo' do
    leads = create_leads(30)

    result = perform(leads.map(&:id))

    expect([result.created.size, result.existing.size, result.failed.size]).to eq([30, 0, 0])
    expect([account.crm_cards.count, account.contacts.count, account.companies.count]).to eq([30, 30, 30])

    item = result.created.find { |row| row[:lead_id] == leads.first.id }
    card = account.crm_cards.find(item[:card_id])
    expect(item[:contact_id]).to eq(card.contact_id)
    expect(item[:company_id]).to be_present
    meta = card.metadata['autonomia_prospecting']
    expect(meta).to include('score' => 70.0, 'priority_score' => 60.5, 'search_rank' => 1, 'summary' => 'Resumo da empresa 0')
    expect(meta['company']).to eq('id' => item[:company_id], 'cnpj' => '11222333000181', 'legal_name' => nil)
    expect(card.description).to include('Resumo da empresa 0')
  end

  it 'o card carrega prioridade, nota, decisor e empresa onde o quadro e o painel do card mostram' do
    hot, cold, unknown = create_leads(3)
    hot.update!(priority_score: 95, score: 90.4, decision_name: 'ANA SOUZA', decision_role: 'Sócia administradora')
    cold.update!(priority_score: 10)
    unknown.update!(priority_score: nil)

    perform([hot, cold, unknown].map(&:id))

    cards = [hot, cold, unknown].map { |lead| lead.reload.crm_card }
    expect(cards.map(&:priority)).to eq(%w[urgent low medium])
    expect(cards.first.score).to eq(0)
    expect(cards.first.description).to include(
      I18n.t('autonomia.prospecting.crm_send.card_description.score', score: 90),
      I18n.t('autonomia.prospecting.crm_send.card_description.decision_with_role', name: 'ANA SOUZA', role: 'Sócia administradora'),
      I18n.t('autonomia.prospecting.crm_send.card_description.cnpj', cnpj: '11222333000181')
    )
  end

  it 'a faixa de prioridade é a mesma do anel da tela: 75 urgente, 50 alta, 25 média, abaixo baixa' do
    leads = create_leads(4)
    [75, 50, 25, 24.4].zip(leads).each { |value, lead| lead.update!(priority_score: value) }

    perform(leads.map(&:id))

    expect(leads.map { |lead| lead.reload.crm_card.priority }).to eq(%w[urgent high medium low])
  end

  it 'reenviar devolve os mesmos cards como já existentes e não cria nada' do
    leads = create_leads(30)
    first = perform(leads.map(&:id))

    second = perform(leads.map(&:id))

    expect(second.created).to be_empty
    expect(second.failed).to be_empty
    expect(second.existing.map { |row| row[:card_id] }).to match_array(first.created.map { |row| row[:card_id] })
    expect(account.crm_cards.count).to eq(30)
    expect(account.contacts.count).to eq(30)
    expect(account.companies.count).to eq(30)
  end

  it 'duas falhas em 30 deixam os 28 bons gravados e não sobra contato nem empresa das falhas' do
    leads = create_leads(30)
    broken = leads.values_at(4, 17)
    allow(Crm::Cards::Creator).to receive(:new).and_wrap_original do |original, **kwargs|
      raise ActiveRecord::RecordInvalid, Crm::Card.new if broken.map(&:name).include?(kwargs[:params][:title])

      original.call(**kwargs)
    end

    result = perform(leads.map(&:id))

    expect(result.created.size).to eq(28)
    expect(result.failed.map { |row| row[:lead_id] }).to match_array(broken.map(&:id))
    expect(result.failed.map { |row| [row[:reason_code], row[:message]] }.uniq)
      .to eq([['invalid_data', I18n.t('autonomia.prospecting.crm_send.failures.invalid_data')]])
    expect([account.crm_cards.count, account.contacts.count, account.companies.count]).to eq([28, 28, 28])
    expect(broken.map { |lead| lead.reload.slice(:crm_card_id, :contact_id).values }).to all(eq([nil, nil]))
  end

  it 'recusa mais de 30 leads sem gravar nada' do
    leads = create_leads(31)

    expect { perform(leads.map(&:id)) }.to raise_error(described_class::TooManyLeads)
    expect(account.crm_cards.count).to eq(0)
  end

  it 'lead de outra conta vira not_found sem vazar nada dele' do
    other_account = create(:account)
    foreign = create_leads(1, target_account: other_account).first
    own = create_leads(1).first

    result = perform([own.id, foreign.id])

    expect(result.created.map { |row| row[:lead_id] }).to eq([own.id])
    expect(result.failed).to eq([{ lead_id: foreign.id, reason_code: 'not_found',
                                   message: I18n.t('autonomia.prospecting.crm_send.failures.not_found') }])
    expect(foreign.reload.crm_card_id).to be_nil
    expect(other_account.crm_cards.count).to eq(0)
  end

  it 'roda a automação de entrada do estágio uma única vez por card criado e nunca para card já existente' do
    automation = create_follow_up_automation
    leads = create_leads(3)

    perform(leads.map(&:id))
    perform(leads.map(&:id))

    executions = account.crm_stage_automation_executions.where(stage_automation: automation)
    expect(executions.count).to eq(3)
    expect(executions.map(&:status).uniq).to eq(['completed'])
    expect(executions.map(&:card_id)).to match_array(account.crm_cards.pluck(:id))
    expect(account.crm_follow_ups.where(title: 'Ligar para o decisor').count).to eq(3)
  end

  it 'não roda a automação para lead que já tinha card antes do lote' do
    automation = create_follow_up_automation
    lead = create_leads(1).first
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card antigo')
    lead.update!(crm_card: card)

    result = perform([lead.id])

    expect(result.existing).to eq([{ lead_id: lead.id, card_id: card.id }])
    expect(account.crm_stage_automation_executions.where(stage_automation: automation).count).to eq(0)
  end

  it 'falha da automação não desfaz o card' do
    create_follow_up_automation
    lead = create_leads(1).first
    allow_any_instance_of(Crm::StageAutomations::Runner).to receive(:perform).and_raise(StandardError, 'automação quebrou') # rubocop:disable RSpec/AnyInstance

    result = perform([lead.id])

    expect(result.created.size).to eq(1)
    expect(lead.reload.crm_card).to be_present
    expect(account.crm_cards.count).to eq(1)
  end

  it 'o Creator do CRM continua sem disparar automação para card criado fora da prospecção' do
    automation = create_follow_up_automation

    Crm::Cards::Creator.new(
      account: account, user: user, params: { pipeline_id: pipeline.id, stage_id: stage.id, title: 'Card manual' }
    ).perform

    expect(account.crm_stage_automation_executions.where(stage_automation: automation).count).to eq(0)
    expect(account.crm_follow_ups.count).to eq(0)
  end
end
