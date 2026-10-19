require 'rails_helper'
require 'timeout'

# #1823, F1b (revisão 2, item F) — corridas reais, duas conexões ao mesmo tempo. Sem transação de teste: o que cada thread
# grava é visível para a outra, e a limpeza é explícita no `after`.
RSpec.describe Etiquetas::AplicarEventoDoCelular, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account).tap { |conta| conta.enable_features!('etiquetas_do_celular') } }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contato) { create(:contact, account: account, phone_number: '+5511999990001') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contato, inbox: inbox, source_id: '5511999990001@c.us') }
  let!(:conversa) do
    create(:conversation, account: account, inbox: inbox, contact: contato, contact_inbox: contact_inbox, status: :open)
  end
  let(:workers) { [] }

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
  ensure
    limpar_tudo
  end

  def limpar_tudo
    limpar_etiquetas
    [Message, Conversation, Contact, Inbox, inbox.channel.class].each do |modelo|
      ContactInbox.where(inbox_id: inbox.id).delete_all if modelo == Contact
      modelo.where(account_id: account.id).delete_all
    end
    account.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def limpar_etiquetas
    titulos = Label.where(account_id: account.id).pluck(:title)
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: contato.id)
                             .or(ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: conversa.id))
                             .delete_all
    ActsAsTaggableOn::Tag.where(name: titulos).where.missing(:taggings).delete_all
    Etiquetas::DoCelular.where(account_id: account.id).delete_all # leva os vínculos (FK em cascata)
    Label.where(account_id: account.id).delete_all
  end

  # Segundos. Passou disso é trava presa, e o teste falha.
  def prazo
    10
  end

  def evento(acao, **extra)
    { inbox_id: inbox.id, chat_id: '5511999990001@c.us', contact_phone: '+5511999990001', label_wa_id: '3',
      nome: 'Novo cliente', color_index: 4, acao: acao, origem: 'celular', at: '2026-10-19T12:00:00Z' }.merge(extra)
  end

  # Cada evento numa thread com conexão própria; todas largam juntas. Devolve o que cada uma terminou: :ok ou o erro.
  def ao_mesmo_tempo(*eventos)
    largada = Queue.new
    prontas = Queue.new
    resultados = Queue.new
    eventos.each { |um_evento| workers << em_thread(um_evento, largada, prontas, resultados) }
    eventos.size.times { tirar(prontas, 'as threads não ficaram prontas') }
    eventos.size.times { largada << true }
    workers.each { |worker| expect(worker.join(prazo)).not_to be_nil, 'thread presa: trava sem fim' }
    Array.new(eventos.size) { tirar(resultados, 'thread terminou sem resultado') }
  end

  # `pop` com prazo: fila vazia depois dele é falha clara, não espera sem fim.
  def tirar(fila, motivo)
    item = fila.pop(timeout: prazo)
    raise "#{motivo} em #{prazo}s" if item.nil?

    item
  end

  def em_thread(um_evento, largada, prontas, resultados)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '#{prazo / 2}s'")
        prontas << true
        tirar(largada, 'a largada não veio')
        described_class.new(um_evento).perform
        resultados << :ok
      rescue StandardError => e
        resultados << e.class.name
      ensure
        conexao.execute('RESET lock_timeout') # a conexão volta ao pool: o prazo não vaza para outros specs
      end
    end
  end

  # As duas threads só seguem depois que as duas acharam o contato: assim chegam juntas às travas dele. Com a ordem
  # errada (vínculo gravado antes de travar o contato), este encontro termina em ActiveRecord::Deadlocked.
  def encontro_depois_de_achar_o_contato(quantas = 2)
    chegaram = 0
    mutex = Mutex.new
    todas = ConditionVariable.new
    allow(Etiquetas::EtiquetaNoContato).to receive(:new).and_wrap_original do |original, **argumentos|
      original.call(**argumentos).tap do |no_contato|
        allow(no_contato).to receive(:contato_do_evento).and_wrap_original do |achar|
          achar.call.tap do
            mutex.synchronize do
              chegaram += 1
              chegaram >= quantas ? todas.broadcast : todas.wait(mutex, prazo)
            end
          end
        end
      end
    end
  end

  it 'mesma etiqueta do celular criada em paralelo: um Label e uma correspondência' do
    resultados = ao_mesmo_tempo(evento('criada'), evento('criada', at: '2026-10-19T12:00:01Z'))

    expect(resultados).to eq(%i[ok ok])
    expect(Label.where(account_id: account.id).pluck(:title)).to eq(['novo_cliente'])
    expect(Etiquetas::DoCelular.where(inbox_id: inbox.id).count).to eq(1)
  end

  it 'mesmo contato com duas etiquetas em paralelo: as duas ficam, sem deadlock' do
    described_class.new(evento('criada')).perform
    described_class.new(evento('criada', label_wa_id: '4', nome: 'Pago')).perform
    encontro_depois_de_achar_o_contato

    resultados = ao_mesmo_tempo(evento('vinculada', at: '2026-10-19T12:01:00Z'),
                                evento('vinculada', label_wa_id: '4', nome: 'Pago', at: '2026-10-19T12:01:00Z'))

    expect(resultados).to eq(%i[ok ok])
    expect(Contact.find(contato.id).label_list).to contain_exactly('novo_cliente', 'pago')
    expect(Conversation.find(conversa.id).label_list).to contain_exactly('novo_cliente', 'pago')
    expect(Etiquetas::DoCelularNoContato.where(contact_id: contato.id).pluck(:vinculada)).to eq([true, true])
  end

  it 'mesmo contato, vinculada sem correspondência em paralelo (cria e vincula): as duas ficam, sem deadlock' do
    encontro_depois_de_achar_o_contato

    resultados = ao_mesmo_tempo(evento('vinculada'), evento('vinculada', label_wa_id: '4', nome: 'Pago'))

    expect(resultados).to eq(%i[ok ok])
    expect(Contact.find(contato.id).label_list).to contain_exactly('novo_cliente', 'pago')
    expect(Conversation.find(conversa.id).label_list).to contain_exactly('novo_cliente', 'pago')
  end
end
