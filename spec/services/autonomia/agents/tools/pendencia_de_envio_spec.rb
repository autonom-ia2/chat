require 'rails_helper'

# A PENDÊNCIA DE ENVIO (rodada 8 da entrega 11, P2 do Codex): a marca na própria mensagem que diz "o
# `SendReplyJob` desta mensagem não entrou na fila". O que estes exemplos travam é a ESCRITA no banco:
# uma só, atômica, que mescla sem apagar o resto do `content_attributes`, e que respeita a forma com
# que o `store ... coder: JSON` da `Message` grava a coluna (uma STRING JSON, não o objeto).
RSpec.describe Autonomia::Agents::Tools::PendenciaDeEnvio do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:mensagem) do
    create(:message, account: account, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'autonomia_async_token' => 'abc:1', 'autonomia_async_sequence' => 0 })
  end

  def tipo_no_banco
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(['SELECT json_typeof(content_attributes) FROM messages WHERE id = ?', mensagem.id])
    )
  end

  it 'marca mesclando, na forma que a Message le de volta, sem apagar o resto do content_attributes' do
    # Act
    described_class.marcar(mensagem, contexto: 'run=1')

    # Assert — a coluna continua uma string JSON (a forma do coder da Message), lida pelo Rails
    expect(tipo_no_banco).to eq('string')
    expect(mensagem.reload.content_attributes).to include('autonomia_envio_pendente' => true, 'autonomia_async_token' => 'abc:1',
                                                          'autonomia_async_sequence' => 0)
    expect(described_class).to be_pendente(mensagem)
  end

  it 'limpa so a marca' do
    # Arrange
    described_class.marcar(mensagem, contexto: 'run=1')

    # Act
    described_class.limpar(mensagem, contexto: 'run=1')

    # Assert
    expect(tipo_no_banco).to eq('string')
    expect(mensagem.reload.content_attributes).not_to have_key('autonomia_envio_pendente')
    expect(mensagem.content_attributes).to include('autonomia_async_token' => 'abc:1', 'autonomia_async_sequence' => 0)
    expect(described_class).not_to be_pendente(mensagem)
  end

  # A marca não é pendência quando o canal já confirmou (`source_id`) nem na nota privada (não vai ao canal).
  it 'nao e pendencia com o canal confirmado, na nota privada, nem sem a marca' do
    described_class.marcar(mensagem, contexto: 'run=1')
    mensagem.reload

    expect(described_class).not_to be_pendente(build(:message, content_attributes: {}))
    expect(described_class).not_to be_pendente(mensagem.tap { |m| m.source_id = 'wamid.1' })
    expect(described_class).not_to be_pendente(mensagem.tap { |m| m.source_id = nil }.tap { |m| m.private = true })
  end

  # A falha da escrita (banco) é registrada com código fechado e não levanta: quem chama decide o
  # resultado pela fila, não pela marca.
  it 'registra e nao levanta quando o banco nao grava a marca' do
    allow(Message).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'banco fora')
    allow(Rails.logger).to receive(:warn).and_call_original

    expect { described_class.marcar(mensagem, contexto: 'run=1') }.not_to raise_error
    expect { described_class.limpar(mensagem, contexto: 'run=1') }.not_to raise_error
    nao_gravada = /pendencia de envio nao gravada run=1 message=#{mensagem.id} motivo=marca_nao_gravada causa=ActiveRecord::StatementInvalid/
    nao_limpa = /pendencia de envio nao gravada run=1 message=#{mensagem.id} motivo=marca_nao_limpa causa=ActiveRecord::StatementInvalid/
    expect(Rails.logger).to have_received(:warn).with(a_string_matching(nao_gravada))
    expect(Rails.logger).to have_received(:warn).with(a_string_matching(nao_limpa))
  end
end
