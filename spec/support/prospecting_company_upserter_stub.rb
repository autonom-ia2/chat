# A empresa do lead é da frente A do #680 (Autonomia::Prospecting::CompanyUpserter). Enquanto as frentes não se
# juntam, os specs da frente B trocam a classe por esta, que cumpre o mesmo contrato: uma empresa por CNPJ na conta.
module ProspectingCompanyUpserterStub
  class FakeUpserter
    Result = Struct.new(:company, :created, keyword_init: true)

    def initialize(lead:)
      @lead = lead
    end

    def perform
      cnpj = @lead.enriched_cnpj.presence || "cnpj-#{@lead.id}"
      existing = @lead.account.companies.find_by("additional_attributes->>'cnpj' = ?", cnpj)
      return Result.new(company: existing, created: false) if existing

      company = @lead.account.companies.create!(
        name: @lead.name,
        additional_attributes: { 'cnpj' => cnpj, 'legal_name' => "#{@lead.name} LTDA", 'source' => 'autonomia_prospecting' }
      )
      Result.new(company: company, created: true)
    end
  end

  def stub_prospecting_company_upserter
    stub_const('Autonomia::Prospecting::CompanyUpserter', FakeUpserter)
  end
end

RSpec.configure do |config|
  config.include ProspectingCompanyUpserterStub
end
