require 'rails_helper'

RSpec.describe CustomRole, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:account_users).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'accepts known permission keys' do
      role = build(:custom_role, permissions: %w[contact_view campaign_manage])

      expect(role).to be_valid
    end

    it 'keeps the accepted keys on the inclusion validator, where tools read them (#900)' do
      inclusion = described_class.validators_on(:permissions).find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }

      expect(inclusion.options[:in]).to eq(CustomRole::PERMISSIONS)
    end

    # #2185: um nome por conta, sem diferenciar maiúsculas nem espaços nas pontas.
    it 'refuses a name already used in the account, ignoring case and surrounding spaces' do
      existing = create(:custom_role, name: 'Vendas')
      role = build(:custom_role, account: existing.account, name: '  vENDAS ')

      expect(role).not_to be_valid
      expect(role.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(role.name).to eq('vENDAS')
    end

    it 'accepts the same name in another account and keeps a role valid against itself' do
      existing = create(:custom_role, name: 'Vendas')

      expect(build(:custom_role, name: 'Vendas')).to be_valid
      expect(existing.reload).to be_valid
    end

    # O índice segura o que a validação não vê: duas gravações ao mesmo tempo.
    it 'refuses a duplicate in the database even when the validation is skipped' do
      existing = create(:custom_role, name: 'Vendas')
      other = create(:custom_role, account: existing.account, name: 'Outra')

      expect { other.update_column(:name, ' vendas ') }.to raise_error(ActiveRecord::RecordNotUnique) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'refuses renaming onto a taken name' do
      existing = create(:custom_role, name: 'Vendas')

      expect(create(:custom_role, account: existing.account, name: 'Suporte').update(name: 'VENDAS ')).to be(false)
    end

    # Nome antigo salvo com espaço nas pontas conta como o mesmo nome, como no índice.
    it 'refuses a name taken by an old row saved with surrounding spaces' do
      existing = create(:custom_role, name: 'Outra')
      existing.update_column(:name, 'Vendas ') # rubocop:disable Rails/SkipsModelValidations

      expect(build(:custom_role, account: existing.account, name: 'vendas')).not_to be_valid
    end

    # A pessoa só aponta para uma função que existe: sem isso, ganhar a função durante a exclusão deixava um id solto.
    it 'keeps account users from pointing to a missing role' do
      account_user = create(:account_user, account: create(:custom_role).account)

      expect { account_user.update_column(:custom_role_id, described_class.maximum(:id).to_i + 1) } # rubocop:disable Rails/SkipsModelValidations
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'saves the name without the surrounding spaces' do
      expect(create(:custom_role, name: '  Suporte  ').reload.name).to eq('Suporte')
    end

    it 'lists the unknown keys and the valid ones' do
      role = build(:custom_role, permissions: %w[contact_view conversation_read_only inbox_38])

      expect(role).not_to be_valid
      message = role.errors[:permissions].first
      expect(message).to include('conversation_read_only, inbox_38')
      expect(message).to include(CustomRole::PERMISSIONS.join(', '))
    end
  end

  describe 'CRM editing keys imply crm_view (#2124)' do
    CustomRole::CRM_EDITING_KEYS.each do |key|
      it "stores crm_view with #{key}" do
        role = create(:custom_role, permissions: [key])

        expect(role.reload.permissions).to contain_exactly(key, 'crm_view')
      end
    end

    it 'keeps a single crm_view' do
      role = create(:custom_role, permissions: %w[crm_view crm_manage_cards])

      expect(role.reload.permissions).to contain_exactly('crm_view', 'crm_manage_cards')
    end

    it 'adds nothing for reports only, sales values or roles without a CRM key' do
      [%w[crm_view_reports], %w[sales_value_view], %w[crm_admin], %w[contact_view], []].each do |keys|
        expect(create(:custom_role, permissions: keys).reload.permissions).to eq(keys)
      end
    end

    it 'adds crm_view when an editing key arrives on update' do
      role = create(:custom_role, permissions: %w[crm_view_reports])

      role.update!(permissions: %w[crm_view_reports crm_export])

      expect(role.reload.permissions).to contain_exactly('crm_view_reports', 'crm_export', 'crm_view')
    end
  end

  describe 'filtered unread count invalidation' do
    let(:account) { create(:account) }
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, users_visibility_changed!: true) }

    before do
      create(:account_user, account: account, user: user, custom_role: custom_role)
      create(:account_user, account: account, user: other_user, custom_role: custom_role)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'invalidates filtered counts for assigned users when permissions change' do
      custom_role.update!(permissions: ['conversation_participating_manage'])

      expect(invalidator).to have_received(:users_visibility_changed!).with(user_ids: contain_exactly(user.id, other_user.id))
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        'account.cache_invalidated',
        kind_of(Time),
        account: account,
        cache_keys: account.cache_keys
      )
    end

    it 'does not invalidate filtered counts when permissions are unchanged' do
      custom_role.update!(name: 'Support manager')

      expect(invalidator).not_to have_received(:users_visibility_changed!)
    end

    it 'invalidates filtered counts for assigned users when the role is deleted' do
      custom_role.destroy!

      expect(invalidator).to have_received(:users_visibility_changed!).with(user_ids: contain_exactly(user.id, other_user.id))
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        'account.cache_invalidated',
        kind_of(Time),
        account: account,
        cache_keys: account.cache_keys
      )
    end
  end
end
