require 'rails_helper'

# Seus posts (#2302, F1 #2304) com função personalizada (parecer de desenho da sessão Funções, 27/10, e revisão final do
# #2312). posts_view abre a página; perfil de caixa que a pessoa não vê nem aparece, e a contagem de conversas é só das
# que a função alcança. Fica em spec/enterprise: a metade de função personalizada do permission_granted? e do filtro de
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

  it 'posts_view sem ver a caixa: o perfil nem aparece' do
    resposta = described_class.new(account: account, perfil: nil, days: 30, viewer: viewer(member_with(%w[posts_view]))).perform

    expect(resposta).to include(perfil: nil, perfis: [])
    expect(SeusPosts::NumerosInstagram).not_to have_received(:new)
  end

  it 'com "esperando você" ligado (F2, #2305), quem não vê a caixa nunca recebe a contagem, nem 0' do
    account.enable_features!('seus_posts_comentarios')
    allow(SeusPosts::Esperando).to receive(:new)

    resposta = described_class.new(account: account, perfil: nil, days: 30, viewer: viewer(member_with(%w[posts_view]))).perform

    expect(resposta).to include(perfil: nil, perfis: [])
    expect(SeusPosts::Esperando).not_to have_received(:new)
  end

  it 'perfil de caixa que a pessoa não vê, pedido pelo id: 404, como o de outra conta' do
    leitura = described_class.new(account: account, perfil: "instagram-#{canal.id}", days: 30,
                                  viewer: viewer(member_with(%w[posts_view])))

    expect { leitura.perform }.to raise_error(SeusPosts::Leitura::PerfilDesconhecido)
  end

  it 'posts_view com a caixa: conta só as conversas que a função alcança' do
    agente = member_with(%w[posts_view conversation_participating_manage])
    create(:inbox_member, user: agente, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: agente)
    create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent))

    perfil = perfil_para(agente)
    expect(perfil).to include(status: 'ok', username: 'studioacme', inbox_id: inbox.id)
    expect(perfil[:messages]).to eq(count: 1, previous: nil)
  end

  it 'com o período anterior nos números, conta também as conversas dele' do
    allow(SeusPosts::NumerosInstagram).to receive(:new)
      .and_return(instance_double(SeusPosts::NumerosInstagram, perform: { status: 'ok', previous: { views: 10 } }))
    agente = member_with(%w[posts_view conversation_participating_manage])
    create(:inbox_member, user: agente, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: agente)
    create_list(:conversation, 2, account: account, inbox: inbox, assignee: agente, created_at: 35.days.ago)
    create(:conversation, account: account, inbox: inbox, assignee: agente, created_at: 70.days.ago)

    expect(perfil_para(agente)[:messages]).to eq(count: 1, previous: 2)
  end

  describe SeusPostsPolicy do
    def policy_for(permissions)
      described_class.new(viewer(member_with(permissions)), :seus_posts)
    end

    it 'posts_view e posts_manage veem' do
      expect(policy_for(%w[posts_view]).index?).to be(true)
      expect(policy_for(%w[posts_manage]).index?).to be(true)
    end

    it 'função sem as chaves de posts não entra' do
      expect(policy_for(%w[conversation_manage]).index?).to be(false)
    end
  end
end
