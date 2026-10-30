require 'rails_helper'

# O funil padrão da caixa só vale ativo: arquivado, o card nasce no próximo funil ativo, ou em nenhum.
RSpec.describe Crm::Cards::ConversationDefaultsResolver do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:padrao) { create_crm_pipeline(account: account, user: admin, name: 'Padrão da caixa') }

  before { account.crm_inbox_settings.create!(inbox: inbox, default_pipeline: padrao.first) }

  def resolver = described_class.new(account: account, requested: {}, conversation: conversation)

  it 'usa o funil padrão da caixa quando ele está ativo' do
    expect(resolver.perform).to eq(pipeline_id: padrao.first.id, stage_id: padrao.last.id)
  end

  it 'pula o funil padrão arquivado e usa o próximo ativo' do
    proximo = create_crm_pipeline(account: account, user: admin, name: 'Próximo')
    padrao.first.archived!

    expect(resolver.perform).to eq(pipeline_id: proximo.first.id, stage_id: proximo.last.id)
  end

  it 'sem funil ativo, não cria card em funil arquivado' do
    padrao.first.archived!

    expect { resolver.perform }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
