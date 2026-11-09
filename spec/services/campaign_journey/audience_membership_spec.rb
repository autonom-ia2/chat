require 'rails_helper'

# #2775: pôr e tirar pessoas de um Público que já existe, sem repetir contato e sem apagar linha.
RSpec.describe CampaignJourney::AudienceMembership do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:contact, account: account, name: 'Ana', phone_number: '+5511987654321') }
  let(:bia) { create(:contact, account: account, name: 'Bia', email: 'bia@example.com') }
  let(:caio) { create(:contact, account: account, name: 'Caio', phone_number: '+5511987650000', email: 'caio@example.com') }
  let(:audience) { CampaignJourney::AudienceWriter.new(account, user: user, source: 'prospecting').perform('Lista', [row(ana)]) }

  def row(contact)
    CampaignJourney::AudienceWriter::Row.new(contact_id: contact.id, name: contact.name, phone: ConversationAudience::Reach.phone(contact),
                                             email: ConversationAudience::Reach.email(contact), company_name: nil, extra_values: {})
  end

  def lines
    audience.campaign_import_rows.order(:row_number)
  end

  describe '.add' do
    it 'acrescenta no fim, com row_number = maior + 1, e acerta contadores e canais' do
      result = described_class.add(audience, [row(bia), row(caio)])

      expect(result.added_contact_ids).to eq([bia.id, caio.id])
      expect(lines.map { |line| [line.contact_id, line.row_number, line.status] })
        .to eq([[ana.id, 1, 'imported'], [bia.id, 2, 'imported'], [caio.id, 3, 'imported']])
      expect(audience.reload).to have_attributes(total_rows: 3, valid_rows: 3, imported_contacts_count: 3, existing_contacts_count: 3)
      expect(audience.channels).to include('whatsapp' => { 'enabled' => true, 'count' => 2 }, 'email' => { 'enabled' => true, 'count' => 2 })
    end

    it 'quem já está não entra de novo nem ganha outra linha' do
      result = described_class.add(audience, [row(ana), row(bia), row(bia)])

      expect(result.added_contact_ids).to eq([bia.id])
      expect(result.skipped_contact_ids).to eq([ana.id])
      expect(lines.where(contact_id: ana.id).count).to eq(1)
      expect(audience.reload.valid_rows).to eq(2)
    end

    it 'liga o canal que estava em zero e ganhou gente (o e-mail do Público só de telefone)' do
      expect(audience.channels.dig('email', 'enabled')).to be(false)

      described_class.add(audience, [row(bia)])

      expect(audience.reload.channels['email']).to eq('enabled' => true, 'count' => 1)
    end

    it 'recusa contato de outra conta' do
      foreign = create(:contact, account: create(:account), phone_number: '+5511911112222')

      expect { described_class.add(audience, [row(foreign)]) }.to raise_error(described_class::Error, 'foreign_contact')
    end

    it 'recusa o que não é Público' do
      contacts_import = account.campaign_imports.create!(user: user, status: :completed, mode: 'single_label', name: 'X',
                                                         campaign_name: 'X', options: { 'flow' => CampaignImport::CONTACTS_FLOW })

      expect { described_class.add(contacts_import, [row(bia)]) }.to raise_error(described_class::Error, 'not_audience')
    end
  end

  describe '.remove' do
    it 'a linha fica como removed, sai da contagem, do envio e da amostra' do
      described_class.add(audience, [row(bia)])

      result = described_class.remove(audience.reload, [ana.id])

      expect(result.removed_contact_ids).to eq([ana.id])
      expect(lines.find_by(contact_id: ana.id).status).to eq('removed')
      expect(audience.reload).to have_attributes(total_rows: 1, valid_rows: 1, imported_contacts_count: 1)
      expect(audience.channels.dig('whatsapp', 'count')).to eq(0)
      expect(CampaignJourney::AudienceContacts.whatsapp_contact_ids(audience, account: account)).to eq([])
      expect(CampaignJourney::AudienceContacts.email_matches(audience, account: account).map(&:contact_id)).to eq([bia.id])
      expect(CampaignImports::AudienceReachability::ROW_STATUSES).not_to include(:removed)
    end

    it 'tirar quem não está não muda nada' do
      expect(described_class.remove(audience, [bia.id]).removed_contact_ids).to eq([])
      expect(audience.reload.valid_rows).to eq(1)
    end

    it 'tirar e pôr de novo reativa a MESMA linha, com o telefone de agora' do
      described_class.add(audience, [row(bia)])
      described_class.remove(audience.reload, [ana.id])
      ana.update!(phone_number: '+5511933334444')

      described_class.add(audience.reload, [row(ana)])

      line = lines.where(contact_id: ana.id).sole
      expect(line).to have_attributes(row_number: 1, status: 'imported',
                                      normalized_phone_hash: ConversationAudience::Reach.phone(ana).hash)
      expect(audience.reload).to have_attributes(valid_rows: 2, total_rows: 2)
      expect(CampaignJourney::AudienceContacts.whatsapp_contact_ids(audience, account: account)).to eq([ana.id])
    end
  end

  describe 'Público já enviado' do
    before do
      campaign = create(:campaign, account: account)
      campaign.update_columns(campaign_status: Campaign.campaign_statuses['completed']) # rubocop:disable Rails/SkipsModelValidations
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    end

    it 'não acrescenta nem tira' do
      expect { described_class.add(audience, [row(bia)]) }.to raise_error(described_class::Error, 'audience_locked')
      expect { described_class.remove(audience, [ana.id]) }.to raise_error(described_class::Error, 'audience_locked')
      expect(lines.map(&:status)).to eq(['imported'])
    end
  end
end
