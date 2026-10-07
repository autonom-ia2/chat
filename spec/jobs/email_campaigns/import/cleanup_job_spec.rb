require 'rails_helper'

# Limpeza (#1099, entrega B): importações que ninguém salvou saem 7 dias depois, com as imagens copiadas; a salva fica,
# porque as imagens do modelo em "Meus modelos" são anexos dela.
RSpec.describe EmailCampaigns::Import::CleanupJob, :aggregate_failures do
  it 'removes unsaved imports past their expiry and keeps the saved ones' do
    expired = EmailCampaignTemplateImport.create!(account: create(:account), source_kind: 'paste', status: 'ready', expires_at: 1.minute.ago)
    expired.images.attach(io: StringIO.new('png'), filename: 'imagem-1.png', content_type: 'image/png')
    fresh = EmailCampaignTemplateImport.create!(account: create(:account), source_kind: 'paste', status: 'ready')
    saved = EmailCampaignTemplateImport.create!(account: create(:account), source_kind: 'paste', status: 'saved', expires_at: 1.minute.ago)

    described_class.perform_now

    expect(EmailCampaignTemplateImport.where(id: [expired.id, fresh.id, saved.id]).pluck(:id)).to contain_exactly(fresh.id, saved.id)
    expect(ActiveStorage::Attachment.where(record_type: 'EmailCampaignTemplateImport', record_id: expired.id)).to be_empty
  end

  it 'runs on the housekeeping queue' do
    expect(described_class.new.queue_name).to eq('housekeeping')
  end
end
