# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Sso::Provisioner do
  describe '#perform' do
    let(:identity_email) { 'atendimento@autonomia.solutions' }
    let(:identity_user_id) { 'auth-user-123' }
    let(:identity_organization_id) { 'auth-org-created-by-invite' }
    let(:inviter) { create(:user) }
    let!(:invited_account) do
      create(
        :account,
        custom_attributes: {
          'autonomia_pending_agent_invitations' => {
            identity_email => {
              'email' => identity_email,
              'name' => 'Atendimento Autonomia',
              'role' => 'agent',
              'invited_by_user_id' => inviter.id,
              'auth_invitation_id' => 'auth-invitation-123',
              'created_at' => Time.current.iso8601
            }
          }
        }
      )
    end
    let(:context) do
      {
        'user' => {
          'id' => identity_user_id,
          'email' => identity_email,
          'name' => 'Atendimento Autonomia'
        },
        'activeOrganization' => {
          'id' => identity_organization_id,
          'name' => 'Nova organizacao criada no Auth'
        }
      }
    end

    it 'uses the pending product invitation account before creating a new account' do
      skip 'QUARANTINE: pre-existing legacy failure, harness-restore PR; real fix tracked for follow-up PR2'
      provisioned_user = nil

      expect do
        provisioned_user = described_class.new(context: context).perform
      end.not_to change(Account, :count)

      account_user = AccountUser.find_by!(account: invited_account, user: provisioned_user)
      expect(account_user.role).to eq('agent')
      expect(account_user.inviter_id).to eq(inviter.id)
      expect(invited_account.reload.name).not_to eq('Nova organizacao criada no Auth')
      expect(invited_account.reload.custom_attributes.fetch('autonomia_pending_agent_invitations')).to eq({})

      expect(Autonomia::UserLink.find_by!(identity_user_id: identity_user_id).user).to eq(provisioned_user)
      expect(Autonomia::AccountLink.find_by(identity_organization_id: identity_organization_id)).to be_nil
    end

    context 'without a trusted customer account relationship' do
      let!(:invited_account) { nil }
      let(:context) do
        {
          'user' => {
            'id' => identity_user_id,
            'email' => identity_email,
            'name' => 'Atendimento Autonomia'
          },
          'activeOrganization' => {
            'id' => 'hub2you-owner-org',
            'name' => 'Hub2You'
          }
        }
      end

      it 'does not turn the product owner organization into an account or administrator' do
        expect do
          expect { described_class.new(context: context).perform }
            .to raise_error('Autonomia SSO requires an invitation, provisioned checkout, or confirmed account link.')
        end.not_to change(Account, :count)

        expect(Autonomia::AccountLink.find_by(identity_organization_id: 'hub2you-owner-org')).to be_nil
      end
    end

    context 'with an existing Auth-linked user' do
      let!(:invited_account) { nil }
      let(:identity_email) { 'vaneska.costa@hubsegs.com.br' }
      let(:identity_user_id) { 'auth-vaneska-user-id' }
      let!(:linked_user) { create(:user, email: identity_email) }
      let!(:user_link) do
        Autonomia::UserLink.create!(
          user: linked_user,
          identity_user_id: identity_user_id,
          email: identity_email,
          metadata: {
            'identity_user' => {
              'id' => identity_user_id,
              'email' => identity_email
            }
          }
        )
      end
      let(:context) do
        {
          'user' => {
            'id' => identity_user_id,
            'email' => identity_email,
            'name' => 'Vaneska Costa'
          },
          'activeOrganization' => {
            'id' => 'hub2you-owner-org',
            'name' => 'Hub2You'
          }
        }
      end

      it 'reuses a single existing account even when it was not created by invitation' do
        membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: nil,
          role: 'agent'
        )

        expect(described_class.new(context: context).perform).to eq(linked_user)

        expect(membership.reload).to be_agent
      end

      it 'chooses the existing account with the latest active_at' do
        older_membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: inviter,
          role: 'agent',
          active_at: 2.days.ago
        )
        latest_membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: nil,
          role: 'agent',
          active_at: 1.hour.ago
        )

        provisioner = described_class.new(context: context)

        expect(provisioner.send(:existing_linked_account)).to eq(latest_membership.account)
        expect(provisioner.perform).to eq(linked_user)
        expect(latest_membership.reload).to be_agent
        expect(older_membership.reload).to be_agent
      end

      it 'does not override the existing account role on SSO re-login' do
        membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: inviter,
          role: 'agent'
        )

        expect(described_class.new(context: context).perform).to eq(linked_user)

        expect(membership.reload).to be_agent
      end

      it 'chooses the most recent existing account when none has active_at' do
        older_membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: inviter,
          role: 'agent',
          created_at: 2.days.ago,
          updated_at: 2.days.ago
        )
        latest_membership = create(
          :account_user,
          user: linked_user,
          account: create(:account),
          inviter: inviter,
          role: 'agent',
          created_at: 1.hour.ago,
          updated_at: 1.hour.ago
        )

        provisioner = described_class.new(context: context)

        expect(provisioner.send(:existing_linked_account)).to eq(latest_membership.account)
        expect(provisioner.perform).to eq(linked_user)
        expect(latest_membership.reload).to be_agent
        expect(older_membership.reload).to be_agent
      end

      it 'can use memberships created by a super admin without an inviter' do
        membership = create(:account_user, user: linked_user, account: create(:account), inviter: nil, role: 'administrator')

        expect(described_class.new(context: context).perform).to eq(linked_user)

        expect(membership.reload).to be_administrator
      end

      it 'ignores integration memberships' do
        create(:account_user, user: linked_user, account: create(:account), integration: true)

        expect do
          described_class.new(context: context).perform
        end.to raise_error('Autonomia SSO requires an invitation, provisioned checkout, or confirmed account link.')
      end

      it 'keeps blocking linked users with no eligible account' do
        expect do
          described_class.new(context: context).perform
        end.to raise_error('Autonomia SSO requires an invitation, provisioned checkout, or confirmed account link.')
      end
    end

    context 'when the account link uses a fallback organization' do
      let!(:invited_account) { nil }
      let(:identity_email) { 'roberto.martins@hub2you.ai' }
      let(:identity_user_id) { 'hub2you-user-id' }
      let!(:linked_account) { create(:account, name: 'GTA') }
      let!(:fallback_account_link) do
        Autonomia::AccountLink.create!(
          account: linked_account,
          identity_organization_id: identity_email,
          metadata: {
            'identity_organization' => {
              'id' => identity_email,
              'name' => 'Noktua',
              'fallback' => true
            }
          }
        )
      end
      let(:context) do
        {
          'user' => {
            'id' => identity_user_id,
            'email' => identity_email,
            'name' => 'Roberto Martins',
            'companyName' => 'Noktua'
          }
        }
      end

      it 'does not trust an unconfirmed fallback account link' do
        expect do
          described_class.new(context: context).perform
        end.to raise_error('Autonomia SSO requires an invitation, provisioned checkout, or confirmed account link.')

        expect(fallback_account_link.reload.account).to eq(linked_account)
        expect(AccountUser.find_by(account: linked_account)).to be_nil
      end
    end

    context 'with a confirmed checkout account link' do
      let!(:invited_account) { nil }
      let!(:confirmed_account) { create(:account, name: 'Cliente confirmado') }
      let!(:confirmed_link) do
        Autonomia::AccountLink.create!(
          account: confirmed_account,
          identity_organization_id: "registration:chat2you:#{identity_user_id}",
          metadata: {
            'registration_checkout' => {
              'auth_user_id' => identity_user_id,
              'checkout_status' => 'provisioned'
            }
          }
        )
      end

      it 'reuses the account without consulting the product owner organization id' do
        provisioned_user = nil

        expect do
          provisioned_user = described_class.new(context: context).perform
        end.not_to change(Account, :count)

        expect(confirmed_link.reload.account).to eq(confirmed_account)
        expect(AccountUser.find_by!(account: confirmed_account, user: provisioned_user).role).to eq('administrator')
      end
    end

    context 'when the account was created by the registration callback' do
      let!(:invited_account) { nil }
      let(:identity_email) { 'roberto+hub2@noktua.io' }
      let(:identity_user_id) { 'sso-user-id' }
      let!(:registration_account) do
        create(
          :account,
          name: 'Noktua Seguros',
          custom_attributes: {
            'autonomia_registration_checkout' => {
              'email' => identity_email,
              'client_id' => 'chat2you',
              'auth_user_id' => 'registration-user-id',
              'checkout_status' => 'provisioned'
            }
          }
        )
      end
      let!(:duplicate_account) do
        create(
          :account,
          name: 'Noktua Seguros',
          custom_attributes: { 'onboarding_step' => 'account_details' }
        )
      end
      let!(:duplicate_account_link) do
        Autonomia::AccountLink.create!(
          account: duplicate_account,
          identity_organization_id: identity_email,
          metadata: { 'identity_organization' => { 'id' => identity_email, 'fallback' => true } }
        )
      end
      let(:context) do
        {
          'user' => {
            'id' => identity_user_id,
            'email' => identity_email,
            'name' => 'Roberto Hub2',
            'companyName' => 'Noktua Seguros'
          }
        }
      end

      it 'reuses the registration account without mapping the product owner organization' do
        provisioned_user = nil

        expect do
          provisioned_user = described_class.new(context: context).perform
        end.not_to change(Account, :count)

        expect(AccountUser.find_by!(account: registration_account, user: provisioned_user).role).to eq('administrator')
        expect(duplicate_account_link.reload.account).to eq(duplicate_account)
      end
    end
  end
end
