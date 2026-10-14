require 'rails_helper'

# #1449: o pedido de parar na resposta a campanha vale pelo número. Desfazer solta o número do pedido, e só ele.
RSpec.describe Contacts::CampaignReplyOptOut do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }

  def asked_to_stop(phone)
    contact = account.contacts.create!(name: "Pediu #{phone}", phone_number: phone)
    described_class.mark!(contact)
    contact
  end

  def heir_on(phone)
    contact = account.contacts.create!(name: "Herdeiro #{phone}", phone_number: phone)
    Contacts::OptOutInheritance.new(account: account).apply([contact])
    contact.reload
  end

  it 'mark! grava a recusa e o número; contato sem telefone fica só com a recusa' do
    contact = asked_to_stop('+5531999996001')
    sem_telefone = account.contacts.create!(name: 'Sem telefone')

    expect(described_class.mark!(sem_telefone)).to be(true)
    expect(contact.reload.additional_attributes[described_class::PHONE_KEY]).to eq('+5531999996001')
    expect(sem_telefone.reload.opt_out_source).to eq('campaign_reply')
    expect(sem_telefone.additional_attributes.to_h).not_to have_key(described_class::PHONE_KEY)
  end

  it 'desfazer no original que trocou de número solta o número do pedido, não o número de hoje dele' do
    original = asked_to_stop('+5531999996010')
    original.update!(phone_number: '+5531999996011')
    heir = heir_on('+5531999996010')
    outro_pedido = asked_to_stop('+5531999996012')
    outro_pedido.update!(phone_number: '+5531999996013')
    heir_do_outro = heir_on('+5531999996012')

    described_class.release_number!(original, by: agent)

    expect(original.reload).not_to be_opted_out
    expect(heir.reload).not_to be_opted_out
    expect(outro_pedido.reload.opt_out_source).to eq('campaign_reply')
    expect(heir_do_outro.reload.opt_out_source).to eq('campaign_reply')
  end

  it 'original de outro número que hoje está neste telefone não é solto pelo herdeiro daqui' do
    pedido_aqui = asked_to_stop('+5531999996020')
    pedido_aqui.update!(phone_number: '+5531999996021')
    heir = heir_on('+5531999996020')
    pedido_em_outro = asked_to_stop('+5531999996022')
    pedido_em_outro.update!(phone_number: '+5531999996023')

    described_class.release_number!(heir, by: agent)

    expect(heir.reload).not_to be_opted_out
    expect(pedido_aqui.reload).not_to be_opted_out
    expect(pedido_em_outro.reload.opt_out_source).to eq('campaign_reply')
    expect(pedido_em_outro.additional_attributes[described_class::PHONE_KEY]).to eq('+5531999996022')
  end

  it 'o mesmo número noutra conta não entra no grupo' do
    original = asked_to_stop('+5531999996030')
    outra_conta = create(:account)
    de_fora = outra_conta.contacts.create!(name: 'Outra conta', phone_number: '+5531999996030')
    described_class.mark!(de_fora)

    described_class.release_number!(original, by: agent)

    expect(original.reload).not_to be_opted_out
    expect(de_fora.reload.opt_out_source).to eq('campaign_reply')
  end

  it 'contato que já tinha recusado por outra origem fica como estava' do
    contact = account.contacts.create!(name: 'Manual', phone_number: '+5531999996040')
    contact.opt_out!(source: 'manual')

    expect(described_class.mark!(contact)).to be(false)
    expect(contact.reload.opt_out_source).to eq('manual')
  end
end
