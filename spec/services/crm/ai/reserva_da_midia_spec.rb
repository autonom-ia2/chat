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

  # #2141: a marca tem dono, e o prazo é contado no relógio do banco.
  describe 'o dono e o prazo da marca' do
    def anexo = Attachment.find(foto.id)

    def vencer_a_marca
      anexo.update!(meta: anexo.meta.merge(described_class::LENDO => 1.second.ago.iso8601(6)))
    end

    # Pega (item 2): o processo A demora mais que o PRAZO, a marca vence, B reserva, e A ao terminar apaga a marca de B.
    # Sem a marca, um terceiro reservaria e pagaria a mesma leitura de novo.
    it 'quem perdeu a marca grava o resultado e deixa a marca de quem reservou depois', :aggregate_failures do
      dono_a = described_class.reservar(anexo) { true }
      vencer_a_marca
      dono_b = described_class.reservar(anexo) { true }

      described_class.gravar(anexo, dono: dono_a) { |meta| meta.merge('ai_caption' => 'texto de A') }

      expect(dono_b).to be_present
      expect(dono_b).not_to eq(dono_a)
      expect(anexo.meta).to include('ai_caption' => 'texto de A', described_class::DONO => dono_b)
      expect(described_class.lendo?(anexo.meta)).to be(true)
      expect(described_class.reservar(anexo) { true }).to be_nil
    end

    it 'liberar de quem perdeu a marca não tira a marca do outro; o dono tira a própria', :aggregate_failures do
      dono_a = described_class.reservar(anexo) { true }
      vencer_a_marca
      dono_b = described_class.reservar(anexo) { true }

      described_class.liberar(anexo, dono: dono_a)
      expect(anexo.meta[described_class::DONO]).to eq(dono_b)

      described_class.liberar(anexo, dono: dono_b)
      expect(anexo.meta.keys).not_to include(described_class::LENDO, described_class::DONO)
    end

    # Pega: no deploy, o código anterior (sem dono) reserva depois que a marca de A venceu e regrava só o prazo; A, ao
    # terminar, tomaria a marca pelo dono que ficou e a tiraria.
    it 'a marca regravada pelo código anterior, sem dono, não passa por de quem reservou antes', :aggregate_failures do
      dono_a = described_class.reservar(anexo) { true }
      anexo.update!(meta: anexo.meta.merge(described_class::LENDO => described_class::PRAZO.from_now.iso8601))

      described_class.liberar(anexo, dono: dono_a)

      expect(described_class.lendo?(anexo.meta)).to be(true)
    end

    # Pega (item 3): a reserva comparar o prazo no relógio do processo. Um processo com o relógio adiantado veria a marca
    # vencida antes da hora e pagaria a mesma leitura; no relógio do banco, a marca segue valendo.
    it 'a reserva confere o prazo no relógio do banco, não no do processo', :aggregate_failures do
      described_class.reservar(anexo) { true }

      travel(described_class::PRAZO + 1.minute) do
        expect(described_class.reservar(anexo) { true }).to be_nil
      end
      travel(-(described_class::PRAZO + 1.minute)) do
        expect(described_class.reservar(anexo) { true }).to be_nil
      end
    end
  end

  # #2141 (itens 1 e 8): no deploy, o Sidekiq interrompe o job com Sidekiq::Shutdown. Pega: a marca ficar presa até o
  # PRAZO e o anexo não ser relido (nem pelo job reenfileirado, nem pelo turno dos Agentes).
  it 'o desligamento do Sidekiq no meio da leitura tira a marca', :aggregate_failures do
    allow(legendas).to receive(:caption).and_raise(Sidekiq::Shutdown)

    expect { leitor.perform }.to raise_error(Sidekiq::Shutdown)
    expect(Attachment.find(foto.id).meta.keys).not_to include(described_class::LENDO, described_class::DONO)
  end

  # #2141 (item 4): o turno dos Agentes IA transcrevia dentro do with_lock, com a transação aberta durante a chamada paga.
  # Pega: o anexo travado durante a transcrição do turno, e o leitor do CRM pagando a mesma transcrição.
  it 'o turno dos Agentes IA transcreve sem travar o anexo, e o leitor do CRM não paga de novo', :aggregate_failures do
    mensagem = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    audio = anexar_audio(mensagem)
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                              instruction: 'Atenda.')
    transcricoes = instance_double(Crm::Ai::TranscriptionClient)
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(transcricoes)
    allow(transcricoes).to receive(:transcribe) do
      na_api << true
      liberar_api.pop
      'texto do áudio'
    end

    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Autonomia::Agents::Operate::MessageMedia.new(messages: [Message.find(mensagem.id)], agent: agente).extract
      end
    end
    Timeout.timeout(10) { na_api.pop }

    expect(Attachment.find(audio.id).meta).to have_key(described_class::LENDO)
    expect { Timeout.timeout(2) { Attachment.find(audio.id).with_lock { nil } } }.not_to raise_error
    expect(Crm::Ai::LeitorDeMidia.new(Message.find(mensagem.id)).perform).to eq(0)

    liberar_api << true
    expect(workers.first.value.transcripts).to eq(['texto do áudio'])
    expect(Attachment.find(audio.id).meta).to include('transcribed_text' => 'texto do áudio')
    expect(Attachment.find(audio.id).meta.keys).not_to include(described_class::LENDO, described_class::DONO)
    expect(transcricoes).to have_received(:transcribe).once
  end
end
