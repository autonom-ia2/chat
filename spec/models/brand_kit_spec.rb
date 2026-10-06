require 'rails_helper'

RSpec.describe BrandKit do
  let(:account) { create(:account) }

  it 'stores the normalized appearance and drops unknown keys' do
    kit = create(:brand_kit, account: account, appearance: attributes_for(:brand_kit)[:appearance].merge(unknown: 'x'))

    expect(kit.reload.appearance.keys).not_to include('unknown')
    expect(kit.appearance.dig('typography', 'fallback')).to eq('Arial, Helvetica, sans-serif')
  end

  it 'is invalid with a malformed palette color' do
    kit = build(:brand_kit, account: account)
    kit.appearance = kit.appearance.deep_merge('palette' => { 'primary' => 'blue' })

    expect(kit).not_to be_valid
    expect(kit.errors[:appearance].join).to include('palette.primary')
  end

  it 'keeps names unique per account among live kits, case-insensitively' do
    create(:brand_kit, account: account, name: 'Hub2You')

    expect(build(:brand_kit, account: account, name: 'hub2you ')).not_to be_valid
    expect(build(:brand_kit, name: 'Hub2You')).to be_valid
  end

  it 'frees the name once the kit is archived' do
    kit = create(:brand_kit, account: account, name: 'Hub2You')
    kit.archive!

    expect(build(:brand_kit, account: account, name: 'Hub2You')).to be_valid
  end

  describe 'one default per account' do
    it 'moves the default flag and keeps a single default' do
      first = create(:brand_kit, account: account)
      second = create(:brand_kit, account: account)

      first.make_default!
      second.make_default!

      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
      expect(described_class.where(account: account, is_default: true).count).to eq(1)
    end

    it 'is enforced by the database too' do
      create(:brand_kit, account: account, is_default: true)
      other = create(:brand_kit, account: account)

      expect { other.update!(is_default: true) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'clears the default when archiving and refuses to make an archived kit the default' do
      kit = create(:brand_kit, account: account, is_default: true)
      kit.archive!

      expect(kit.reload.is_default).to be(false)
      expect(kit.archived_at).to be_present
      expect { kit.make_default! }.to raise_error(BrandKit::ArchivedError)
    end
  end

  it 'only accepts a raster logo' do
    kit = create(:brand_kit, account: account)
    kit.logo.attach(io: StringIO.new('<svg></svg>'), filename: 'logo.svg', content_type: 'image/svg+xml')

    expect(kit).not_to be_valid
    expect(kit.errors[:logo]).to be_present
  end
end
