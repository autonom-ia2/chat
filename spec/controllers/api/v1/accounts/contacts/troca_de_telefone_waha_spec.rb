require 'rails_helper'

# #2711 (Waha::TrocaDeTelefoneNaMao): a pessoa troca o telefone do contato e o chat id da WAHA sai no mesmo save, para a
# próxima mensagem pela caixa WAHA ir ao número novo. Importação, junção e sincronização não passam por aqui.
RSpec.describe 'Troca do telefone do contato na caixa WAHA', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:chat_id) do
    { 'waha_whatsapp_chat_id' => '5511911110000@c.us', 'waha_whatsapp_jid' => '5511911110000@c.us', 'waha_whatsapp_lid' => '77@lid' }
  end
  let(:contact) do
    create(:contact, account: account, phone_number: '+5511911110000', custom_attributes: chat_id.merge('origem' => 'site'))
  end
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}" }

  def caixa_waha(conta = account)
    channel = create(:channel_api, account: conta, additional_attributes: { 'provider' => 'waha', 'session' => "s-#{conta.id}" })
    create(:inbox, account: conta, channel: channel)
  end

  def patch_contact(params)
    patch url, params: params, headers: admin.create_new_auth_token, as: :json
  end

  context 'with a WAHA inbox in the account' do
    before { caixa_waha }

    it 'removes the WAHA chat id when the phone changes, keeping the other attributes' do
      patch_contact(phone_number: '+5511922220000')

      expect(response).to have_http_status(:success)
      contact.reload
      expect(contact.phone_number).to eq('+5511922220000')
      expect(contact.custom_attributes).to eq('origem' => 'site')
    end

    it 'removes the chat id even when the request sends it back with the new phone' do
      patch_contact(phone_number: '+5511922220000', custom_attributes: chat_id.merge('plano' => 'ouro'))

      expect(contact.reload.custom_attributes).to eq('origem' => 'site', 'plano' => 'ouro')
    end

    it 'keeps the chat id when the phone does not change' do
      patch_contact(name: 'Outro nome', phone_number: '+5511911110000')

      expect(contact.reload.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
    end

    it 'keeps the chat id when the request does not send the phone' do
      patch_contact(name: 'Outro nome')

      expect(contact.reload.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
    end

    it 'keeps the chat id when the phone is cleared' do
      patch_contact(phone_number: '')

      expect(contact.reload.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
    end

    it 'keeps the chat id when the contact had no phone before' do
      contact.update!(phone_number: nil)

      patch_contact(phone_number: '+5511922220000')

      expect(contact.reload.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
    end

    it 'keeps the phone and the chat id when the new phone is invalid' do
      patch_contact(phone_number: '11922220000')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(contact.reload.phone_number).to eq('+5511911110000')
      expect(contact.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
    end
  end

  it 'keeps the chat id in an account without a WAHA inbox' do
    create(:inbox, account: account, channel: create(:channel_api, account: account))
    caixa_waha(create(:account))

    patch_contact(phone_number: '+5511922220000')

    expect(contact.reload.phone_number).to eq('+5511922220000')
    expect(contact.custom_attributes).to eq(chat_id.merge('origem' => 'site'))
  end

  context 'when the phone changes outside a person editing the contact' do
    let!(:inbox) { caixa_waha }
    let(:intacto) { chat_id.merge('origem' => 'site') }

    it 'keeps the chat id on the WAHA sync through the inbox public API' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)

      patch "/public/api/v1/inboxes/#{inbox.channel.identifier}/contacts/#{contact_inbox.source_id}",
            params: { phone_number: '+5511922220000' }

      expect(response).to have_http_status(:success)
      expect(contact.reload.phone_number).to eq('+5511922220000')
      expect(contact.custom_attributes).to eq(intacto)
    end

    it 'keeps the chat id on the legacy contact import' do
      contact.update!(email: 'cliente@example.com')

      DataImport::ContactManager.new(account).build_contact(
        { email: 'cliente@example.com', phone_number: '+5511922220000' }.with_indifferent_access
      )

      expect(contact.reload.phone_number).to eq('+5511922220000')
      expect(contact.custom_attributes).to eq(intacto)
    end

    it 'keeps the chat id on the contact merge' do
      contact.update!(phone_number: nil)
      mergee = create(:contact, account: account, phone_number: '+5511922220000')

      ContactMergeAction.new(account: account, base_contact: contact, mergee_contact: mergee).perform

      expect(contact.reload.phone_number).to eq('+5511922220000')
      expect(contact.custom_attributes).to include(chat_id)
    end
  end
end
