require 'rails_helper'
require 'timeout'

# #2202 (PR 3) — duas chamadas ao mesmo tempo, em conexões separadas, na mesma conversa. A primeira para depois de
# ler a lista, dentro do lock; a segunda tem de esperar o lock e ler a lista já com a etiqueta da primeira. Sem o lock,
# a segunda leria a lista velha e a última gravação apagaria a etiqueta da outra.
RSpec.describe 'Pôr etiquetas ao mesmo tempo na mesma conversa', :relationships_committed_fixtures, type: :request do
  self.use_transactional_tests = false

  # Etiqueta (tag) é global: guarda as que já existiam para apagar só as criadas aqui.
  let!(:tags_antes) { ActsAsTaggableOn::Tag.ids }
  let!(:account) { create(:account) }
  let!(:agente) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:leu) { Queue.new }
  let(:soltar) { Queue.new }
  let(:threads) { [] }
  let(:rota) { "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/labels/alterar" }

  before do
    create(:inbox_member, inbox: inbox, user: agente)
    conversa.update_labels(['vip'])
    avisar = leu
    esperar = soltar
    allow_any_instance_of(Conversation).to receive(:label_list).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      lista = original.call(*args)
      if Thread.current[:pausar_depois_de_ler]
        Thread.current[:pausar_depois_de_ler] = false
        avisar << true
        esperar.pop
      end
      lista
    end
  end

  after do
    soltar << true
    threads.each { |thread| thread.join(5) || thread.kill.join }
  ensure
    limpar_dados!
  end

  def limpar_dados!
    limpar_conversas!
    limpar_conta_e_pessoa!
  end

  def limpar_conversas!
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: account.conversations.ids).delete_all
    ActsAsTaggableOn::Tag.where.not(id: tags_antes).delete_all
    Message.where(account_id: account.id).delete_all
    Conversation.where(account_id: account.id).delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    Contact.where(account_id: account.id).delete_all
  end

  def limpar_conta_e_pessoa!
    InboxMember.where(inbox_id: inbox.id).delete_all
    inbox.destroy!
    account.account_users.destroy_all
    account.destroy!
    NotificationSetting.where(user_id: agente.id).delete_all
    AccessToken.where(owner: agente).delete_all
    agente.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def pedir(params, pausar: false)
    pronto = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '10s'")
        pronto << conexao.select_value('SELECT pg_backend_pid()')
        Thread.current[:pausar_depois_de_ler] = pausar
        sessao = ActionDispatch::Integration::Session.new(Rails.application)
        sessao.patch(rota, params: params, headers: agente.create_new_auth_token, as: :json)
        [sessao.response.status, sessao.response.parsed_body['payload']]
      ensure
        conexao.execute('SET lock_timeout TO DEFAULT')
      end
    end
    threads << thread
    [thread, Timeout.timeout(10) { pronto.pop }]
  end

  def esperando_o_lock?(thread, pid, quem_trava)
    Timeout.timeout(10) do
      loop do
        return true if ActiveRecord::Base.connection.select_value(
          "SELECT #{Integer(quem_trava)} = ANY(pg_blocking_pids(#{Integer(pid)}))"
        )
        return false unless thread.alive?

        sleep 0.01
      end
    end
  end

  it 'a segunda espera a primeira e as duas etiquetas ficam' do
    primeira, pid_primeira = pedir({ por: ['boleto'] }, pausar: true)
    Timeout.timeout(10) { leu.pop }
    segunda, pid_segunda = pedir({ por: ['retorno'] })

    esperou = esperando_o_lock?(segunda, pid_segunda, pid_primeira)
    soltar << true

    expect([primeira, segunda].map { |thread| thread.join(15) }).to eq([primeira, segunda])
    expect(esperou).to be(true)
    expect(primeira.value.first).to eq(200)
    expect(segunda.value).to match([200, contain_exactly('vip', 'boleto', 'retorno')])
    expect(conversa.reload.label_list).to contain_exactly('vip', 'boleto', 'retorno')
  end
end
