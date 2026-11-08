require 'rails_helper'
require 'timeout'

# #2202 (PR 3) e #2461 — duas chamadas ao mesmo tempo, em conexões separadas, na mesma conversa ou no mesmo contato.
# A primeira para depois de ler a lista, dentro do lock; a segunda tem de esperar o lock e ler a lista já com a etiqueta
# da primeira. Sem o lock, a segunda leria a lista velha e a última gravação apagaria a etiqueta da outra.
RSpec.describe 'Pôr etiquetas ao mesmo tempo', :relationships_committed_fixtures, type: :request do
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

  before do
    create(:inbox_member, inbox: inbox, user: agente)
    [Conversation, Contact].each { |classe| pausar_depois_de_ler(classe) }
  end

  def pausar_depois_de_ler(classe)
    avisar = leu
    esperar = soltar
    allow_any_instance_of(classe).to receive(:label_list).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
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
    limpar_etiquetas!
    limpar_conversas!
    limpar_conta_e_pessoa!
  end

  def limpar_etiquetas!
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: account.conversations.ids).delete_all
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: account.contacts.ids).delete_all
    ActsAsTaggableOn::Tag.where.not(id: tags_antes).delete_all
  end

  def limpar_conversas!
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

  def pedir(rota, params, pausar: false)
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

  def duas_ao_mesmo_tempo(registro, rota)
    registro.update_labels(['vip'])
    primeira, pid_primeira = pedir(rota, { por: ['boleto'] }, pausar: true)
    Timeout.timeout(10) { leu.pop }
    segunda, pid_segunda = pedir(rota, { por: ['retorno'] })

    esperou = esperando_o_lock?(segunda, pid_segunda, pid_primeira)
    soltar << true
    terminaram = [primeira, segunda].all? { |thread| thread.join(15) }
    { esperou: esperou, terminaram: terminaram, respostas: terminaram && [primeira.value, segunda.value] }
  end

  def as_duas_valeram
    { esperou: true, terminaram: true, respostas: [[200, anything], [200, contain_exactly('vip', 'boleto', 'retorno')]] }
  end

  it 'na conversa, a segunda espera a primeira e as duas etiquetas ficam' do
    resultado = duas_ao_mesmo_tempo(conversa, "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/labels/alterar")

    expect(resultado).to match(as_duas_valeram)
    expect(conversa.reload.label_list).to contain_exactly('vip', 'boleto', 'retorno')
  end

  it 'no contato, a segunda espera a primeira e as duas etiquetas ficam (#2461)' do
    resultado = duas_ao_mesmo_tempo(conversa.contact, "/api/v1/accounts/#{account.id}/contacts/#{conversa.contact_id}/labels/alterar")

    expect(resultado).to match(as_duas_valeram)
    expect(conversa.contact.reload.label_list).to contain_exactly('vip', 'boleto', 'retorno')
  end
end
