# Tabela única de casos de telefone da prospecção (#677). O mesmo JSON roda no
# vitest (specs/utils/phoneContract.spec.js), para o backend e o front darem o mesmo resultado.
module ProspectingPhoneContractCases
  def self.all
    @all ||= JSON.parse(Rails.root.join('spec/fixtures/prospecting_phone_contract_cases.json').read).freeze
  end

  # Grava o país da busca da conta (settings.metadata['search_country']). País fora da lista a tela já não aceita;
  # ele só existe como dado antigo no banco, então entra sem passar pela validação.
  def self.apply_region!(account, region)
    return if region.nil?

    setting = Autonomia::Prospecting::Setting.for_account(account)
    metadata = setting.metadata.to_h.merge('search_country' => region)
    return setting.update!(metadata: metadata) if Autonomia::Prospecting::SearchCountry.normalize(region)

    setting.update_columns(metadata: metadata) # rubocop:disable Rails/SkipsModelValidations
  end
end
