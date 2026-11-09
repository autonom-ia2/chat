require 'rails_helper'

# chat#2733: contato bloqueado não recebe campanha, igual a quem recusou mensagens ativas (chat#737).
RSpec.describe ContactCampaignReach do
  let(:account) { create(:account) }
  let!(:livre) { create(:contact, account: account) }
  let!(:recusou) { create(:contact, account: account, opted_out_at: 1.day.ago) }
  let!(:bloqueado) { create(:contact, account: account, blocked: true) }
  let!(:os_dois) { create(:contact, account: account, blocked: true, opted_out_at: 1.day.ago) }

  it 'campaign_reachable deixa só quem não recusou e não está bloqueado' do
    expect(account.contacts.campaign_reachable).to contain_exactly(livre)
  end

  it 'campaign_unreachable junta quem recusou e quem está bloqueado' do
    expect(account.contacts.campaign_unreachable).to contain_exactly(recusou, bloqueado, os_dois)
  end

  it 'campaign_refusal diz o motivo, com a recusa antes do bloqueio' do
    expect(livre.campaign_refusal).to be_nil
    expect(recusou.campaign_refusal).to eq('opted_out')
    expect(bloqueado.campaign_refusal).to eq('blocked')
    expect(os_dois.campaign_refusal).to eq('opted_out')
  end

  it 'campaign_refusal_now relê do banco, para o envio pegar quem mudou durante o disparo' do
    carregado = Contact.find(livre.id)
    Contact.where(id: livre.id).update_all(blocked: true) # rubocop:disable Rails/SkipsModelValidations

    expect(carregado.campaign_refusal).to be_nil
    expect(Contact.campaign_refusal_now(livre.id)).to eq('blocked')
    expect(Contact.campaign_refusal_now(recusou.id)).to eq('opted_out')
    expect(Contact.campaign_refusal_now(0)).to be_nil
  end
end
