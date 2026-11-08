require 'rails_helper'

# #2521: a resposta da pessoa ao privado de um comentário de anúncio liga a conversa ao anúncio.
RSpec.describe Crm::MetaAds::CommentLinkJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:ad_id) { '120254710067060999' }

  def private_reply(comment_id: 'c-1', ad_of_comment: ad_id)
    Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: comment_id, ad_id: ad_of_comment, action: 'private_reply',
                                      actor: 'ai', conversation_id: conversation.id, at: 1.hour.ago, confirmed_at: 1.hour.ago)
  end

  def incoming
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming)
  end

  it 'pending?: só com privado de anúncio confirmado e ainda sem ligação' do
    expect(described_class.pending?(conversation)).to be(false)
    private_reply(ad_of_comment: nil)
    expect(described_class.pending?(conversation)).to be(false)

    private_reply(comment_id: 'c-2')
    expect(described_class.pending?(conversation)).to be(true)

    incoming
    described_class.perform_now(conversation.id)
    expect(described_class.pending?(conversation)).to be(false)
  end

  it 'liga a conversa ao anúncio pela resposta da pessoa' do
    create_meta_ads_insights_connection(account)
    private_reply
    incoming

    described_class.perform_now(conversation.id)

    expect(Crm::MetaAdLink.sole).to have_attributes(conversation_id: conversation.id, origin: 'comment', ad_id: ad_id, certainty: 'ad')
  end

  it 'o listener enfileira na mensagem da pessoa, e não na mensagem que sai nem sem privado' do
    listener = Crm::MetaAdsCommentLinkListener.instance
    event = ->(message) { Events::Base.new('message.created', Time.zone.now, message: message) }
    outgoing = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing)

    expect { listener.message_created(event.call(incoming)) }.not_to have_enqueued_job(described_class)

    private_reply
    expect { listener.message_created(event.call(outgoing)) }.not_to have_enqueued_job(described_class)
    expect { listener.message_created(event.call(incoming)) }.to have_enqueued_job(described_class).with(conversation.id)
  end
end
