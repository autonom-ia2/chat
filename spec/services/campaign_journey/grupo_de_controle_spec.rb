require 'rails_helper'

# #3098: o grupo de controle da campanha com público. Sorteio fixo pelo hash, exatamente público × pct (para baixo), uma
# vez só; quem está no grupo não vira destinatário (nem "Pulada"), e a soma do resultado continua fechando com o Público.
RSpec.describe CampaignJourney::GrupoDeControle, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) do
    linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end
  let!(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, audience: [], title: 'Parcela', message: 'Oi {{contact.first_name}}') }
  let(:link) { CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, grupo_de_controle_pct: 20) }
  # Antes do sorteio, ninguém está no grupo: é o público inteiro.
  let!(:publico_ids) { CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).pluck(:id) }

  it 'sorteia exatamente público × pct, sempre as mesmas pessoas, uma vez só' do
    described_class.new(link).sortear!(publico_ids)
    primeiro = link.campaign_control_contacts.pluck(:contact_id)
    expect(primeiro.size).to eq(2)
    expect(CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).pluck(:id)).to match_array(publico_ids - primeiro)

    described_class.new(link).sortear!(publico_ids.reverse)
    expect(link.campaign_control_contacts.pluck(:contact_id)).to match_array(primeiro)

    link.campaign_control_contacts.delete_all
    described_class.new(link).sortear!(publico_ids.reverse)
    expect(link.campaign_control_contacts.pluck(:contact_id)).to match_array(primeiro)
  end

  it 'sem grupo não sorteia nem tira ninguém' do
    link.update!(grupo_de_controle_pct: 0)
    described_class.new(link).sortear!(publico_ids)

    expect(link.campaign_control_contacts).to be_empty
    expect(CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).count).to eq(10)
  end

  it 'o grupo não recebe o SMS e não vira destinatário pulado' do
    sent = stub_twilio_sms
    CampaignJourney::Medicao.new(link).aplicar!({}) { CampaignJourney::Medicao.publico(link, 'sms') }
    fora = account.contacts.where(id: link.campaign_control_contacts.select(:contact_id)).pluck(:phone_number)

    Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform

    expect(sent.pluck('To').size).to eq(8)
    expect(sent.pluck('To') & fora).to be_empty
    expect(CampaignRecipient.where(campaign: campaign).count).to eq(8)
    expect(CampaignRecipient.where(campaign: campaign).skipped.count).to eq(0)
  end

  it 'muda a porcentagem antes do envio: o sorteio antigo sai e vale o novo' do
    CampaignJourney::Medicao.new(link).aplicar!({}) { publico_ids }
    expect(link.campaign_control_contacts.count).to eq(2)

    CampaignJourney::Medicao.new(link).aplicar!({ grupo_de_controle_pct: '10', janela_de_compra_dias: '15' }) { publico_ids }

    expect(link.reload).to have_attributes(grupo_de_controle_pct: 10, janela_de_compra_dias: 15)
    expect(link.campaign_control_contacts.count).to eq(1)
  end

  it 'recusa janela e porcentagem fora das opções da tela' do
    expect { CampaignJourney::Medicao.new(link).aplicar!({ janela_de_compra_dias: 9 }) { [] } }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
