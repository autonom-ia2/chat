require 'rails_helper'

# #1453: depois de erro inesperado no reenvio pelo WhatsApp API, o resultado fecha pelo que já aconteceu.
RSpec.describe WhatsappHybrid::UnexpectedErrorOutcome, :aggregate_failures do
  let(:message) { create(:message, message_type: :outgoing, status: :sent, content_attributes: attributes) }

  def settle
    described_class.settle!(message, external_error: '131047: Re-engagement message')
  end

  describe 'quando o motor já aceitou' do
    let(:attributes) { { 'whatsapp_transport' => 'web', 'whatsapp_transport_outcome' => 'accepted' } }

    it 'deixa a mensagem como está' do
      expect(settle).to eq('accepted')
      expect(message.reload).to be_sent
    end
  end

  describe 'quando estava esperando o limite por minuto (o pedido não saiu)' do
    let(:attributes) { { 'whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'throttled' } }

    it 'fecha como failed, com o erro original' do
      expect(settle).to eq('failed')
      expect(message.reload).to be_failed
      expect(message.content_attributes).to include('external_error' => '131047: Re-engagement message', 'whatsapp_transport_fallback' => true)
    end
  end

  describe 'quando o envio ainda não tinha sido marcado' do
    let(:attributes) { { 'whatsapp_transport_fallback' => true } }

    it 'fecha como failed' do
      expect(settle).to eq('failed')
    end
  end

  describe 'quando o envio foi marcado e não há resultado (pode ter saído)' do
    let(:attributes) { { 'whatsapp_transport_fallback' => true, 'whatsapp_transport' => 'web' } }

    it 'fecha como uncertain, com o aviso de conferir no celular (não o erro da Meta)' do
      expect(settle).to eq('uncertain')
      expect(message.reload).to be_failed
      expect(message.content_attributes['external_error']).to eq(WhatsappHybrid::WebTransport::UNCONFIRMED_ERROR)
    end
  end

  describe 'quando o plano B assumiu e ainda não chamou o motor (pending)' do
    let(:attributes) { { 'whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'pending' } }

    it 'fecha como failed, com o erro original' do
      expect(settle).to eq('failed')
      expect(message.reload.content_attributes['external_error']).to eq('131047: Re-engagement message')
    end
  end

  describe 'quando já estava fechado' do
    let(:attributes) { { 'whatsapp_transport' => 'web', 'whatsapp_transport_outcome' => 'uncertain', 'external_error' => 'sem resposta' } }

    it 'mantém o resultado e o erro gravados' do
      expect(settle).to eq('uncertain')
      expect(message.reload.content_attributes['external_error']).to eq('sem resposta')
    end
  end
end
