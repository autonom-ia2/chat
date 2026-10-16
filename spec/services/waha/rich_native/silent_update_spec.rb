require 'rails_helper'

# chat#1709 (fase 3, revisão): reação e edição gravadas na caixa WAHA comum não mandam `message_updated` ao conector
# (que o leria como pedido de reenvio); a atividade escondida não vai às integrações da conta.
describe Waha::RichNative::SilentUpdate do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'Até', conversation: conversation, inbox: inbox, account: account,
                     content_attributes: { external_error: nil })
  end

  def inbox_payloads(changes)
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads << payload if kind == :api_inbox_webhook }
    event = Events::Base.new('message.updated', Time.zone.now, message: message, previous_changes: changes)
    WebhookListener.instance.message_updated(event)
    payloads
  end

  it 'does not send the update of a reaction or an edit to the connector' do
    reaction = { 'content_attributes' => [{ 'external_error' => nil }, { 'external_error' => nil, 'reactions' => [{ 'emoji' => '👍' }] }],
                 'updated_at' => [1.minute.ago, Time.current] }
    edit = { 'content' => ['Até', 'Até logo'], 'processed_message_content' => ['Até', 'Até logo'],
             'content_attributes' => [{}, { 'edit_history' => [{ 'content' => 'Até' }], 'edited_at' => 'agora' }] }

    expect(inbox_payloads(reaction)).to be_empty
    expect(inbox_payloads(edit)).to be_empty
  end

  it 'sends any other update as before (status, delete, error, content without history)' do
    [
      { 'status' => %w[sent delivered] },
      { 'content_attributes' => [{}, { 'deleted' => true }] },
      { 'content_attributes' => [{ 'reactions' => [] }, { 'reactions' => [{ 'emoji' => '👍' }], 'external_error' => 'x' }] },
      { 'content' => %w[a b], 'content_attributes' => [{}, { 'reactions' => [] }] }
    ].each do |changes|
      expect(inbox_payloads(changes).size).to eq(1), changes.inspect
    end
  end

  it 'still sends the update of a reaction in a non-WAHA API inbox' do
    api = create(:channel_api, account: account, webhook_url: 'https://n8n.example/hook')
    api_conversation = create(:conversation, inbox: api.inbox, account: account)
    other = create(:message, message_type: :outgoing, content: 'oi', conversation: api_conversation, inbox: api.inbox, account: account)
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads << payload if kind == :api_inbox_webhook }
    changes = { 'content_attributes' => [{}, { 'reactions' => [{ 'emoji' => '👍' }] }] }

    WebhookListener.instance.message_updated(Events::Base.new('message.updated', Time.zone.now, message: other, previous_changes: changes))

    expect(payloads.size).to eq(1)
  end

  describe Waha::RichNative::HiddenActivityHooks do
    it 'does not send the hidden activity to the account integrations' do
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      hidden = create(:message, message_type: :activity, content: 'Reação registrada', conversation: conversation, inbox: inbox,
                                account: account)
      hidden.update_column(:content_attributes, { 'c2y_hidden' => true }) # rubocop:disable Rails/SkipsModelValidations
      visible = create(:message, message_type: :activity, content: 'Ligação perdida', conversation: conversation, inbox: inbox,
                                 account: account)

      expect { HookListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: hidden.reload)) }
        .not_to have_enqueued_job(HookJob)
      expect { HookListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: visible)) }
        .to have_enqueued_job(HookJob).with(hook, 'message.created', anything)
    end
  end
end
