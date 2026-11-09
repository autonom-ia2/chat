require 'rails_helper'

# #1006: creating the new attributes survives another import (or a person) creating the same
# key between the lookup and the insert. merge! does not lose the keys another writer saved on the
# same contact after it was loaded (#2771: one automation run per message).
RSpec.describe ContactImports::CustomAttributes, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:campaign_import) do
    create_contact_import(account: account, user: account_and_user.last, content: "Nome,Celular\n").tap do |contact_import|
      contact_import.update!(extra_columns: ['Plano'])
    end
  end

  # The other writer committed its attribute after our lookup said "not there".
  def created_in_between!
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'plano',
                                                 attribute_display_name: 'Plano (outro)', attribute_display_type: :text)
    allow_any_instance_of(ActiveRecord::AssociationRelation).to receive(:exists?).and_return(false) # rubocop:disable RSpec/AnyInstance
  end

  def plano_names
    account.custom_attribute_definitions.where(attribute_key: 'plano').pluck(:attribute_display_name)
  end

  it 'uses the existing attribute when the unique index refuses the insert' do
    created_in_between!
    allow_any_instance_of(CustomAttributeDefinition).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique, 'duplicate key') # rubocop:disable RSpec/AnyInstance

    expect(described_class.new(campaign_import).prepare!).to eq(0)
    expect(plano_names).to eq(['Plano (outro)'])
  end

  it 'uses the existing attribute when the uniqueness validation sees it first' do
    created_in_between!

    expect(described_class.new(campaign_import).prepare!).to eq(0)
    expect(plano_names).to eq(['Plano (outro)'])
  end

  it 'merge! reads the contact again under lock: a write made after the contact was loaded is kept' do
    described_class.new(campaign_import).prepare!
    contact = create(:contact, account: account, custom_attributes: {})
    stale = Contact.find(contact.id)
    Contact.find(contact.id).update!(custom_attributes: { 'outro' => 'da outra execução' }) # the other writer, after our read

    described_class.new(campaign_import).merge!(stale, { 'Plano' => 'Ouro' })

    expect(contact.reload.custom_attributes).to eq('outro' => 'da outra execução', 'plano' => 'Ouro')
  end

  it 'merge! keeps the value the other writer gave to the same key' do
    described_class.new(campaign_import).prepare!
    contact = create(:contact, account: account, custom_attributes: {})
    stale = Contact.find(contact.id)
    Contact.find(contact.id).update!(custom_attributes: { 'plano' => 'Prata' })

    described_class.new(campaign_import).merge!(stale, { 'Plano' => 'Ouro' })

    expect(contact.reload.custom_attributes).to eq('plano' => 'Prata')
  end

  it 'creates the attribute when nobody did' do
    expect(described_class.new(campaign_import).prepare!).to eq(1)
    expect(account.custom_attribute_definitions.find_by(attribute_key: 'plano')).to have_attributes(attribute_display_type: 'text')
  end
end
