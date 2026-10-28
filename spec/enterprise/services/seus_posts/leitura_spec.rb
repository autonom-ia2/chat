require 'rails_helper'

# Seus posts (#2302, F1 #2304) com função personalizada (parecer de desenho da sessão Funções, 27/10). posts_view abre a
# página e os números; a contagem de conversas e o id da caixa só vão para quem vê a caixa (ou pode reautorizá-la,
# integration_manage). Fica em spec/enterprise: a metade de função personalizada do permission_granted? e do filtro de
# conversas é EE. A leitura da Meta é substituída.
RSpec.describe SeusPosts::Leitura do
  let(:account) { create(:account) }
  # A factory do Instagram já cria a caixa nesta conta.
  let!(:canal) { create(:channel_instagram, account: account) }
  let(:inbox) { canal.inbox }

  before do
    Rails.cache.clear
    Current.account = account
    allow(SeusPosts::NumerosInstagram).to receive(:new)
      .and_return(instance_double(SeusPosts::NumerosInstagram, perform: { status: 'ok', username: 'studioacme' }))
    allow(SeusPosts::Posts).to receive(:para)
      .and_return(instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [], normal: {} }))
  end

  after { Current.reset }

  def member_with(permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def viewer(user)
    Current.user = user
    { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
  end

  def perfil_para(user)
    described_class.new(account: account, perfil: nil, days: 30, viewer: viewer(user)).perform[:perfil]
  end

  it 'posts_view sem ver a caixa: vê os números, sem a contagem nem o id da caixa' do
    perfil = perfil_para(member_with(%w[posts_view]))

    expect(perfil).to include(status: 'ok', username: 'studioacme')
    expect(perfil[:messages]).to eq(count: nil, inbox_id: nil)
  end

  it 'posts_view com a caixa: conta só as conversas que a função alcança' do
    agente = member_with(%w[posts_view conversation_participating_manage])
    create(:inbox_member, user: agente, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: agente)
    create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent))

    expect(perfil_para(agente)[:messages]).to eq(count: 1, inbox_id: inbox.id)
  end

  describe SeusPostsPolicy do
    def policy_for(permissions)
      described_class.new(viewer(member_with(permissions)), :seus_posts)
    end

    it 'posts_manage também vê' do
      expect(policy_for(%w[posts_manage])).to have_attributes(index?: true, manage?: true)
    end

    it 'posts_view não age sobre os posts' do
      expect(policy_for(%w[posts_view])).to have_attributes(index?: true, manage?: false)
    end

    it 'função sem as chaves de posts não entra' do
      expect(policy_for(%w[conversation_manage])).to have_attributes(index?: false, manage?: false)
    end
  end
end
