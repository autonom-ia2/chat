require 'rails_helper'

# #998 (PRD #990 §8.2 "Empresa", C1–C7): companies from the spreadsheet's company column,
# end to end through AudienceValidator (preview before saving) and Importer.
RSpec.describe CampaignImports::Importer, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 } }
  let(:header) { "Segurado,Celular,Email,Corretora\n" }

  before { account.enable_features!('companies') }

  def validated(lines, create_companies: nil)
    campaign_import = create_audience_import(account: account, user: account_and_user.last, content: "#{header}#{lines.join("\n")}\n")
    options = campaign_import.options.merge(create_companies.nil? ? {} : { 'create_companies' => create_companies })
    campaign_import.update!(options: options, schema_resolution: { 'manual_mapping' => mapping, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform
    expect(campaign_import.reload).to be_ready_to_confirm
    campaign_import
  end

  def import!(campaign_import)
    campaign_import.update!(status: :queued)
    described_class.new(campaign_import).perform
    campaign_import.reload
  end

  def preview(campaign_import)
    campaign_import.validation_summary['companies']
  end

  def final_counts(campaign_import)
    {
      'companies_created' => campaign_import.companies_created_count, 'companies_reused' => campaign_import.companies_reused_count,
      'contacts_linked' => campaign_import.company_contacts_linked_count, 'contacts_kept' => campaign_import.companies_kept_count
    }
  end

  def row_results(campaign_import)
    campaign_import.campaign_import_rows.order(:row_number).pluck(:company_result)
  end

  def phone(index)
    "1198765#{format('%04d', index)}"
  end

  # C1
  it 'creates one company for ten rows with the same name and links the ten contacts' do
    campaign_import = validated(Array.new(10) { |i| "Pessoa #{i},#{phone(i)},,Alfa Corretora" })

    expect(preview(campaign_import)).to eq(
      'available' => true, 'rows_with_company' => 10, 'companies_created' => 1, 'companies_reused' => 0, 'contacts_linked' => 10, 'contacts_kept' => 0
    )
    expect(Company.count).to eq(0)

    import!(campaign_import)

    company = account.companies.sole
    expect(company.name).to eq('Alfa Corretora')
    expect(account.contacts.pluck(:company_id).uniq).to eq([company.id])
    expect(company.reload.contacts_count).to eq(10)
    expect(row_results(campaign_import)).to eq(['created'] + (['reused'] * 9))
    expect(campaign_import.campaign_import_rows.distinct.pluck(:company_id)).to eq([company.id])
    expect(final_counts(campaign_import)).to eq(preview(campaign_import).except('available', 'rows_with_company'))
  end

  # C2
  it 'reuses the existing company when the spreadsheet writes it with other case and spaces' do
    existing = create(:company, :without_domain, account: account, name: 'Alfa Corretora')
    campaign_import = validated(["Ana,#{phone(1)},,ALFA  corretora"])

    expect(preview(campaign_import)).to include('companies_created' => 0, 'companies_reused' => 1, 'contacts_linked' => 1)

    expect { import!(campaign_import) }.not_to change(Company, :count)

    expect(account.contacts.sole.company).to eq(existing)
    expect(row_results(campaign_import)).to eq(['reused'])
    expect(final_counts(campaign_import)).to eq(preview(campaign_import).except('available', 'rows_with_company'))
  end

  # C3
  it 'links by the business e-mail domain even when the spreadsheet name differs' do
    by_domain = create(:company, account: account, name: 'Alfa', domain: 'alfacorretora.com.br')
    campaign_import = validated(["Ana,#{phone(1)},ana@alfacorretora.com.br,Nome Diferente"])

    expect(preview(campaign_import)).to include('companies_created' => 0, 'companies_reused' => 1)

    expect { import!(campaign_import) }.not_to change(Company, :count)

    expect(account.contacts.sole.company).to eq(by_domain)
    expect(final_counts(campaign_import)).to eq(preview(campaign_import).except('available', 'rows_with_company'))
  end

  # C4
  it 'keeps the company a contact already has and counts the row as kept, before and after saving' do
    beta = create(:company, :without_domain, account: account, name: 'Beta Seguros')
    contact = account.contacts.create!(name: 'Ana', phone_number: "+55#{phone(1)}", company: beta)
    campaign_import = validated(["Ana,#{phone(1)},,Alfa Corretora"])

    expect(preview(campaign_import)).to include('companies_created' => 0, 'contacts_linked' => 0, 'contacts_kept' => 1)

    import!(campaign_import)

    expect(contact.reload.company).to eq(beta)
    expect(account.companies.pluck(:name)).to eq(['Beta Seguros'])
    expect(row_results(campaign_import)).to eq(['kept_other'])
    expect(campaign_import.companies_kept_count).to eq(1)
    expect(final_counts(campaign_import)).to eq(preview(campaign_import).except('available', 'rows_with_company'))
  end

  # C5
  it 'creates and links nothing when "Criar e ligar" is off, not even from a business e-mail' do
    campaign_import = validated(["Ana,#{phone(1)},ana@deltaconstrutora.com.br,Delta Construtora"], create_companies: false)

    import!(campaign_import)

    expect(Company.count).to eq(0)
    expect(account.contacts.sole.company_id).to be_nil
    expect(row_results(campaign_import)).to eq(['none'])
    expect(final_counts(campaign_import).values).to all(eq(0))
  end

  # C6
  it 'shows no company block and creates nothing when the companies feature is off' do
    account.disable_features!('companies')
    campaign_import = validated(["Ana,#{phone(1)},,Alfa Corretora"])

    expect(preview(campaign_import)).to eq('available' => false)

    import!(campaign_import)

    expect(Company.count).to eq(0)
    expect(account.contacts.sole.company_id).to be_nil
    expect(row_results(campaign_import)).to eq(['none'])
  end

  # C7
  it 'keeps companies and contact links when the audience labels are undone' do
    campaign_import = import!(validated(["Ana,#{phone(1)},,Alfa Corretora", "Bia,#{phone(2)},,Alfa Corretora"]))

    CampaignImports::UndoLabels.new(campaign_import).perform

    expect(campaign_import.reload).to be_labels_undone
    company = account.companies.sole
    expect(account.contacts.pluck(:company_id)).to eq([company.id, company.id])
    expect(company.reload.contacts_count).to eq(2)
  end

  it 'shows before saving the same numbers the import reports for a mixed spreadsheet' do
    alfa = create(:company, :without_domain, account: account, name: 'Alfa')
    beta = create(:company, :without_domain, account: account, name: 'Beta')
    account.contacts.create!(name: 'Com Beta', phone_number: "+55#{phone(3)}", company: beta)
    same = account.contacts.create!(name: 'Com Alfa', email: 'mesmo@alfa.com.br', company: alfa)
    legacy = account.contacts.create!(name: 'Sem nono', phone_number: '+554588887777')
    campaign_import = validated(
      [
        "Nova 1,#{phone(1)},,Gama Clínica", "Nova 2,#{phone(2)},,gama  clinica", "Com Beta,#{phone(3)},,Alfa",
        'Com Alfa,,mesmo@alfa.com.br,Alfa', 'Sem nono,45988887777,,Beta', "Sem empresa,#{phone(6)},,"
      ]
    )

    expect(preview(campaign_import)).to eq(
      'available' => true, 'rows_with_company' => 5, 'companies_created' => 1, 'companies_reused' => 2, 'contacts_linked' => 4, 'contacts_kept' => 1
    )

    import!(campaign_import)

    expect(row_results(campaign_import)).to eq(%w[created reused kept_other reused reused none])
    expect(same.reload.company).to eq(alfa)
    expect(legacy.reload.company).to eq(beta)
    expect(final_counts(campaign_import)).to eq(preview(campaign_import).except('available', 'rows_with_company'))
  end

  it 'keeps the final numbers of the whole import when a retried run skips rows already imported' do
    campaign_import = import!(validated(["Ana,#{phone(1)},,Alfa Corretora", "Bia,#{phone(2)},,Alfa Corretora"]))
    counts = final_counts(campaign_import)

    campaign_import.update!(status: :queued)
    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_completed
    expect(final_counts(campaign_import)).to eq(counts)
    expect(counts).to eq('companies_created' => 1, 'companies_reused' => 0, 'contacts_linked' => 2, 'contacts_kept' => 0)
  end

  it 'rolls the company back with a failed row and leaves no company on that row' do
    campaign_import = validated(["Ana,#{phone(1)},,Alfa Corretora", "Bia,#{phone(2)},,Delta Construtora"])
    campaign_import.update!(status: :queued)
    importer = described_class.new(campaign_import)
    allow(importer).to receive(:mark_row_imported!).and_wrap_original do |method, import_row, *args|
      raise ActiveRecord::RecordInvalid, Contact.new if import_row.row_number == 3

      method.call(import_row, *args)
    end

    importer.perform

    campaign_import.reload
    expect(campaign_import).to be_completed_with_failures
    expect(account.companies.pluck(:name)).to eq(['Alfa Corretora'])
    expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:status, :company_result, :company_id)).to eq(
      [['imported', 'created', account.companies.sole.id], ['import_failed', nil, nil]]
    )
    expect(final_counts(campaign_import)).to include('companies_created' => 1, 'contacts_linked' => 1)
  end

  it 'leaves the old campaign base flow without company results or counters' do
    content = "nome,telefone\nAna,#{phone(1)}\n"
    campaign_import = create_campaign_import(account: account, user: account_and_user.last, content: content, batch_count: 1)
    CampaignImports::Validator.new(campaign_import).perform
    expect(campaign_import.reload.validation_summary).not_to have_key('companies')

    import!(campaign_import)

    expect(campaign_import).to be_completed
    expect(row_results(campaign_import)).to eq([nil])
    expect(final_counts(campaign_import).values).to all(eq(0))
    expect(Company.count).to eq(0)
  end
end
