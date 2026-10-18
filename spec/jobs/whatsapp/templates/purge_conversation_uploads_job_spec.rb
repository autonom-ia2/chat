require 'rails_helper'

# #1716: a foto do computador da conversa é só para o envio. A que nunca foi usada sai depois de um dia; a usada num
# envio fica (a conversa mostra o que foi enviado), e nenhum outro arquivo é tocado.
RSpec.describe Whatsapp::Templates::PurgeConversationUploadsJob do
  def blob(metadata, age: 2.days)
    created = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'foto.png', content_type: 'image/png',
                                                     metadata: metadata)
    created.update_columns(created_at: age.ago) # rubocop:disable Rails/SkipsModelValidations
    created
  end

  it 'purges only the unused conversation photos older than a day' do
    unused = blob({ 'account_id' => 1, 'conversation_upload' => true })
    sent = blob({ 'account_id' => 1, 'conversation_upload' => true, 'conversation_sent' => true })
    fresh = blob({ 'account_id' => 1, 'conversation_upload' => true }, age: 1.hour)
    campaign = blob({ 'account_id' => 1 })
    attached = blob({ 'account_id' => 1, 'conversation_upload' => true })
    create(:contact).avatar.attach(attached)

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActiveStorage::Blob.where(id: unused.id)).not_to exist
    expect(ActiveStorage::Blob.where(id: [sent.id, fresh.id, campaign.id, attached.id]).count).to eq(4)
  end
end
