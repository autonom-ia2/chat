require 'rails_helper'

# Importar contatos (#1006, PRD §8.7, Q1–Q3, C1/C4/C5): validated by ContactImports::Validator
# (the audience validator, same SpreadsheetReader) and saved by CampaignImports::Importer.
RSpec.describe ContactImports::Validator, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 } }
  let(:header) { "Segurado,Celular,Email,Corretora,Vencimento,Plano\n" }

  before { account.enable_features!('companies') }

  def contact_import(lines, create_companies: nil)
    campaign_import = create_contact_import(account: account, user: user, content: "#{header}#{lines.join("\n")}\n")
    campaign_import.update!(options: campaign_import.options.merge('create_companies' => create_companies)) unless create_companies.nil?
    validate_contact_import(campaign_import, mapping)
  end

  def phone(index)
    "1198765#{format('%04d', index)}"
  end

  describe 'Q1: the same reading service as Públicos' do
    it 'reads through SpreadsheetReader and sends Jev only headers, counts and masked formats' do
      enable_audience_jev
      requests = stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'column_3')
      allow(CampaignImports::SpreadsheetReader).to receive(:new).and_call_original
      content = "Segurado;Celular;Email;Corretora;Vencimento\nAna Souza;(11) 98765-4321;ana.souza@example.org;Alfa Corretora;10/2026\n"
      campaign_import = create_contact_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      expect(CampaignImports::SpreadsheetReader).to have_received(:new).once
      expect(campaign_import.reload).to be_ready_to_confirm
      expect(campaign_import.schema_resolution['method']).to eq('jev')
      expect(requests.size).to eq(1)
      expect(requests.first.dig('state', 'headers')).to eq(%w[Segurado Celular Email Corretora Vencimento])
      body = requests.to_json
      expect(body).not_to include('Ana', 'Souza', '98765', '4321', 'ana.souza', 'example.org', 'Alfa', '10/2026', '@')
    end
  end

  describe 'Q3: Jev off or unavailable' do
    let(:content) { "Nome,Celular,Email\nAna,11987654321,ana@x.com.br\n" }

    it 'asks for the columns when Jev is off, with known headers only as a suggestion' do
      campaign_import = create_contact_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_needs_column_choice
      expect(campaign_import.schema_resolution).to include('method' => 'deterministic', 'needs_confirmation' => true)
      expect(campaign_import.schema_resolution['jev']).to eq('status' => 'disabled')
      expect(campaign_import.schema_resolution['targets']['phone']).to include('column' => 1, 'source' => 'alias', 'confident' => false)
      expect(account.contacts.count).to eq(0)
    end

    it 'asks for the columns when Jev fails, without an error and without creating contacts' do
      enable_audience_jev
      stub_request(:post, AudienceJevHelpers::JEV_URL).to_return(status: 503, body: 'down')
      campaign_import = create_contact_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_needs_column_choice
      expect(campaign_import.schema_resolution['jev']).to include('status' => 'failed')
      expect(campaign_import.validation_summary['errors']).to eq({})
      expect(account.contacts.count).to eq(0)
    end
  end

  describe 'Q2: custom attributes' do
    it 'previews the attributes, creates the new ones and writes the values on the contacts' do
      account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'vencimento',
                                                   attribute_display_name: 'Vencimento', attribute_display_type: :text)
      campaign_import = contact_import(["Ana,#{phone(1)},,Alfa,10/2026,Ouro", "Bia,#{phone(2)},,,,Prata"])

      expect(campaign_import.validation_summary['contact_attributes']).to eq(
        [
          { 'column' => 'Vencimento', 'key' => 'vencimento', 'label' => 'Vencimento', 'existing' => true, 'type' => 'text' },
          { 'column' => 'Plano', 'key' => 'plano', 'label' => 'Plano', 'existing' => false, 'type' => 'text' }
        ]
      )
      expect(account.custom_attribute_definitions.where(attribute_key: 'plano')).to be_empty

      import_contacts!(campaign_import)

      expect(campaign_import).to be_completed
      plano = account.custom_attribute_definitions.find_by(attribute_key: 'plano')
      expect(plano).to have_attributes(attribute_model: 'contact_attribute', attribute_display_name: 'Plano', attribute_display_type: 'text')
      expect(campaign_import.validation_summary['contact_attributes_created']).to eq(1)
      expect(account.contacts.order(:name).pluck(:name, :custom_attributes)).to eq(
        [['Ana', { 'vencimento' => '10/2026', 'plano' => 'Ouro' }], ['Bia', { 'plano' => 'Prata' }]]
      )
    end

    it 'fills only what an existing contact lacks and keeps its own values' do
      existing = account.contacts.create!(name: '', phone_number: "+55#{phone(1)}", custom_attributes: { 'plano' => 'Diamante' })
      campaign_import = contact_import(["Ana,#{phone(1)},ana@alfa.com.br,,10/2026,Ouro"])

      expect(campaign_import.validation_summary['existing_contacts']).to eq(1)

      import_contacts!(campaign_import)

      existing.reload
      expect(account.contacts.count).to eq(1)
      expect(existing).to have_attributes(name: 'Ana', email: 'ana@alfa.com.br')
      expect(existing.custom_attributes).to eq('plano' => 'Diamante', 'vencimento' => '10/2026')
      expect(campaign_import.existing_contacts_count).to eq(1)
    end

    it 'reuses a contact saved without the ninth digit and creates no label' do
      existing = account.contacts.create!(name: 'Ana', phone_number: '+551187654321')
      campaign_import = contact_import(['Ana,+5511987654321,,,,'])

      expect { import_contacts!(campaign_import) }.not_to change(Label, :count)

      expect(account.contacts.sole).to eq(existing)
      expect(campaign_import.campaign_import_labels).to be_empty
      expect(campaign_import.campaign_import_rows.sole).to have_attributes(contact_id: existing.id, labels_applied: [])
    end
  end

  describe 'Q2: typed attributes' do
    it 'converts values to the attribute type and leaves out, per row, the ones that do not fit' do
      account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'vencimento',
                                                   attribute_display_name: 'Vencimento', attribute_display_type: :date)
      account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'plano',
                                                   attribute_display_name: 'Plano', attribute_display_type: :list,
                                                   attribute_values: %w[Ouro Prata])
      campaign_import = contact_import(["Ana,#{phone(1)},,,15/03/2026,ouro", "Bia,#{phone(2)},,,amanhã,Bronze"])

      expect(campaign_import.validation_summary['attribute_problems']).to eq(
        'count' => 2, 'kept' => 0, 'by_attribute' => { 'Vencimento' => 1, 'Plano' => 1 },
        'rows' => [{ 'row_number' => 3, 'attribute' => 'Vencimento' }, { 'row_number' => 3, 'attribute' => 'Plano' }]
      )
      expect(campaign_import.validation_summary['contact_attributes'].pluck('type')).to eq(%w[date list])
      expect(campaign_import.validation_summary.to_json).not_to include('amanhã', 'Bronze')

      import_contacts!(campaign_import)

      expect(campaign_import).to be_completed
      expect(account.contacts.order(:name).pluck(:name, :custom_attributes)).to eq(
        [['Ana', { 'vencimento' => '2026-03-15', 'plano' => 'Ouro' }], ['Bia', {}]]
      )
    end
  end

  describe 'Q2: values a contact already has' do
    it 'counts them as kept, not as left out' do
      account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'vencimento',
                                                   attribute_display_name: 'Vencimento', attribute_display_type: :date)
      account.contacts.create!(name: 'Ana', phone_number: "+55#{phone(1)}", custom_attributes: { 'vencimento' => '2025-01-01', 'plano' => 'Ouro' })
      campaign_import = contact_import(["Ana,#{phone(1)},,,amanhã,Prata", "Bia,#{phone(2)},,,amanhã,Prata"])

      expect(campaign_import.validation_summary['attribute_problems']).to include(
        'count' => 1, 'kept' => 2, 'rows' => [{ 'row_number' => 3, 'attribute' => 'Vencimento' }]
      )
    end
  end

  describe 'Q2: companies with the C1–C7 rules' do
    # C1
    it 'creates one company for ten rows with the same name and links the ten contacts' do
      campaign_import = contact_import(Array.new(10) { |i| "Pessoa #{i},#{phone(i)},,Alfa Corretora,," })

      expect(campaign_import.validation_summary['companies']).to include('companies_created' => 1, 'contacts_linked' => 10)

      import_contacts!(campaign_import)

      company = account.companies.sole
      expect(company.name).to eq('Alfa Corretora')
      expect(account.contacts.pluck(:company_id).uniq).to eq([company.id])
      expect(campaign_import.companies_created_count).to eq(1)
      expect(campaign_import.company_contacts_linked_count).to eq(10)
    end

    # C4
    it 'keeps the company a contact already has and counts it as kept' do
      beta = create(:company, :without_domain, account: account, name: 'Beta Seguros')
      contact = account.contacts.create!(name: 'Ana', phone_number: "+55#{phone(1)}", company: beta)
      campaign_import = contact_import(["Ana,#{phone(1)},,Alfa Corretora,,"])

      expect(campaign_import.validation_summary['companies']).to include('contacts_kept' => 1)

      import_contacts!(campaign_import)

      expect(contact.reload.company).to eq(beta)
      expect(account.companies.pluck(:name)).to eq(['Beta Seguros'])
      expect(campaign_import.companies_kept_count).to eq(1)
    end

    # C5
    it 'creates and links nothing with "Criar e ligar" off' do
      campaign_import = contact_import(["Ana,#{phone(1)},ana@deltaconstrutora.com.br,Delta Construtora,,"], create_companies: false)

      import_contacts!(campaign_import)

      expect(Company.count).to eq(0)
      expect(account.contacts.sole.company_id).to be_nil
    end

    # C6
    it 'creates nothing when the account has no companies feature' do
      account.disable_features!('companies')
      campaign_import = contact_import(["Ana,#{phone(1)},,Alfa Corretora,,"])

      expect(campaign_import.validation_summary['companies']).to eq('available' => false)

      import_contacts!(campaign_import)

      expect(Company.count).to eq(0)
    end
  end
end
