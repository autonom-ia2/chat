require 'rails_helper'

# #2519: o número "esperando você" por anúncio, o contrato com o painel de Anúncios (#2521). Lido do banco, das ações do
# #2196 (Crm::MetaAdsCommentAction), nunca da Meta.
RSpec.describe Crm::MetaAds::ComentariosIa::Esperando do
  let(:account) { create(:account) }

  def acao(comment_id, action, ad_id: '120', actor: 'ai', at: 1.hour.ago)
    Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: comment_id, action: action, actor: actor,
                                      ad_id: ad_id, at: at, user: (create(:user, account: account) if actor == 'user'))
  end

  def contar(ad_ids = %w[120 121])
    described_class.por_anuncio(account.id, ad_ids)
  end

  it 'conta o que a IA deixou com o dono e o que chegou sem cuidado, por anúncio, com zero para quem não tem nada' do
    acao('c-1', 'no_care')
    acao('c-2', 'to_you')
    acao('c-3', 'kept_for_owner')
    acao('c-4', 'ai_unread', ad_id: '121')
    acao('c-5', 'reply')

    expect(contar(%w[120 121 122])).to eq('120' => 3, '121' => 1, '122' => 0)
  end

  # A linha da pessoa é a que InstagramComments e SeusPosts::ComentariosInstagram gravam (spec deles): reply, hide,
  # show, delete ou private_reply, com actor user, no comentário original. Só a da mesma rede conta.
  it 'sai da conta quando a pessoa age no comentário, na mesma rede' do
    acao('c-1', 'no_care')
    acao('c-2', 'to_you')
    acao('c-2', 'reply', actor: 'user', ad_id: nil)
    acao('c-3', 'kept_for_owner')
    Crm::MetaAdsCommentAction.create!(account: account, network: 'facebook', comment_id: 'c-3', action: 'reply', actor: 'user',
                                      user: create(:user, account: account), at: 1.hour.ago)

    expect(contar).to eq('120' => 2, '121' => 0)
  end

  it 'o que chegou sem cuidado e a IA pegou depois (Ler e mandar) só conta se ela o deixou com o dono' do
    acao('c-1', 'no_care')
    acao('c-1', 'ai_seen')
    acao('c-2', 'no_care')
    acao('c-2', 'ai_seen')
    acao('c-2', 'private_reply_failed')

    expect(contar).to eq('120' => 1, '121' => 0)
  end

  it 'o mesmo comentário conta uma vez; mais de 7 dias, outra conta e sem anúncio não contam' do
    acao('c-1', 'to_you')
    acao('c-1', 'private_reply_failed')
    acao('c-2', 'no_care', at: 8.days.ago)
    acao('c-3', 'no_care', ad_id: nil)
    Crm::MetaAdsCommentAction.create!(account: create(:account), network: 'instagram', comment_id: 'c-4', action: 'no_care',
                                      actor: 'ai', ad_id: '120', at: 1.hour.ago)

    expect(contar).to eq('120' => 1, '121' => 0)
  end

  it 'sem anúncio pedido, nada' do
    expect(contar([])).to eq({})
  end
end
