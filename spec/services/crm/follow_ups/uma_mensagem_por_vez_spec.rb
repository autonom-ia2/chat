require 'rails_helper'

# Monta follow-ups enviados (done + sent_message_id) sem passar pelo envio.
# rubocop:disable Rails/SkipsModelValidations

# Uma mensagem por vez por card (#1589): a regra que os dois motores consultam.
RSpec.describe Crm::FollowUps::UmaMensagemPorVez do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:now) { Time.zone.parse('2026-10-14 15:00 UTC') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Troca')
  end

  def cadencia(mode: 'auto_send', enabled: true)
    pipeline_and_stage.first.update!(metadata: { 'ai' => { 'auto_followup' => { 'enabled' => enabled, 'mode' => mode } } })
  end

  def follow_up(source, enviado_em: nil)
    registro = account.crm_follow_ups.create!(card: card, title: 'x', due_at: now + 1.hour, timezone: 'UTC',
                                              automation_mode: :reminder_only, metadata: { 'source' => source })
    return registro unless enviado_em

    registro.update_columns(status: Crm::FollowUp.statuses[:done], completed_at: enviado_em,
                            metadata: registro.metadata.merge('sent_message_id' => 1))
    registro
  end

  def regra = described_class.new(card.reload, now: now)

  before { cadencia }

  it 'nada no card: ninguém espera' do
    expect(regra.lembrete_espera?).to be(false)
    expect(regra.automatico_espera?).to be(false)
    expect(regra.automatico_espera_ate).to be_nil
  end

  it 'toque pendente segura o lembrete só com o card aberto' do
    follow_up('ai_followup')
    expect(regra.lembrete_espera?).to be(true)

    card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now)
    expect(regra.lembrete_espera?).to be(false)
  end

  it 'toque pendente não segura com a cadência só de lembrete para a equipe ou desligada' do
    follow_up('ai_followup')
    cadencia(mode: 'ai_reminder')
    expect(regra.lembrete_espera?).to be(false)

    cadencia(enabled: false)
    expect(regra.lembrete_espera?).to be(false)
  end

  it 'toque enviado segura o lembrete por 24 h, mesmo com o card fechado' do
    follow_up('ai_followup', enviado_em: now - 23.hours)
    card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now)

    expect(regra.lembrete_espera?).to be(true)
    expect(described_class.new(card.reload, now: now + 2.hours).lembrete_espera?).to be(false)
  end

  it 'lembrete pendente ou enviado segura o início da cadência; enviado diz até quando' do
    follow_up('service_reminder')
    expect(regra.automatico_espera?).to be(true)
    expect(regra.automatico_espera_ate).to be_nil

    Crm::FollowUp.update_all(status: Crm::FollowUp.statuses[:canceled])
    follow_up('service_reminder', enviado_em: now - 2.hours)
    expect(regra.automatico_espera?).to be(true)
    expect(regra.automatico_espera_ate).to eq(now + 22.hours)
  end

  it 'em modo lembrete para a equipe a cadência não espera o lembrete' do
    cadencia(mode: 'ai_reminder')
    follow_up('service_reminder', enviado_em: now - 2.hours)

    expect(regra.automatico_espera?).to be(false)
    expect(regra.automatico_espera_ate).to be_nil
  end

  it 'envio sem mensagem (toque pulado ou parado) não segura' do
    registro = follow_up('ai_followup')
    registro.update_columns(status: Crm::FollowUp.statuses[:done], completed_at: now - 1.hour)
    card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now)

    expect(regra.lembrete_espera?).to be(false)
  end
end
# rubocop:enable Rails/SkipsModelValidations
