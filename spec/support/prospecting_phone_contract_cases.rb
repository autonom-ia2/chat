# Tabela única de casos de telefone da prospecção (#677). O mesmo JSON roda no
# vitest (specs/utils/phoneContract.spec.js), para o backend e o front darem o mesmo resultado.
module ProspectingPhoneContractCases
  def self.all
    @all ||= JSON.parse(Rails.root.join('spec/fixtures/prospecting_phone_contract_cases.json').read).freeze
  end

  # Grava o país da busca da conta como a frente de país faz (settings.metadata['search_country']).
  def self.apply_region!(account, region)
    return if region.nil?

    setting = Autonomia::Prospecting::Setting.for_account(account)
    setting.update!(metadata: setting.metadata.to_h.merge('search_country' => region))
  end
end
