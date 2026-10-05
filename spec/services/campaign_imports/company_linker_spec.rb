require 'rails_helper'

RSpec.describe CampaignImports::CompanyLinker do
  let(:account) { create(:account) }
  let(:linker) { described_class.new(account) }

  before { account.enable_features!('companies') }

  def new_contact(**attrs)
    create(:contact, account: account, email: nil, **attrs)
  end

  describe '.normalize_name' do
    it 'collapses spaces and ignores case and accents' do
      expect(described_class.normalize_name("  Corretora  São\tPaulo ")).to eq('corretora sao paulo')
      expect(described_class.normalize_name('CORRETORA SAO PAULO')).to eq('corretora sao paulo')
    end

    it 'keeps punctuation, so the comparison stays exact' do
      expect(described_class.normalize_name('Alfa & Cia.')).not_to eq(described_class.normalize_name('Alfa Cia'))
    end
  end

  describe '#link' do
    # C1
    it 'creates one company for the same name across many rows and links every contact' do
      contacts = Array.new(10) { new_contact }

      results = contacts.map { |contact| linker.link(contact, company_name: 'Alfa Corretora') }

      expect(account.companies.where(name: 'Alfa Corretora').count).to eq(1)
      company = account.companies.find_by!(name: 'Alfa Corretora')
      expect(contacts.map { |contact| contact.reload.company_id }.uniq).to eq([company.id])
      expect(results.map(&:status)).to eq([:created] + ([:reused] * 9))
      expect(results).to all(be_linked)
      expect(company.reload.contacts_count).to eq(10)
      expect(linker.summary).to eq(companies_created: 1, companies_reused: 0, contacts_linked: 10, contacts_kept: 0)
    end

    # C2
    it 'reuses an existing company whose name differs only by case, spaces and accents' do
      existing = create(:company, :without_domain, account: account, name: 'Corretora São Paulo')
      contact = new_contact

      result = nil
      expect { result = linker.link(contact, company_name: ' corretora  sao   PAULO ') }.not_to change(Company, :count)

      expect(result.status).to eq(:reused)
      expect(result.company).to eq(existing)
      expect(contact.reload.company).to eq(existing)
      expect(existing.reload.contacts_count).to eq(1)
      expect(linker.summary).to include(companies_created: 0, companies_reused: 1, contacts_linked: 1)
    end

    it 'reuses "Alfa Corretora" for "ALFA corretora" written with a double space' do
      existing = create(:company, :without_domain, account: account, name: 'Alfa Corretora')

      result = linker.link(new_contact, company_name: 'ALFA  corretora')

      expect(result.status).to eq(:reused)
      expect(result.company).to eq(existing)
    end

    # C3
    it 'prefers the company with the business e-mail domain over the spreadsheet name' do
      by_domain = create(:company, account: account, name: 'Alfa', domain: 'alfacorretora.com.br')
      create(:company, :without_domain, account: account, name: 'Outro Nome')
      contact = new_contact

      result = linker.link(contact, company_name: 'Outro Nome', email: 'Ana@AlfaCorretora.com.br')

      expect(result.status).to eq(:reused)
      expect(result.company).to eq(by_domain)
      expect(contact.reload.company).to eq(by_domain)
    end

    it 'falls back to the name when the e-mail is from a free provider, even if a company has that domain' do
      create(:company, account: account, name: 'Gmail Inc', domain: 'gmail.com')
      by_name = create(:company, :without_domain, account: account, name: 'Beta Seguros')

      result = linker.link(new_contact, company_name: 'Beta Seguros', email: 'ana@gmail.com')

      expect(result.company).to eq(by_name)
    end

    it 'falls back to the name when no company has the e-mail domain' do
      by_name = create(:company, :without_domain, account: account, name: 'Beta Seguros')

      result = linker.link(new_contact, company_name: 'Beta Seguros', email: 'ana@betaseguros.com.br')

      expect(result.company).to eq(by_name)
    end

    it 'creates the company with the name as written, trimmed, and no domain' do
      result = linker.link(new_contact, company_name: '  Gama  Clínica ', email: 'ana@gamaclinica.com.br')

      expect(result.status).to eq(:created)
      expect(result.company.name).to eq('Gama  Clínica')
      expect(result.company.domain).to be_nil
    end

    # C4
    it 'keeps the company a contact already has and counts the row as kept' do
      beta = create(:company, :without_domain, account: account, name: 'Beta Seguros')
      alfa = create(:company, :without_domain, account: account, name: 'Alfa Corretora')
      contact = new_contact
      contact.update!(company: beta)

      result = linker.link(contact, company_name: 'Alfa Corretora')

      expect(result.status).to eq(:kept_other)
      expect(result.company).to eq(alfa)
      expect(result).not_to be_linked
      expect(contact.reload.company).to eq(beta)
      expect(beta.reload.contacts_count).to eq(1)
      expect(alfa.reload.contacts_count).to eq(0)
      expect(linker.summary).to include(contacts_kept: 1, contacts_linked: 0, companies_reused: 0)
    end

    it 'does not create the spreadsheet company for a contact that keeps another one' do
      beta = create(:company, :without_domain, account: account, name: 'Beta Seguros')
      contact = new_contact
      contact.update!(company: beta)

      result = nil
      expect { result = linker.link(contact, company_name: 'Empresa Nova') }.not_to change(Company, :count)

      expect(result.status).to eq(:kept_other)
      expect(result.company).to be_nil
    end

    it 'does nothing when the contact already has the same company' do
      alfa = create(:company, :without_domain, account: account, name: 'Alfa Corretora')
      contact = new_contact
      contact.update!(company: alfa)

      result = linker.link(contact, company_name: 'alfa corretora')

      expect(result.status).to eq(:reused)
      expect(result).not_to be_linked
      expect(alfa.reload.contacts_count).to eq(1)
      expect(linker.summary).to include(contacts_linked: 0, companies_reused: 1)
    end

    it 'returns none for a blank company value and links nothing' do
      contact = new_contact

      results = [nil, '', '   '].map { |name| linker.link(contact, company_name: name, email: 'ana@alfa.com.br') }

      expect(results.map(&:status)).to all(eq(:none))
      expect(contact.reload.company_id).to be_nil
      expect(Company.count).to eq(0)
    end

    it 'counts each pre-existing company once in companies_reused' do
      alfa = create(:company, :without_domain, account: account, name: 'Alfa')
      beta = create(:company, :without_domain, account: account, name: 'Beta')

      [alfa.name, alfa.name, beta.name].each { |name| linker.link(new_contact, company_name: name) }

      expect(linker.summary).to eq(companies_created: 0, companies_reused: 2, contacts_linked: 3, contacts_kept: 0)
    end

    it 'does not let the e-mail auto association create a second company' do
      contact = nil
      expect do
        ActiveRecord::Base.transaction do
          contact = account.contacts.create!(name: 'Ana', email: 'ana@deltaconstrutora.com.br')
          linker.link(contact, company_name: 'Delta Construtora', email: contact.email)
        end
      end.to change(Company, :count).by(1)

      expect(contact.reload.company.name).to eq('Delta Construtora')
      expect(contact.additional_attributes['company_name']).to eq('Delta Construtora')
    end

    it 'forgets a company whose row savepoint rolled back' do
      ActiveRecord::Base.transaction(requires_new: true) do
        linker.link(new_contact, company_name: 'Épsilon')
        raise ActiveRecord::Rollback
      end

      expect(Company.count).to eq(0)
      expect(linker.summary).to eq(companies_created: 0, companies_reused: 0, contacts_linked: 0, contacts_kept: 0)

      contact = new_contact
      result = linker.link(contact, company_name: 'epsilon')

      expect(result.status).to eq(:created)
      expect(contact.reload.company).to eq(result.company)
      expect(Company.count).to eq(1)
    end

    it 'truncates names longer than the company name limit' do
      long_name = 'A' * (Limits::COMPANY_NAME_LENGTH_LIMIT + 10)

      first = linker.link(new_contact, company_name: long_name)
      second = linker.link(new_contact, company_name: long_name)

      expect(first.company.name.length).to eq(Limits::COMPANY_NAME_LENGTH_LIMIT)
      expect(second.company).to eq(first.company)
    end

    it 'never touches companies of another account' do
      create(:company, :without_domain, name: 'Alfa Corretora')
      create(:company, name: 'Alfa', domain: 'alfacorretora.com.br')

      result = linker.link(new_contact, company_name: 'Alfa Corretora', email: 'ana@alfacorretora.com.br')

      expect(result.status).to eq(:created)
      expect(result.company.account).to eq(account)
    end
  end

  describe '#prepare' do
    it 'loads the companies of a block in one query so linking does not query per row' do
      companies = Array.new(3) { |index| create(:company, :without_domain, account: account, name: "Empresa #{index}") }
      rows = companies.flat_map { |company| Array.new(2) { { company_name: company.name.upcase, email: nil } } }
      linker.prepare(rows)

      company_queries = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        company_queries += 1 if payload[:sql].include?('FROM "companies"')
      end
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        rows.each { |row| linker.link(new_contact, **row) }
      end

      expect(company_queries).to eq(0)
      expect(companies.map { |company| company.reload.contacts_count }).to eq([2, 2, 2])
    end
  end

  describe 'guards' do
    # C5
    it 'does nothing when the import switch is off' do
      off = described_class.new(account, enabled: false)
      contact = new_contact

      result = off.link(contact, company_name: 'Alfa Corretora')

      expect(result.status).to eq(:none)
      expect(off).not_to be_active
      expect(Company.count).to eq(0)
      expect(contact.reload.company_id).to be_nil
    end

    # C6
    it 'does nothing when the companies feature is off for the account' do
      account.disable_features!('companies')
      off = described_class.new(account.reload)
      contact = new_contact

      off.prepare([{ company_name: 'Alfa Corretora', email: nil }])
      result = off.link(contact, company_name: 'Alfa Corretora')

      expect(result.status).to eq(:none)
      expect(Company.count).to eq(0)
      expect(contact.reload.company_id).to be_nil
    end
  end
end
