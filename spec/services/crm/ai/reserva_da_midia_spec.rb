require 'rails_helper'
require 'timeout'

# #2109 (revisão de banco) — com duas conexões reais. Enquanto o leitor de mídia espera a API: o anexo não fica travado
# (outra conexão pega o FOR UPDATE na hora, sem transação aberta segurando a linha); a reserva impede a segunda leitura
# paga; e a escrita do resultado não apaga o que outra conexão gravou no meta durante a leitura.
RSpec.describe Crm::Ai::ReservaDaMidia, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
  let(:foto) { anexar_imagem(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)) }
  let(:legendas) { instance_double(Crm::Ai::VisionCaptioner) }
  let(:na_api) { Queue.new }
  let(:liberar_api) { Queue.new }
  let(:workers) { [] }

  def leitor = Crm::Ai::LeitorDeMidia.new(Message.find(foto.message_id))

  before do
    limpar_redis_do_leitor
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
    allow(Crm::Ai::VisionCaptioner).to receive(:new).and_return(legendas)
    allow(legendas).to receive(:caption) do
      na_api << true
      liberar_api.pop
      'descrição da foto'
    end
  end

  after do
    liberar_api << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
  ensure
    apagar_a_conta
  end

  def apagar_a_conta
    conexao = ActiveRecord::Base.connection
    conexao.execute('SET session_replication_role = replica')
    conexao.tables.select { |tabela| conexao.column_exists?(tabela, :account_id) }.each do |tabela|
      conexao.execute("DELETE FROM #{conexao.quote_table_name(tabela)} WHERE account_id = #{account.id.to_i}")
    end
    conexao.execute("DELETE FROM accounts WHERE id = #{account.id.to_i}")
  ensure
    conexao.execute('SET session_replication_role = origin')
  end

  it 'a leitura paga roda sem travar o anexo, não paga duas vezes e grava sobre o meta atual', :aggregate_failures do
    workers << Thread.new { ActiveRecord::Base.connection_pool.with_connection { leitor.perform } }
    Timeout.timeout(10) { na_api.pop }

    expect(Attachment.find(foto.id).meta).to have_key(described_class::LENDO)
    expect { Timeout.timeout(2) { Attachment.find(foto.id).with_lock { nil } } }.not_to raise_error
    expect(leitor.perform).to eq(0)
    escrita = Attachment.find(foto.id)
    escrita.update!(meta: escrita.meta.merge('escrita_no_meio' => 1))

    liberar_api << true
    expect(workers.first.value).to eq(1)
    expect(Attachment.find(foto.id).meta).to include('ai_caption' => 'descrição da foto', 'escrita_no_meio' => 1)
    expect(Attachment.find(foto.id).meta).not_to have_key(described_class::LENDO)
    expect(legendas).to have_received(:caption).once
  end

  it 'a leitura em linha espera o texto do anexo que o outro processo está lendo', :aggregate_failures do
    workers << Thread.new { ActiveRecord::Base.connection_pool.with_connection { leitor.perform } }
    Timeout.timeout(10) { na_api.pop }
    Thread.new do
      sleep(1)
      liberar_api << true
    end

    Crm::Ai::LeitorDeMidia.ler_em_linha(Message.find(foto.message_id))

    expect(Attachment.find(foto.id).meta['ai_caption']).to eq('descrição da foto')
    expect(legendas).to have_received(:caption).once
  end
end
