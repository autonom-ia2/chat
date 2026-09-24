require 'rails_helper'

RSpec.describe Enterprise::AuditLog do
  let(:account) { create(:account).tap { |record| record.enable_features!(:ip_lookup) } }
  let(:inbox) { create(:inbox, account: account) }

  describe 'ip lookup enqueue' do
    it 'enqueues the lookup job on create when remote_address is present' do
      expect do
        described_class.create!(auditable: inbox, action: 'update', associated: account, remote_address: '8.8.8.8')
      end.to have_enqueued_job(Enterprise::AuditLogIpLookupJob)
    end

    it 'does not enqueue the lookup job when remote_address is blank' do
      expect do
        described_class.create!(auditable: inbox, action: 'update', associated: account)
      end.not_to have_enqueued_job(Enterprise::AuditLogIpLookupJob)
    end

    it 'does not enqueue the lookup job when the account has not enabled ip_lookup' do
      opted_out = create(:account)

      expect do
        described_class.create!(auditable: create(:inbox, account: opted_out), action: 'update',
                                associated: opted_out, remote_address: '8.8.8.8')
      end.not_to have_enqueued_job(Enterprise::AuditLogIpLookupJob)
    end
  end

  describe '#location' do
    it 'joins city and country' do
      audit = described_class.new(city: 'Berlin', country: 'Germany')
      expect(audit.location).to eq('Berlin, Germany')
    end

    it 'returns the present part when one is missing' do
      expect(described_class.new(country: 'Germany').location).to eq('Germany')
    end

    it 'returns nil when both are missing' do
      expect(described_class.new.location).to be_nil
    end

    it 'ignores blank parts instead of leaving a trailing separator' do
      expect(described_class.new(city: 'London', country: '').location).to eq('London')
      expect(described_class.new(city: '', country: '').location).to be_nil
    end
  end

  # #644 — antes, search_by_user só olhava para quem fez a ação (audits.user_id
  # / audits.username). Buscar pelo nome de quem foi convidado, promovido ou
  # adicionado a um time/caixa não retornava nada.
  describe '.search_by_user' do
    let(:author) { create(:user, name: 'Lia Admin', email: 'lia@example.com') }

    it 'still finds by the author (username, name or email) — regressão' do
      audit = described_class.create!(auditable: inbox, action: 'update', user: author, associated: account)

      expect(described_class.search_by_user('Lia').pluck(:id)).to contain_exactly(audit.id)
      expect(described_class.search_by_user('lia@example.com').pluck(:id)).to contain_exactly(audit.id)
      expect(described_class.search_by_user('nobody-matches-this')).to be_empty
    end

    it 'finds the invitee of an AccountUser create by name or email' do
      invitee = create(:user, name: 'Marcos Andrade', email: 'marcos@example.com')
      audit = described_class.create!(
        auditable_type: 'AccountUser', auditable_id: 999, action: 'create',
        user: author, associated: account,
        audited_changes: { 'user_id' => invitee.id, 'role' => 0 }
      )

      expect(described_class.search_by_user('Marcos').pluck(:id)).to contain_exactly(audit.id)
      expect(described_class.search_by_user('marcos@example.com').pluck(:id)).to contain_exactly(audit.id)
    end

    it 'finds the affected agent of an AccountUser role/availability update, whose ' \
       'user_id is not in the diff' do
      affected = create(:user, name: 'Marcos Andrade')
      account_user = create(:account_user, account: account, user: affected, role: 'agent')
      audit = described_class.create!(
        auditable_type: 'AccountUser', auditable_id: account_user.id, action: 'update',
        user: author, associated: account,
        audited_changes: { 'role' => [0, 1] }
      )

      # O create do account_user acima também gera um audit (o convite) que cita
      # Marcos; aqui só importa que o update, sem user_id no diff, apareça.
      expect(described_class.search_by_user('Marcos').pluck(:id)).to include(audit.id)
    end

    it 'does not blow up when the AccountUser of an update was since deleted' do
      audit = described_class.create!(
        auditable_type: 'AccountUser', auditable_id: 424_242, action: 'update',
        user: author, associated: account,
        audited_changes: { 'role' => [0, 1] }
      )

      expect(described_class.search_by_user('Marcos').pluck(:id)).not_to include(audit.id)
      expect(described_class.search_by_user('Lia').pluck(:id)).to contain_exactly(audit.id)
    end

    it 'finds the member added to an inbox' do
      member = create(:user, name: 'Marcos Andrade')
      audit = described_class.create!(
        auditable_type: 'InboxMember', auditable_id: 1, action: 'create',
        user: author, associated: account,
        audited_changes: { 'id' => 1, 'inbox_id' => inbox.id, 'user_id' => member.id }
      )

      expect(described_class.search_by_user('Marcos').pluck(:id)).to contain_exactly(audit.id)
    end

    it 'finds the member removed from a team' do
      member = create(:user, name: 'Marcos Andrade')
      team = create(:team, account: account)
      audit = described_class.create!(
        auditable_type: 'TeamMember', auditable_id: 1, action: 'destroy',
        user: author, associated: account,
        audited_changes: { 'id' => 1, 'team_id' => team.id, 'user_id' => member.id }
      )

      expect(described_class.search_by_user('Marcos').pluck(:id)).to contain_exactly(audit.id)
    end

    it 'does not match an unrelated agent, even if that agent authored other audits' do
      unrelated = create(:user, name: 'Unrelated Person')
      create(:account_user, account: account, user: unrelated, role: 'agent')
      described_class.create!(auditable: inbox, action: 'update', user: unrelated, associated: account)

      expect(described_class.search_by_user('Marcos Andrade')).to be_empty
    end
  end

  describe '#masked_remote_address' do
    it 'masks the last octet of an IPv4 address' do
      expect(described_class.new(remote_address: '203.0.113.42').masked_remote_address).to eq('203.0.113.x')
    end

    it 'keeps the first four hextets of an IPv6 address' do
      audit = described_class.new(remote_address: '2001:0db8:85a3:0000:0000:8a2e:0370:7334')
      expect(audit.masked_remote_address).to eq('2001:0db8:85a3:0000::')
    end

    it 'expands a compressed IPv6 address before masking so host bits do not leak' do
      masked = described_class.new(remote_address: '2001:db8::1').masked_remote_address
      expect(masked).to eq('2001:0db8:0000:0000::')
      expect(masked).not_to include('::1')
    end

    it 'returns nil for a blank address' do
      expect(described_class.new(remote_address: nil).masked_remote_address).to be_nil
    end

    it 'returns nil for a malformed address' do
      expect(described_class.new(remote_address: 'not-an-ip').masked_remote_address).to be_nil
    end
  end
end
