require 'rails_helper'

# #2037: the e-mail AI gets the line of business of the account from the server package; a general account gets the
# prompt it always got.
RSpec.describe EmailCampaigns::Ai::Generator, :aggregate_failures do
  let(:nicho) { Autonomia::Agents::Nicho }

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', AUTONOMIA_NICHO_PADRAO: nil) { example.run }
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO)
  end

  def account_of(perfil = nil)
    attributes = perfil ? { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil } : {}
    create(:account, internal_attributes: attributes)
  end

  def instructions_for(account, base_mjml: nil)
    described_class.new(account: account, brief: 'Lembrete de renovação', base_mjml: base_mjml).build.fetch(:instructions)
  end

  it 'tells the AI the vocabulary of a brokerage account, when generating and when adjusting' do
    account = account_of('corretora')
    adjust = '<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>'

    expect(instructions_for(account)).to include('Ramo da conta: corretora de seguros. Diga corretor e cotação')
    expect(instructions_for(account, base_mjml: adjust)).to include('Ramo da conta: corretora de seguros')
  end

  it 'uses the shared insurance line for an insurer and the health line for health plans' do
    expect(instructions_for(account_of('seguradora'))).to include('Ramo da conta: seguros. Fale de seguro, apólice')
    expect(instructions_for(account_of('saude_beneficios'))).to include('Ramo da conta: planos de saúde e benefícios')
  end

  it 'leaves a general account without any line of business' do
    account = account_of

    expect(instructions_for(account)).not_to include('Ramo da conta')
    expect(instructions_for(account)).to eq(EmailCampaigns::Ai::PromptBuilder.generate(brand: account.name))
  end
end
