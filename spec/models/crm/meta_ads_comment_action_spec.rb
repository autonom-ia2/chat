require 'rails_helper'

# O que já foi feito num comentário de anúncio (#2196): só a resposta no privado e a leitura da IA acontecem uma vez
# por comentário (a linha é a reivindicação); ocultar e mostrar podem se repetir.
RSpec.describe Crm::MetaAdsCommentAction do
  let(:account) { create(:account) }

  def record(action, actor: 'user')
    described_class.record!(account: account, network: 'instagram', comment_id: '1801', action: action, actor: actor)
  end

  it 'barra a segunda resposta no privado e a segunda leitura da IA do mesmo comentário' do
    record('private_reply')
    record('ai_seen', actor: 'ai')

    expect { record('private_reply') }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { record('ai_seen', actor: 'ai') }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'deixa ocultar e mostrar de novo quantas vezes for preciso' do
    expect { 2.times { record('hide') && record('show') } }.to change(described_class, :count).by(4)
  end

  it 'recusa ação e autor desconhecidos' do
    expect { record('pin') }.to raise_error(ActiveRecord::RecordInvalid)
    expect { record('hide', actor: 'robo') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'reserva sem chamada vence em RESERVED_TTL; depois de attempt!, nunca' do
    action = described_class.record!(account: create(:account), network: 'instagram', comment_id: 'c2', action: 'private_reply',
                                     actor: 'ai')
    travel(described_class::RESERVED_TTL + 1.minute) { expect(action.abandoned?).to be(true) }

    action.attempt!
    travel(30.days) { expect(action.abandoned?).to be(false) }
  end

  it 'attempt! vale uma vez só e só numa linha que ainda existe' do
    action = described_class.record!(account: create(:account), network: 'instagram', comment_id: 'c3', action: 'private_reply',
                                     actor: 'ai')

    expect(action.attempt!).to be(true)
    expect(action.attempt!).to be(false)
    described_class.where(id: action.id).delete_all
    expect(action.attempt!).to be(false)
  end

  it 'confirm! marca quando a Meta aceitou o privado' do
    action = described_class.record!(account: create(:account), network: 'instagram', comment_id: 'c1', action: 'private_reply',
                                     actor: 'ai')

    expect { action.confirm! }.to change { action.reload.confirmed_at }.from(nil)
  end
end
