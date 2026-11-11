require 'rails_helper'

# G52 (#2760): ver lista com campaign_view; criar, renomear e apagar com campaign_manage. No OSS as duas são do
# administrador.
RSpec.describe EmailListPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }
  let(:de_fora) { EmailList.criar(account: create(:account), name: 'Outra') }

  def contexto(usuario) = { user: usuario, account: account, account_user: AccountUser.find_by(account: account, user: usuario) }

  permissions :index?, :create? do
    it { expect(policy).to permit(contexto(admin), EmailList) }
    it { expect(policy).not_to permit(contexto(agente), EmailList) }
  end

  permissions :show?, :update?, :destroy? do
    it { expect(policy).to permit(contexto(admin), lista) }
    it { expect(policy).not_to permit(contexto(agente), lista) }
    it { expect(policy).not_to permit(contexto(admin), de_fora) }
  end
end
