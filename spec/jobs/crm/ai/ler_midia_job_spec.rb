require 'rails_helper'

RSpec.describe Crm::Ai::LerMidiaJob do
  include ActiveJob::TestHelper

  describe 'com o leitor dublê' do
    let(:message) { create(:message) }
    let(:leitor) { instance_double(Crm::Ai::LeitorDeMidia, perform: 1) }

    before { allow(Crm::Ai::LeitorDeMidia).to receive(:new).and_return(leitor) }

    it 'lê os anexos da mensagem', :aggregate_failures do
      described_class.perform_now(message.id)

      expect(Crm::Ai::LeitorDeMidia).to have_received(:new).with(message, ultima_tentativa: false, releitura: :mensagem_nova, uma_chamada: false)
      expect(leitor).to have_received(:perform)
    end

    it 'mensagem que sumiu: não faz nada' do
      described_class.perform_now(0)

      expect(Crm::Ai::LeitorDeMidia).not_to have_received(:new)
    end

    it 'a releitura vai na fila low, uma vez por mensagem dentro do prazo', :aggregate_failures do
      Redis::Alfred.delete("crm:leitor_de_midia:releitura:#{message.id}")

      expect(described_class.reler(message.id, 'varredura')).to be(true)
      expect(described_class.reler(message.id, 'mensagem_nova')).to be(false)
      expect(described_class).to have_been_enqueued.with(message.id, 'varredura').on_queue('low').once
    end

    it 'vai na fila high' do
      expect(described_class.new.queue_name).to eq('high')
    end
  end

  # A corrida da chegada: o job roda no commit da mensagem, antes de o upload do anexo terminar.
  describe 'arquivo que ainda não chegou ao storage' do
    let(:account) { create(:account) }
    let(:inbox) { create_crm_inbox(account: account) }
    let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
    let(:foto) { anexar_imagem(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)) }
    let(:legendas) { instance_double(Crm::Ai::VisionCaptioner) }

    def meta = foto.reload.meta.to_h

    before do
      account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
      allow(Crm::Ai::VisionCaptioner).to receive(:new).and_return(legendas)
      clear_enqueued_jobs
    end

    it 'não marca o anexo e reagenda o job', :aggregate_failures do
      allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError)

      described_class.perform_now(foto.message_id)

      expect(meta).not_to have_key('crm_ai_image_done')
      expect(described_class).to have_been_enqueued.with(foto.message_id).on_queue('high')
    end

    it 'o arquivo chega na segunda tentativa: lê', :aggregate_failures do
      tentativas = 0
      allow(legendas).to receive(:caption) do
        tentativas += 1
        raise ActiveStorage::FileNotFoundError if tentativas == 1

        'descrição da foto'
      end

      perform_enqueued_jobs { described_class.perform_later(foto.message_id) }

      expect(meta).to include('ai_caption' => 'descrição da foto', 'crm_ai_image_done' => true)
      expect(legendas).to have_received(:caption).twice
    end

    it 'esgotou as tentativas: marca o anexo sem texto', :aggregate_failures do
      allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError)

      perform_enqueued_jobs { described_class.perform_later(foto.message_id) }

      expect(meta['crm_ai_image_done']).to be(true)
      expect(meta).not_to have_key('ai_caption')
      expect(legendas).to have_received(:caption).exactly(described_class::TENTATIVAS).times
    end

    it 'falha passageira da API: não marca e reagenda com espera', :aggregate_failures do
      allow(legendas).to receive(:caption).and_raise(Faraday::TooManyRequestsError)

      described_class.perform_now(foto.message_id)

      expect(meta).not_to have_key('crm_ai_image_done')
      expect(described_class).to have_been_enqueued.with(foto.message_id).on_queue('high')
    end

    it 'falha passageira: vencida a espera, a nova tentativa lê', :aggregate_failures do
      tentativas = 0
      allow(legendas).to receive(:caption) do
        tentativas += 1
        raise Faraday::ServerError if tentativas == 1

        'descrição da foto'
      end

      described_class.perform_now(foto.message_id)
      travel(2.minutes) { described_class.perform_now(foto.message_id) }

      expect(meta).to include('ai_caption' => 'descrição da foto', 'crm_ai_image_done' => true, 'crm_ai_midia_tentativas' => 1)
      expect(legendas).to have_received(:caption).twice
    end

    it 'com a flag desligada, nada muda: não lê, não marca e não reagenda', :aggregate_failures do
      account.disable_features!(Crm::Ai::LeitorDeMidia::FLAG)
      allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError)

      described_class.perform_now(foto.message_id)

      expect(meta).not_to have_key('crm_ai_image_done')
      expect(legendas).not_to have_received(:caption)
      expect(described_class).not_to have_been_enqueued
    end
  end

  # #2109, revisão adversarial: numa queda da API (ReadTimeout), a releitura segurava uma thread do Sidekiq por ~9 min
  # (3 chamadas de 180 s mais as esperas), e as threads são as mesmas da entrega de mensagens. Pega: a releitura voltar a
  # tentar de novo dentro do job, seguir para o próximo anexo com a API fora, ou usar um tempo menor que o da chegada
  # (a leitura longa nunca terminaria e seria cobrada a cada vez); a chegada perder as novas tentativas dela.
  describe 'API da IA fora do ar (tempo esgotado)' do
    let(:account) { create(:account) }
    let(:inbox) { create_crm_inbox(account: account) }
    let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
    let(:mensagem) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }
    let(:png) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

    def meta(anexo) = anexo.reload.meta.to_h

    before do
      limpar_redis_do_leitor
      account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_wrap_original do |original, **opcoes|
        original.call(**opcoes).tap { |cliente| allow(cliente).to receive(:sleep) }
      end
      clear_enqueued_jobs
    end

    it 'releitura: uma chamada só, com o tempo da chegada, para no 1º anexo e não cria job novo', :aggregate_failures do
      foto, outra = Array.new(2) { mensagem.attachments.create!(account: account, file_type: :image, file: png) }

      described_class.perform_now(mensagem.id, 'varredura')

      expect(HTTParty).to have_received(:post).once
      expect(HTTParty).to have_received(:post).with(anything, hash_including(timeout: Crm::Ai::ResponsesClient::REQUEST_TIMEOUT))
      expect(described_class).not_to have_been_enqueued
      expect(meta(foto)).to include('crm_ai_midia_tentativas' => 1).and(have_key('crm_ai_midia_proxima_em'))
      expect(meta(foto)).not_to have_key('crm_ai_image_done')
      expect(meta(outra)).not_to include('crm_ai_midia_tentativas', 'crm_ai_image_done')
    end

    it 'chegada da foto: mantém as novas tentativas do cliente, o tempo longo e o novo job', :aggregate_failures do
      mensagem.attachments.create!(account: account, file_type: :image, file: png)

      described_class.perform_now(mensagem.id)

      longo = hash_including(timeout: Crm::Ai::ResponsesClient::REQUEST_TIMEOUT)
      expect(HTTParty).to have_received(:post).with(anything, longo).exactly(Crm::Ai::ResponsesClient::MAX_RETRIES + 1).times
      expect(described_class).to have_been_enqueued.with(mensagem.id).on_queue('high')
    end

    it 'chegada com dois anexos: tenta os dois (a parada no 1º é só da releitura)' do
      Array.new(2) { mensagem.attachments.create!(account: account, file_type: :image, file: png) }

      described_class.perform_now(mensagem.id)

      expect(HTTParty).to have_received(:post).exactly(2 * (Crm::Ai::ResponsesClient::MAX_RETRIES + 1)).times
    end
  end

  # #2109: a varredura só relê mensagem do cliente. Pega: o log prometer a varredura para a mídia que a equipe mandou.
  describe 'aviso quando as tentativas da chegada acabam' do
    let(:erro) { Crm::Ai::LeitorDeMidia::FalhaPassageira.new('mensagem=1 anexos=2') }

    before { allow(Rails.logger).to receive(:warn) }

    it 'mensagem do cliente: fica para a varredura' do
      described_class.new(create(:message, message_type: :incoming).id).avisar_desistencia(erro)

      expect(Rails.logger).to have_received(:warn).with(a_string_including('falha_passageira_fica_para_a_varredura'))
    end

    it 'mensagem apagada: não diz que é da equipe' do
      described_class.new(0).avisar_desistencia(erro)

      expect(Rails.logger).to have_received(:warn).with(a_string_including('falha_passageira_sem_varredura mensagem_apagada'))
    end

    it 'mensagem da equipe: diz que a varredura não relê' do
      described_class.new(create(:message, message_type: :outgoing).id).avisar_desistencia(erro)

      expect(Rails.logger).to have_received(:warn).with(a_string_including('falha_passageira_sem_varredura mensagem_de_saida'))
    end
  end
end
