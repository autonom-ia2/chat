require 'rails_helper'

# #3099: o cron escolhe a versão do resto. A hora sai do primeiro envio do teste + a espera; empate ou poucas respostas
# seguem a versão 1; no "eu escolho" a campanha espera a pessoa e, depois de 3 dias, a versão 1 vai sozinha (D5).
RSpec.describe CampaignJourney::EscolherVencedoraJob, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
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

  def campanha(criterio, enviar: true)
    campaign = CampaignJourney::SmsCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'sms',
      attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi, versão 1',
                    duas_versoes: { criterio: criterio, segunda: { message_body: 'Oi, versão 2' } } }
    ).perform
    Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform if enviar
    CampaignAudienceLink.for_campaign(campaign)
  end

  it 'antes do teste sair não marca hora nem escolhe' do
    link = campanha('respostas', enviar: false)

    described_class.perform_now

    expect(link.reload).to have_attributes(teste_estado: 'testando', teste_escolhe_em: nil)
  end

  it 'marca a hora pelo primeiro envio e, sem respostas, manda a versão 1 por empate' do
    link = campanha('respostas')

    described_class.perform_now
    expect(link.reload.teste_escolhe_em).to be_within(1.minute).of(4.hours.from_now)
    expect(link.teste_estado).to eq('testando')

    travel 5.hours do
      described_class.perform_now
      CampaignJourney::EnviarRestoJob.perform_now(link.id)
    end

    expect(link.reload).to have_attributes(teste_estado: 'escolhida', teste_vencedora: 1, teste_escolhida_por: 'empate')
    expect(sent.size).to eq(10)
    expect(sent.last(6).pluck('Body')).to all(eq('Oi, versão 1'))
  end

  it 'manda a versão que teve mais respostas' do
    link = campanha('respostas')
    numeros = instance_double(CampaignJourney::DuasVersoes::Numeros, primeiro_envio: Time.current)
    allow(numeros).to receive(:por_versao).and_return([{ receberam: 100, responderam: 5, compraram: 0 },
                                                       { receberam: 100, responderam: 20, compraram: 0 }])
    allow(CampaignJourney::DuasVersoes::Numeros).to receive(:new).and_return(numeros)

    travel 5.hours do
      described_class.perform_now
    end

    expect(link.reload).to have_attributes(teste_estado: 'escolhida', teste_vencedora: 2, teste_escolhida_por: 'sistema')
  end

  it 'no "eu escolho" espera a pessoa e, passados 3 dias, manda a versão 1 sozinha' do
    link = campanha('eu_escolho')
    described_class.perform_now

    travel 5.hours do
      described_class.perform_now
    end
    expect(link.reload).to have_attributes(teste_estado: 'esperando_voce', teste_vencedora: nil)

    travel 2.days do
      described_class.perform_now
    end
    expect(link.reload.teste_estado).to eq('esperando_voce')

    travel 4.days do
      described_class.perform_now
    end
    expect(link.reload).to have_attributes(teste_estado: 'escolhida', teste_vencedora: 1, teste_escolhida_por: 'sistema')
  end

  it 'uma campanha com problema não segura as outras' do
    quebrada = campanha('respostas')
    boa = campanha('respostas')
    [quebrada, boa].each { |link| link.update!(teste_escolhe_em: 1.hour.ago) }
    chamadas = 0
    allow(CampaignJourney::DuasVersoes::Vencedora).to receive(:melhor).and_wrap_original do |original, *args|
      chamadas += 1
      raise StandardError, 'quebrou' if chamadas == 1

      original.call(*args)
    end

    described_class.perform_now

    expect([quebrada.reload.teste_estado, boa.reload.teste_estado]).to contain_exactly('testando', 'escolhida')
  end
end
