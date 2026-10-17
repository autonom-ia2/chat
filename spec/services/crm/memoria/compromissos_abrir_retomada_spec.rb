require 'rails_helper'

# Concorrência real (#1601, invariante 10): duas threads, cada uma com a sua conexão, sem a transação do teste.
RSpec.describe Crm::Memoria::Compromissos, '.abrir_retomada!' do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:conversation) { create(:conversation, account: account) }

  before { ligar_memoria!(account) }

  after { limpar_conta!(account) }

  it 'duas aberturas ao mesmo tempo deixam UMA tarefa (trava da conversa e índice único)' do
    largada = Queue.new
    threads = Array.new(2) do
      Thread.new do
        largada.pop
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.abrir_retomada!(conversation: Conversation.find(conversation.id), origem: 'segurada')
        end
      end
    end
    2.times { largada << true }
    threads.each(&:join)

    expect(described_class.da_conversa(conversation).count).to eq(1)
  end
end
