require 'rails_helper'

# #2124: a função gerenciada do token segue a mesma regra das pessoas. Escopo de editar traz `crm_view` (as políticas
# do card já pediam ver para editar) e nada mais.
RSpec.describe Crm::IntegrationToken do
  let(:account) { create(:account) }

  def token_with(scopes)
    described_class.create!(account: account, name: "Token #{SecureRandom.hex(3)}", scopes: scopes)
  end

  it 'grava crm_view junto de um escopo de editar' do
    expect(token_with(%w[crm_manage_cards]).granted_scopes).to contain_exactly('crm_manage_cards', 'crm_view')
  end

  it 'não acrescenta nada a quem só vê relatórios ou valores' do
    expect(token_with(%w[crm_view_reports]).granted_scopes).to eq(%w[crm_view_reports])
    expect(token_with(%w[sales_value_view]).granted_scopes).to eq(%w[sales_value_view])
  end
end
