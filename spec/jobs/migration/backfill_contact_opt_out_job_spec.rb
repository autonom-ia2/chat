require 'rails_helper'

RSpec.describe Migration::BackfillContactOptOutJob do
  it 'vai para a fila de migração de dados' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('async_database_migration')
  end

  it 'marca o contato de lead legado recusado em cada conta, e a falha de uma conta não para as outras' do
    broken = create(:account)
    account = create(:account)
    contact = account.contacts.create!(name: 'Do lead', phone_number: '+5531999970071')
    [broken, account].each do |target|
      lead = Autonomia::Prospecting::Lead.create!(account: target, provider: 'mock', provider_place_id: "job-#{target.id}",
                                                  name: 'Lead antigo', phone: '+5531999970071', country: 'BR', status: :no_consent)
      lead.update_columns(consent_refused_at: lead.updated_at) # rubocop:disable Rails/SkipsModelValidations
    end
    allow(Contacts::OptOutBackfill).to receive(:new).and_call_original
    allow(Contacts::OptOutBackfill).to receive(:new).with(account: broken).and_raise(ActiveRecord::StatementInvalid, 'falha')

    described_class.perform_now

    expect(contact.reload.opt_out_source).to eq('prospecting')
  end
end
