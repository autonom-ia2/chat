require 'rails_helper'

# #1822: a template or campaign keeps the images its body shows, so deleting the draft, the import or the
# old logo that uploaded them no longer leaves the e-mail with broken images.
RSpec.describe RetainsEmailImages do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:source) { create(:email_campaign, account: account, status: :draft) }

  def upload(name = 'banner.png')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('image-bytes'), filename: name, content_type: 'image/png')
  end

  def image_url(blob)
    "https://chat.example.com#{Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)}"
  end

  def image_html(blob)
    %(<img src="#{image_url(blob)}" alt="">)
  end

  def campaign_image
    upload.tap { |blob| source.builder_assets.attach(blob) }
  end

  it 'keeps a template image after the campaign that uploaded it is deleted' do
    blob = campaign_image
    template = EmailCampaignTemplate.create!(account: account, name: 'Convite', body_html: image_html(blob))

    perform_enqueued_jobs { source.destroy! }

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    expect(template.reload.builder_assets.blobs).to contain_exactly(blob)
  end

  it 'keeps a duplicated campaign image after the original draft is deleted' do
    blob = campaign_image
    copy = create(:email_campaign, account: account, status: :draft, sender_identity: source.sender_identity,
                                   body_mjml: %(<mjml><mj-body><mj-image src="#{image_url(blob)}" /></mj-body></mjml>))

    perform_enqueued_jobs { source.destroy! }

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    expect(copy.reload.builder_assets.blobs).to contain_exactly(blob)
  end

  it 'still purges an image no other e-mail shows' do
    blob = campaign_image

    perform_enqueued_jobs { source.destroy! }

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  it 'keeps a brand kit logo the AI wrote into the body after the logo is replaced' do
    kit = create(:brand_kit, account: account)
    kit.logo.attach(upload('logo.png'))
    logo = kit.logo.blob
    token = source.ai_begin!

    source.ai_succeed!(token, { subject: 'Oi', body_mjml: %(<mjml><mj-body><mj-image src="#{image_url(logo)}" /></mj-body></mjml>) })
    perform_enqueued_jobs { kit.logo.attach(upload('logo-novo.png')) }

    expect(ActiveStorage::Blob.exists?(logo.id)).to be(true)
    expect(source.reload.builder_assets.blobs).to include(logo)
  end

  it 'keeps an imported template image after the import expires, and never takes the original file' do
    import = EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste')
    image = upload.tap { |blob| import.images.attach(blob) }
    original = upload('original.html').tap { |blob| import.source.attach(blob) }
    template = EmailCampaignTemplate.create!(account: account, name: 'Importado',
                                             body_html: image_html(image) + image_html(original))

    perform_enqueued_jobs { import.destroy! }

    expect(ActiveStorage::Blob.exists?(image.id)).to be(true)
    expect(template.reload.builder_assets.blobs).to contain_exactly(image)
  end

  it 'ignores an image owned by another account' do
    foreign = create(:email_campaign, status: :draft)
    blob = upload.tap { |image| foreign.builder_assets.attach(image) }

    template = EmailCampaignTemplate.create!(account: account, name: 'Colado', body_html: image_html(blob))

    expect(template.reload.builder_assets).to be_empty
  end

  it 'attaches an image once even when the body is saved again' do
    blob = campaign_image
    template = EmailCampaignTemplate.create!(account: account, name: 'Convite', body_html: image_html(blob))

    template.update!(body_html: "#{image_html(blob)}<p>novo texto</p>")

    expect(template.reload.builder_assets.attachments.count).to eq(1)
  end

  it 'leaves global gallery templates alone' do
    blob = campaign_image

    template = EmailCampaignTemplate.create!(account: nil, name: 'Galeria', body_html: image_html(blob))

    expect(template.reload.builder_assets).to be_empty
  end
end
