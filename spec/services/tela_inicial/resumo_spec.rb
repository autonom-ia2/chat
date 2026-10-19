require 'rails_helper'

RSpec.describe TelaInicial::Resumo do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caixa) { create(:inbox, account: account) }

  def resumo_de(user)
    described_class.new(account: account, user: user, account_user: account.account_users.find_by(user: user)).perform
  end

  def conversa(dono: nil, inbox: caixa)
    create(:conversation, account: account, inbox: inbox, assignee: dono)
  end

  before { create(:inbox_member, user: agente, inbox: caixa) }

  describe 'fora do prazo' do
    it 'sem a feature de prazos, nil para a tela esconder' do
      create(:sla_policy, account: account)

      expect(resumo_de(admin)[:fora_do_prazo]).to be_nil
    end

    it 'com a feature e sem política, nil' do
      account.enable_features!('sla')

      expect(resumo_de(admin)[:fora_do_prazo]).to be_nil
    end

    it 'conta os prazos perdidos, dele e da equipe' do
      account.enable_features!('sla')
      politica = create(:sla_policy, account: account)
      create(:applied_sla, sla_policy: politica, conversation: conversa(dono: agente), sla_status: 'missed')
      create(:applied_sla, sla_policy: politica, conversation: conversa(dono: agente), sla_status: 'active_with_misses')
      create(:applied_sla, sla_policy: politica, conversation: conversa(dono: agente), sla_status: 'active')
      create(:applied_sla, sla_policy: politica, conversation: conversa, sla_status: 'missed')

      expect(resumo_de(agente)[:fora_do_prazo]).to eq(2)
      expect(resumo_de(admin)[:fora_do_prazo]).to eq(0)
      expect(resumo_de(admin)[:equipe][:fora_do_prazo]).to eq(3)
    end
  end

  describe 'funções personalizadas' do
    def com_papel(permissoes)
      papel = create(:custom_role, account: account, permissions: permissoes)
      account.account_users.find_by(user: agente).update!(custom_role: papel)
    end

    it 'com report_manage vê a equipe da conta inteira' do
      com_papel(%w[conversation_manage report_manage])
      conversa(dono: agente)
      conversa
      conversa(inbox: create(:inbox, account: account))

      expect(resumo_de(agente)[:equipe]).to eq(esperam: 3, fora_do_prazo: nil)
      expect(resumo_de(agente)[:sem_responsavel]).to eq(1)
    end

    it 'sem nenhuma permissão de conversa: zero, nunca nil' do
      com_papel(%w[report_manage])
      conversa(dono: agente)

      expect(resumo_de(agente)).to include(com_voce: 0, esperam: 0, sem_responsavel: 0, proxima: nil)
    end

    it 'só com conversation_manage não recebe a equipe' do
      com_papel(%w[conversation_manage])

      expect(resumo_de(agente)).not_to have_key(:equipe)
    end
  end

  # Os números da tela são os da lista. Se a regra de "não atendida" ou das abas mudar num lado só, isto quebra.
  describe 'paridade com a lista (ConversationFinder)' do
    # O ConversationFinder lê a conta do Current, como na requisição.
    def lista_de(user, filtros = {})
      Current.account = account
      ConversationFinder.new(user, filtros).perform_meta_only[:count]
    ensure
      Current.reset
    end

    before do
      conversa(dono: agente)
      conversa(dono: agente).update!(first_reply_created_at: 1.hour.ago, waiting_since: nil)
      conversa(dono: agente).update!(first_reply_created_at: 1.hour.ago, waiting_since: 5.minutes.ago)
      conversa(dono: admin)
      conversa
      conversa(inbox: create(:inbox, account: account))
    end

    [:admin, :agente].each do |quem|
      it "#{quem}: com você, sem responsável e esperam batem com as abas" do
        user = public_send(quem)
        resumo = resumo_de(user)

        expect(resumo[:com_voce]).to eq(lista_de(user)[:mine_count])
        expect(resumo[:sem_responsavel]).to eq(lista_de(user)[:unassigned_count])
        expect(resumo[:esperam]).to eq(lista_de(user, conversation_type: 'unattended')[:mine_count])
      end
    end

    it 'a equipe bate com "Não atendidas" na aba Todos do administrador' do
      expect(resumo_de(admin)[:equipe][:esperam]).to eq(lista_de(admin, conversation_type: 'unattended')[:all_count])
    end
  end

  it 'faz poucas consultas, sem N+1' do
    5.times { conversa(dono: agente) }
    consultas = 0
    contar = ->(*, payload) { consultas += 1 unless payload[:name].in?(%w[SCHEMA CACHE]) }

    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { resumo_de(agente) }

    expect(consultas).to be <= 6
  end
end
