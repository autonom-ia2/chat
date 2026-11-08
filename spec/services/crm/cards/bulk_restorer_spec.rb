require 'rails_helper'

RSpec.describe Crm::Cards::BulkRestorer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:stage) { create_crm_pipeline(account: account, user: admin).last }
  let(:account_user) { admin.account_users.find_by!(account: account) }

  def archived_card(title)
    account.crm_cards.create!(pipeline: stage.pipeline, stage: stage, title: title, status: :archived)
  end

  def restore(ids)
    described_class.new(account: account, user: admin, account_user: account_user, ids: ids).perform
  end

  it 'é tudo ou nada: um erro no meio desfaz os já restaurados' do
    first = archived_card('Primeiro')
    second = archived_card('Segundo')
    calls = 0
    allow(Crm::Cards::Closer).to receive(:new).and_wrap_original do |original, **kwargs|
      calls += 1
      raise ActiveRecord::StatementInvalid, 'falha no meio' if calls == 2

      original.call(**kwargs)
    end

    expect { restore([first.id, second.id]) }.to raise_error(ActiveRecord::StatementInvalid)
    expect([first.reload.status, second.reload.status]).to eq(%w[archived archived])
  end

  it 'avisa o quadro só dos restaurados, depois de gravar' do
    first = archived_card('Primeiro')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)

    expect(restore([first.id, 'abc'])).to eq(restored: [first.id], skipped: [])
    expect(Crm::Cards::Broadcaster).to have_received(:broadcast).once.with(first, Events::Types::CRM_CARD_UPDATED)
  end

  it 'no conflito, o card aberto só vai se a pessoa o enxerga' do
    contact = create(:contact, account: account)
    archived = account.crm_cards.create!(pipeline: stage.pipeline, stage: stage, contact: contact, title: 'Arquivado', status: :archived)
    open = account.crm_cards.create!(pipeline: stage.pipeline, stage: stage, contact: contact, title: 'Aberto')
    allow(Pundit).to receive(:policy!).and_wrap_original do |original, context, record|
      original.call(context, record).tap { |policy| allow(policy).to receive(:show?).and_return(false) if record == open }
    end

    expect(restore([archived.id])).to eq(restored: [], skipped: [{ id: archived.id, error: Crm::Cards::Restorer::CONFLICT }])
  end

  it 'aceita no máximo o mesmo lote da ação em massa' do
    ids = (1..(Crm::Cards::BulkAction::MAX_IDS + 5)).to_a

    expect(restore(ids)[:skipped].size).to eq(Crm::Cards::BulkAction::MAX_IDS)
  end
end
