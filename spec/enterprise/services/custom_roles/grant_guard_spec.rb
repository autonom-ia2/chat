require 'rails_helper'

# #2124: a trava de quem dá função confere as chaves como a função vai gravá-las. Uma chave de editar o CRM traz
# `crm_view`, então quem não tem `crm_view` não o entrega por tabela.
RSpec.describe CustomRoles::GrantGuard do
  let(:account) { create(:account) }
  let(:giver) { create(:user, account: account, role: :agent) }
  let(:membership) { giver.account_users.find_by!(account: account) }

  def give_giver(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    membership.update!(custom_role: role)
    role
  end

  it 'deixa quem edita cards dar uma função que edita cards' do
    give_giver(%w[crm_manage_cards custom_role_manage])

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_cards])).to be(true)
  end

  it 'não deixa quem não tem crm_view dar uma chave que o traz' do
    role = give_giver(%w[crm_view_reports custom_role_manage])
    # Função antiga, gravada antes do #2124: o callback não roda aqui de propósito.
    role.update_column(:permissions, %w[crm_manage_cards custom_role_manage]) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_cards])).to be(false)
  end

  it 'continua negando chave que quem dá não tem' do
    give_giver(%w[crm_view custom_role_manage])

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_pipelines])).to be(false)
  end

  # #2308, rodada 5: o motivo da recusa só sai da lista CODES. A tela tem uma frase para cada código
  # (FRASE_DO_401 em salvarFuncao.js; codigosDo401.spec.js lê esta lista), então um código fora dela não sai.
  describe 'refusal codes' do
    it 'keeps every code in one frozen list' do
      expect(described_class::CODES).to eq(%w[out_of_reach own_role])
      expect(described_class::CODES).to be_frozen
    end

    it 'refuses only with a listed code' do
      described_class::CODES.each { |code| expect(described_class::Denied.new(code).code).to eq(code) }
      expect { described_class::Denied.new('made_up') }.to raise_error(ArgumentError, /made_up/)
    end

    it 'says own_role and out_of_reach' do
      role = give_giver(%w[contact_view custom_role_manage])
      guard = described_class.new(actor: membership.reload)

      expect { guard.write!(role, %w[contact_view]) }
        .to raise_error(described_class::Denied) { |error| expect(error.code).to eq(described_class::OWN_ROLE) }
      expect { guard.write!(nil, %w[financial_view]) }
        .to raise_error(described_class::Denied) { |error| expect(error.code).to eq(described_class::OUT_OF_REACH) }
    end
  end
end
