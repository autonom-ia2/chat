require 'rails_helper'

# #3099: o teste em que ninguém recebeu nada. Passada a espera, o Resultado e a lista de Campanhas avisam (com a hora em
# que a versão 1 vai para o resto); com alguém do teste recebendo, nenhum aviso.
RSpec.describe CampaignJourney::DuasVersoes::SemEnvio, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:account_user) { AccountUser.find_by!(account: account, user: user) }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) do
    linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end
  let!(:audience) { saved_audience(account: account, user: user, content: content) }
  let!(:sent) { stub_twilio_sms }

  before do
    stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
    stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
  end

  def campanha(criterio = 'respostas', **outros)
    campaign = CampaignJourney::SmsCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'sms',
      attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi, versão 1',
                    duas_versoes: { criterio: criterio, segunda: { message_body: 'Oi, versão 2' } }, **outros }
    ).perform
    CampaignAudienceLink.for_campaign(campaign)
  end

  def resultado(link)
    CampaignJourney::DuasVersoes::Resultado.new(link, account: account).payload(user: user, account_user: account_user)
  end

  def esperando = CampaignJourney::DuasVersoes::Esperando.new(account).payload

  it 'antes da espera não avisa; depois, avisa com a hora em que a versão 1 vai para o resto' do
    link = campanha

    expect(described_class.new(link).avisar?).to be(false)
    expect(resultado(link)[:sem_envio_ate]).to be_nil
    expect(esperando).to be_empty

    travel 5.hours do
      sem_envio = described_class.new(link.reload)
      ate = sem_envio.ate
      expect(sem_envio.avisar?).to be(true)
      expect(sem_envio.venceu?).to be(false)
      expect(ate).to be_within(1.minute).of(3.days.from_now - 5.hours)
      expect(resultado(link)[:sem_envio_ate]).to eq(ate.to_i)
      expect(esperando).to contain_exactly(
        include(motivo: 'sem_envio', channel: CampaignJourney::ResultFinder.channel_of(link.campaign), id: link.campaign.display_id,
                name: 'Parcela', resto: 6, vai_sozinha_em: ate.to_i)
      )
    end
  end

  it 'com alguém do teste recebendo, não avisa' do
    link = campanha
    Twilio::OneoffSmsCampaignService.new(campaign: link.campaign).perform

    travel 5.hours do
      expect(described_class.new(link.reload).avisar?).to be(false)
      expect(resultado(link)[:sem_envio_ate]).to be_nil
      expect(esperando).to be_empty
    end
  end

  it 'agendada para depois, não conta o tempo antes de começar' do
    link = campanha(scheduled_at: 1.day.from_now.iso8601)

    travel 5.hours do
      expect(described_class.new(link.reload).avisar?).to be(false)
    end
  end

  it 'a lista traz junto as campanhas que esperam alguém escolher, cada uma com o seu motivo' do
    escolher = campanha('eu_escolho')
    Twilio::OneoffSmsCampaignService.new(campaign: escolher.campaign).perform
    escolher.update!(teste_estado: 'esperando_voce', teste_escolhe_em: 1.hour.ago)
    sem_envio = campanha

    travel 5.hours do
      expect(esperando.pluck(:motivo, :id)).to eq([['escolher', escolher.campaign.display_id], ['sem_envio', sem_envio.campaign.display_id]])
    end
  end
end
