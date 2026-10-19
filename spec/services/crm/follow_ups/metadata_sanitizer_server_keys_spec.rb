require 'rails_helper'

# Provas do servidor no metadata do follow-up: o cliente não as grava nem as forja pela API (#1624, #1585).
RSpec.describe Crm::FollowUps::MetadataSanitizer do
  it 'tira do metadata do cliente o pré-voo, o registro do envio e o transporte do Híbrido' do
    metadata = { 'message_body' => 'oi', 'preflight' => { 'estado' => 'pronto' }, 'envio_fora_da_janela' => { 'tipo' => 'retorno' },
                 'delivery_transport' => 'whatsapp_api', 'hybrid_free_form_reason' => 'x' }

    expect(described_class.without_server_keys(metadata)).to eq('message_body' => 'oi')
  end
end
