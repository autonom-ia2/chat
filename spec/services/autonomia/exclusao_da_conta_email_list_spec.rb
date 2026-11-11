require 'rails_helper'

# G52 (#2760): a campanha aponta para a lista e a lista para a etiqueta. A ordem das ETAPAS (campanha antes da lista)
# apaga as duas sem esbarrar nas chaves, e só da conta que sai.
RSpec.describe Autonomia::ExclusaoDaConta do
  around do |example|
    with_modified_env(EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  before { allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue) }

  def campanha_com_lista(conta)
    lista = EmailList.criar(account: conta, name: 'Dicas do mês')
    create(:contact, account: conta, email: "ana#{conta.id}@exemplo.com").update_labels([lista.label.title])
    create(:email_campaign, account: conta).tap { |campanha| campanha.update!(email_list: lista) }
  end

  it 'apaga a lista de e-mail e a campanha que a usa, e só da conta' do
    campanha = campanha_com_lista(create(:account))
    de_outra_conta = campanha_com_lista(create(:account))

    recipient_ids = campanha.email_campaign_recipients.pluck(:id)

    described_class.new(campanha.account).perform

    contar = ->(conta_id) { [EmailCampaign.where(account_id: conta_id).count, EmailList.where(account_id: conta_id).count] }
    expect(contar.call(campanha.account_id)).to eq([0, 0])
    expect(contar.call(de_outra_conta.account_id)).to eq([1, 1])
    expect(EmailCampaignRecipient.where(id: recipient_ids)).to be_empty
    expect(de_outra_conta.email_campaign_recipients.count).to eq(1)
  end
end
