require 'rails_helper'

# Quem vê os valores de venda em R$ do CRM (#2075, lote 13 das funções personalizadas).
RSpec.describe Crm::ValorDeVenda do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }

  def membro(user) = AccountUser.find_by(account: account, user: user)

  def com_funcao(permissions)
    user = create(:user, account: account, role: :agent)
    membro(user).tap { |account_user| account_user.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) }
  end

  def card_de(dono)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: dono, title: 'Card', value_cents: 100_000)
  end

  describe '.ve?' do
    it 'administrador, agente sem função e a chave veem; crm_admin e função sem a chave, não (chave protegida)' do
      agente = membro(create(:user, account: account, role: :agent))

      expect(described_class.ve?(membro(admin))).to be(true)
      expect(described_class.ve?(agente)).to be(true)
      expect(described_class.ve?(com_funcao(%w[crm_view sales_value_view]))).to be(true)
      expect(described_class.ve?(com_funcao(%w[crm_admin]))).to be(false)
      expect(described_class.ve?(com_funcao(%w[crm_view crm_view_reports crm_metas_manage]))).to be(false)
      expect(described_class.ve?(nil)).to be(false)
    end
  end

  describe '.ve_o_card?' do
    it 'sem a chave, só o card de que a pessoa é dona' do
      sem_chave = com_funcao(%w[crm_view])

      expect(described_class.ve_o_card?(sem_chave, card_de(sem_chave.user))).to be(true)
      expect(described_class.ve_o_card?(sem_chave, card_de(admin))).to be(false)
      expect(described_class.ve_o_card?(sem_chave, card_de(nil))).to be(false)
    end
  end

  it '.oculta_card! tira o valor e marca que foi por permissão' do
    expect(described_class.oculta_card!({ value_cents: 100, currency: 'BRL' }))
      .to eq(value_cents: nil, currency: 'BRL', value_hidden: true)
  end
end
