require 'rails_helper'

# #1637: o teto da espera do assunto conta de quando a mensagem ficou pronta, `content_attributes['hybrid_recovered_at']`
# (contrato com o WhatsApp Híbrido, #1489) quando ele está entre o created_at e agora. Cada exemplo cria a mensagem 30 s
# atrás, sem marco: `esperar?` true = ainda dentro do teto (contou da recuperação); false = teto estourado (contou do
# created_at).
RSpec.describe Autonomia::Agents::Operate::EsperaDoAssunto, :um_turno do
  include_context 'with crm responsible agent'

  let(:mensagem) { cliente_escreve('quero o boleto') }

  before do
    contrato!(ordem: true)
    mensagem
    travel 30.seconds
  end

  def recuperada!(valor)
    mensagem.update!(content_attributes: { 'hybrid_recovered_at' => valor })
  end

  def esperar?
    described_class.esperar?(conversation: conversation, agent_inbox: vinculo_da_porta, message_id: mensagem.id)
  end

  it 'recuperada 5 s atrás (UTC, com Z): espera o assunto' do
    recuperada!(5.seconds.ago.utc.iso8601)

    expect(esperar?).to be(true)
  end

  it 'recuperada_em no futuro não adia o teto: vale o created_at e grava assunto_atrasou' do
    recuperada!(1.hour.from_now.utc.iso8601)

    expect(esperar?).to be(false)
    expect(Autonomia::Agents::AgentEvent.skipped_assunto_atrasou.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'recuperação anterior ao created_at: vale o created_at' do
    recuperada!(1.hour.ago.utc.iso8601)

    expect(esperar?).to be(false)
  end

  it 'content_attributes nil: vale o created_at, sem erro' do
    mensagem.update_column(:content_attributes, nil) # rubocop:disable Rails/SkipsModelValidations

    expect(esperar?).to be(false)
  end

  it 'string vazia: vale o created_at' do
    recuperada!('')

    expect(esperar?).to be(false)
  end

  # O fuso da aplicação é diferente do fuso do processo de propósito: o parser do processo erraria por horas.
  describe 'fuso' do
    around { |example| Time.use_zone('Asia/Tokyo') { example.run } }

    it 'offset explícito: lido no offset que veio' do
      recuperada!(5.seconds.ago.in_time_zone('America/Sao_Paulo').iso8601)

      expect(esperar?).to be(true)
    end

    it 'sem offset: lido no fuso da aplicação (Time.zone)' do
      recuperada!(5.seconds.ago.in_time_zone.strftime('%Y-%m-%dT%H:%M:%S'))

      expect(esperar?).to be(true)
    end
  end
end
