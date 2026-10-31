require 'rails_helper'

# #1479 F3: a mensagem do robô já SAIU para o canal? É o que o cartão do turno espera antes de sair
# (`EnviarCartoesJob`). A regra é por tipo de caixa, pelo que cada envio grava de volta na mensagem.
RSpec.describe Autonomia::Agents::Operate::SaidaDaMensagem do
  let(:account) { create(:account) }

  def mensagem(inbox, **atributos)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'oi', **atributos)
  end

  def estado(message)
    described_class.estado(message.reload)
  end

  describe 'WhatsApp Cloud e 360' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    end

    it 'sem source_id: pendente (a Meta ainda não respondeu)' do
      expect(estado(mensagem(inbox))).to eq(:pendente)
    end

    it 'com o source_id que a Meta devolveu: saiu' do
      expect(estado(mensagem(inbox, source_id: 'wamid.ABC'))).to eq(:saiu)
    end

    it 'falhou' do
      expect(estado(mensagem(inbox, status: :failed))).to eq(:falhou)
    end
  end

  describe 'Híbrido pelo WhatsApp API (whatsapp_transport = web)' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    end
    let(:pelo_celular) { { 'whatsapp_transport' => 'web' } }

    it 'o id físico gravado ANTES do envio não prova que saiu' do
      expect(estado(mensagem(inbox, source_id: 'true_5511@c.us_ABC', content_attributes: pelo_celular))).to eq(:pendente)
    end

    it 'o motor aceitou (accepted): saiu' do
      atributos = pelo_celular.merge('whatsapp_transport_outcome' => 'accepted')
      expect(estado(mensagem(inbox, source_id: 'true_5511@c.us_ABC', content_attributes: atributos))).to eq(:saiu)
    end

    it 'o eco da Meta reconciliou (whatsapp_web_id): saiu' do
      atributos = pelo_celular.merge('whatsapp_web_id' => 'true_5511@c.us_ABC')
      expect(estado(mensagem(inbox, source_id: 'wamid.ABC', content_attributes: atributos))).to eq(:saiu)
    end

    it 'o ack de entregue: saiu' do
      expect(estado(mensagem(inbox, status: :delivered, content_attributes: pelo_celular))).to eq(:saiu)
    end

    it 'o plano B ainda em curso (pending) ou na espera do limite (throttled): pendente' do
      %w[pending throttled].each do |resultado|
        atributos = pelo_celular.merge('whatsapp_transport_outcome' => resultado)
        expect(estado(mensagem(inbox, content_attributes: atributos))).to eq(:pendente)
      end
    end

    it 'falhou ou ficou incerto (os dois gravam failed): falhou' do
      atributos = pelo_celular.merge('whatsapp_transport_outcome' => 'uncertain')
      expect(estado(mensagem(inbox, status: :failed, content_attributes: atributos))).to eq(:falhou)
    end
  end

  describe 'WAHA (caixa API do conector)' do
    let(:inbox) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511888880000' }).inbox }

    it 'recém-criada, sem sinal: pendente' do
      expect(estado(mensagem(inbox))).to eq(:pendente)
    end

    it 'o conector devolveu entregue ou lida: saiu' do
      expect(estado(mensagem(inbox, status: :delivered))).to eq(:saiu)
      expect(estado(mensagem(inbox, status: :read))).to eq(:saiu)
    end

    it 'sem sinal depois da espera fixa: saiu' do
      message = mensagem(inbox)
      travel(described_class::ESPERA_SEM_SINAL + 1.second) { expect(estado(message)).to eq(:saiu) }
    end

    it 'o conector devolveu falha: falhou' do
      expect(estado(mensagem(inbox, status: :failed))).to eq(:falhou)
    end
  end

  describe 'caixas sem envio externo' do
    it 'chat do site: saiu ao gravar' do
      expect(estado(mensagem(create(:inbox, account: account)))).to eq(:saiu)
    end

    it 'API comum (sem o conector WAHA): saiu ao gravar' do
      expect(estado(mensagem(create(:channel_api, account: account).inbox))).to eq(:saiu)
    end
  end

  describe 'outros canais com envio externo (e-mail, Instagram, Telegram...)' do
    let(:inbox) { create(:channel_email, account: account).inbox }

    it 'com source_id: saiu; sem ele, pendente até a espera fixa' do
      expect(estado(mensagem(inbox, source_id: '<abc@mail>'))).to eq(:saiu)
      message = mensagem(inbox)
      expect(estado(message)).to eq(:pendente)
      travel(described_class::ESPERA_SEM_SINAL + 1.second) { expect(estado(message)).to eq(:saiu) }
    end
  end
end
