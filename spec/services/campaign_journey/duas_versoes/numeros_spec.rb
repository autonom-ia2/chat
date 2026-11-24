require 'rails_helper'

# #3099: os números de cada versão na campanha. Só contam as pessoas do teste que receberam; "responderam" é a marca da
# campanha na conversa (CampaignJourney::ResultReplies), e quem respondeu sem ser do teste (o resto) não entra.
RSpec.describe CampaignJourney::DuasVersoes::Numeros, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) do
    linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end
  let!(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:link) do
    campaign = CampaignJourney::SmsCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'sms',
      attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi, versão 1',
                    duas_versoes: { criterio: 'respostas', segunda: { message_body: 'Oi, versão 2' } } }
    ).perform
    CampaignAudienceLink.for_campaign(campaign)
  end

  before do
    stub_twilio_sms
    stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
    stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
  end

  def numeros = described_class.new(link, account: account)

  def do_teste(versao) = link.campaign_version_contacts.where(fase: 'teste', versao: versao).pluck(:contact_id)

  it 'antes do envio, ninguém recebeu e não há começo' do
    expect(numeros.primeiro_envio).to be_nil
    expect(numeros.por_versao.pluck(:receberam)).to eq([0, 0])
  end

  it 'conta quem do teste recebeu e respondeu, cada um na sua versão' do
    Twilio::OneoffSmsCampaignService.new(campaign: link.campaign).perform
    fora_do_teste = account.contacts.where.not(id: link.campaign_version_contacts.select(:contact_id)).pick(:id)
    respostas = instance_double(CampaignJourney::ResultReplies, contact_ids: [do_teste(2).first, fora_do_teste])
    allow(CampaignJourney::ResultReplies).to receive(:new).and_return(respostas)

    um, dois = numeros.por_versao

    expect(numeros.primeiro_envio).to be_present
    expect(um).to include(receberam: 2, responderam: 0, compraram: 0)
    expect(dois).to include(receberam: 2, responderam: 1, compraram: 0)
  end
end
