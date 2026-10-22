require 'rails_helper'

RSpec.describe Crm::Ai::LerMidiaJob do
  include ActiveJob::TestHelper

  describe 'com o leitor dublê' do
    let(:message) { create(:message) }
    let(:leitor) { instance_double(Crm::Ai::LeitorDeMidia, perform: 1) }

    before { allow(Crm::Ai::LeitorDeMidia).to receive(:new).and_return(leitor) }

    it 'lê os anexos da mensagem', :aggregate_failures do
      described_class.perform_now(message.id)

      expect(Crm::Ai::LeitorDeMidia).to have_received(:new).with(message, ultima_tentativa: false)
      expect(leitor).to have_received(:perform)
    end

    it 'mensagem que sumiu: não faz nada' do
      described_class.perform_now(0)

      expect(Crm::Ai::LeitorDeMidia).not_to have_received(:new)
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

    it 'com a flag desligada, nada muda: não lê, não marca e não reagenda', :aggregate_failures do
      account.disable_features!(Crm::Ai::LeitorDeMidia::FLAG)
      allow(legendas).to receive(:caption).and_raise(ActiveStorage::FileNotFoundError)

      described_class.perform_now(foto.message_id)

      expect(meta).not_to have_key('crm_ai_image_done')
      expect(legendas).not_to have_received(:caption)
      expect(described_class).not_to have_been_enqueued
    end
  end
end
