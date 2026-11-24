require 'rails_helper'

# #3101: com o melhor horário ligado na campanha, quem tem hora aprendida espera `queued` com adiado_ate na hora dele
# (sem virar falha no fim da rodada) e sai na retomada, sem esperar de novo; quem não tem hora recebe na hora.
RSpec.describe CampaignJourney::SmsOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) { "Nome,Celular\nAna Souza,11987654321\nCaio Reis,31987654321\n" }
  let!(:audience) { saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'phone' => 1 }) }
  let(:campaign) do
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Parcela', message: 'Oi {{contact.first_name}}.')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end
  let(:ana) { account.contacts.find_by!(name: 'Ana Souza') }
  # Quinta-feira, 19/11/2026, 10h em São Paulo (13h UTC); a hora da Ana é 14h.
  let(:agora) { Time.utc(2026, 11, 19, 13, 0, 0) }

  before do
    account.update_columns(settings: account.settings.to_h.merge('reporting_timezone' => 'America/Sao_Paulo')) # rubocop:disable Rails/SkipsModelValidations
    Autonomia::HorarioDeResposta.create!(account: account, contact: ana, por_hora: Array.new(24, 0), respostas: 5, hora: 14,
                                         calculado_em: agora)
  end

  def service = Twilio::OneoffSmsCampaignService.new(campaign: campaign)
  def recipient_of(contact) = CampaignRecipient.find_by!(campaign: campaign, contact: contact)

  it 'desligado, todos recebem na hora' do
    sent = stub_twilio_sms

    travel_to(agora) { service.perform }

    expect(sent.size).to eq(2)
  end

  it 'ligado, adia quem tem hora para a hora dele e manda na hora a quem não tem' do
    Autonomia::MelhorHorario.guardar!(campaign, true)
    sent = stub_twilio_sms
    allow(Autonomia::MelhorHorario).to receive(:ligado?).and_call_original

    travel_to(agora) { service.perform }

    # Uma consulta da opção por rodada da campanha, não uma por destinatário (Autonomia::MelhorHorario::DoMotor).
    expect(Autonomia::MelhorHorario).to have_received(:ligado?).once

    expect(sent.pluck('To')).to eq(['+5531987654321'])
    adiada = recipient_of(ana)
    expect(adiada).to be_queued
    expect(adiada.adiado_ate).to eq(Time.utc(2026, 11, 19, 17, ana.id % 60, 0))
  end

  it 'na retomada, manda sem esperar o melhor horário de novo' do
    Autonomia::MelhorHorario.guardar!(campaign, true)
    sent = stub_twilio_sms
    travel_to(agora) { service.perform }

    travel_to(recipient_of(ana).adiado_ate + 1.minute) { service.retomar_adiados }

    expect(sent.pluck('To')).to contain_exactly('+5531987654321', '+5511987654321')
    expect(recipient_of(ana)).to be_sent
  end
end
