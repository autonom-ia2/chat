require 'rails_helper'

# Empresa do Chatwoot a partir do lead da prospecção (#680, frente A): reaproveita por CNPJ e, sem ele, pelo domínio do
# site; empresa existente só ganha o que está vazio.
RSpec.describe Autonomia::Prospecting::CompanyUpserter do
  let(:account) { create(:account) }
  let(:cnpj) { '11222333000181' }
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(
      cnpj: cnpj, legal_name: 'ALPHA RESTAURANTE LTDA', trade_name: 'Alpha Restaurante', registration_status: 'ATIVA',
      registration_state: 'SP', legal_nature_text: 'Sociedade Empresária Limitada', verified_at: Time.zone.parse('2026-09-20 10:00')
    )
  end
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/alpha', name: 'Alpha Restaurante e Bar',
      phone: '+55 11 3333-4444', website: 'https://www.alpha.com.br/contato?x=1', address: 'Rua das Flores, 123',
      enriched_instagram: 'https://instagram.com/alpharest', enriched_linkedin: 'https://www.linkedin.com/company/alpha',
      enriched_facebook: 'https://facebook.com/alpharest'
    )
  end

  def research!(target = lead, status: 'confirmed')
    target.update!(company_profile: profile, company_research_status: status)
  end

  def upsert_company(target = lead)
    described_class.new(lead: target).perform
  end

  it 'cria a empresa com o cadastro da pesquisa, o domínio do site sem www e sem caminho, e a origem' do
    research!

    result = upsert_company

    expect(result.created).to be(true)
    expect(result.company).to have_attributes(account_id: account.id, name: 'Alpha Restaurante', domain: 'alpha.com.br')
    expect(result.company.additional_attributes).to include(
      'cnpj' => cnpj, 'legal_name' => 'ALPHA RESTAURANTE LTDA', 'trade_name' => 'Alpha Restaurante', 'registration_status' => 'ATIVA',
      'registration_state' => 'SP', 'address' => 'Rua das Flores, 123', 'phone' => '+551133334444',
      'instagram' => 'https://instagram.com/alpharest', 'linkedin' => 'https://www.linkedin.com/company/alpha',
      'facebook' => 'https://facebook.com/alpharest', 'source' => 'autonomia_prospecting'
    )
  end

  it 'reaproveita a empresa da conta com o mesmo CNPJ, mesmo com outro site' do
    existing = Company.create!(account: account, name: 'Alpha (cadastro manual)', domain: 'outro.com.br',
                               additional_attributes: { 'cnpj' => cnpj })
    research!

    result = nil
    expect { result = upsert_company }.not_to change(Company, :count)

    expect(result.created).to be(false)
    expect(result.company).to eq(existing)
  end

  it 'sem CNPJ, reaproveita a empresa da conta pelo domínio do site' do
    existing = Company.create!(account: account, name: 'Alpha', domain: 'alpha.com.br')

    result = nil
    expect { result = upsert_company }.not_to change(Company, :count)

    expect(result.created).to be(false)
    expect(result.company).to eq(existing)
  end

  it 'sem pesquisa, usa o CNPJ que o site mostrou, só se o dígito verificador fecha' do
    lead.update!(enriched_cnpj: '11.222.333/0001-81', website: nil)
    expect(upsert_company.company.additional_attributes['cnpj']).to eq(cnpj)

    other = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/beta',
                                                 name: 'Beta', enriched_cnpj: '11.222.333/0001-99')
    expect(upsert_company(other).company.additional_attributes).not_to have_key('cnpj')
  end

  it 'na empresa existente só preenche o que está vazio: nunca sobrescreve o que o usuário escreveu, nem a origem' do
    existing = Company.create!(
      account: account, name: 'Nome que o usuário deu',
      additional_attributes: { 'cnpj' => cnpj, 'legal_name' => 'RAZAO QUE O USUARIO CORRIGIU', 'phone' => '+5511900000000',
                               'address' => '' }
    )
    research!

    company = upsert_company.company.reload

    expect(company).to eq(existing)
    expect(company.name).to eq('Nome que o usuário deu')
    expect(company.domain).to eq('alpha.com.br')
    expect(company.additional_attributes).to include(
      'legal_name' => 'RAZAO QUE O USUARIO CORRIGIU', 'phone' => '+5511900000000', 'address' => 'Rua das Flores, 123',
      'trade_name' => 'Alpha Restaurante', 'registration_status' => 'ATIVA'
    )
    expect(company.additional_attributes).not_to have_key('source')
  end

  it 'empresa de outra conta com o mesmo CNPJ não é reaproveitada' do
    other_company = Company.create!(account: create(:account), name: 'Alpha', additional_attributes: { 'cnpj' => cnpj })
    research!

    result = upsert_company

    expect(result.created).to be(true)
    expect(result.company).not_to eq(other_company)
    expect(result.company.account_id).to eq(account.id)
  end

  it 'mesmo domínio com outro CNPJ (filial, franquia) é outra empresa, sem domínio' do
    Company.create!(account: account, name: 'Alpha Matriz', domain: 'alpha.com.br', additional_attributes: { 'cnpj' => '11444777000161' })
    research!

    result = upsert_company

    expect(result.created).to be(true)
    expect(result.company.domain).to be_nil
    expect(result.company.additional_attributes['cnpj']).to eq(cnpj)
  end

  it 'mesmo domínio de empresa sem CNPJ: reaproveita e grava o CNPJ nela' do
    existing = Company.create!(account: account, name: 'Alpha', domain: 'alpha.com.br')
    research!

    result = upsert_company

    expect(result.company).to eq(existing)
    expect(existing.reload.additional_attributes['cnpj']).to eq(cnpj)
  end

  it 'site em rede social ou encurtador não vira domínio: dois negócios no Instagram são duas empresas' do
    lead.update!(website: 'https://www.instagram.com/alpharest')
    other = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/beta',
                                                 name: 'Beta', website: 'https://instagram.com/betarest')

    first = upsert_company.company
    second = upsert_company(other).company

    expect(first.domain).to be_nil
    expect(second).not_to eq(first)
  end

  it 'sem pesquisa e sem nome fantasia, o nome é o do lead; com só a razão social, é ela' do
    expect(upsert_company.company.name).to eq('Alpha Restaurante e Bar')

    profile.update!(trade_name: nil, cnpj: '11444777000161')
    other = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/beta', name: 'Beta')
    research!(other)

    expect(upsert_company(other).company.name).to eq('ALPHA RESTAURANTE LTDA')
  end

  it 'pesquisa sem empresa achada (no_result) não usa o cadastro de outra pesquisa' do
    lead.update!(company_profile: profile, company_research_status: 'no_result', website: nil)

    expect(upsert_company.company.additional_attributes).not_to have_key('cnpj')
  end

  it 'chamado duas vezes para o mesmo lead devolve a mesma empresa' do
    research!

    first = upsert_company.company
    second = upsert_company

    expect(second.created).to be(false)
    expect(second.company).to eq(first)
  end

  it 'sem CNPJ e sem domínio, reaproveita a empresa já ligada ao contato do lead: reenvio não cria outra' do
    lead.update!(website: nil)
    first = upsert_company.company
    lead.update!(contact: account.contacts.create!(name: lead.name, company: first))

    second = upsert_company

    expect(second.created).to be(false)
    expect(second.company).to eq(first)
    expect(account.companies.count).to eq(1)
  end
end
