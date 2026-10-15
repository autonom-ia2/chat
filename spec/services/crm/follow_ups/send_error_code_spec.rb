require 'rails_helper'

RSpec.describe Crm::FollowUps::SendErrorCode do
  def follow_up(status:, metadata:)
    Crm::FollowUp.new(status: status, metadata: metadata)
  end

  it 'traduz os motivos conhecidos do envio e junta o resto em "outro"' do
    {
      'conversation_required' => 'sem_conversa',
      'not_whatsapp_capable' => 'canal',
      'sender_required' => 'sem_remetente',
      'whatsapp_api_unavailable' => 'celular_desconectado',
      'template_name_required' => 'sem_modelo',
      'whatsapp_api_message_template_id is required outside the messaging window' => 'sem_modelo',
      'whatsapp_api_message_template is invalid for this conversation inbox' => 'modelo_invalido',
      '(#131047) Re-engagement message' => 'outro'
    }.each do |erro, codigo|
      expect(described_class.for(follow_up(status: :overdue, metadata: { 'send_error' => erro }))).to eq(codigo)
    end
  end

  it 'só fala da falha enquanto ela vale: reagendado (pendente) não mostra o motivo antigo' do
    expect(described_class.for(follow_up(status: :pending, metadata: { 'send_error' => 'sender_required' }))).to be_nil
    expect(described_class.for(follow_up(status: :overdue, metadata: {}))).to be_nil
  end

  it 'diz quando o cliente pediu para não receber mensagens' do
    cancelado = follow_up(status: :canceled, metadata: { 'canceled_reason' => 'opt_out' })

    expect(described_class.for(cancelado)).to eq('recusou')
  end
end
