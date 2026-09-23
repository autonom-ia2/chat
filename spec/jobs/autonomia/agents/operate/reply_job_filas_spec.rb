require 'rails_helper'

# A RESPOSTA AO CLIENTE NÃO ESPERA AS CONSULTAS DA COTAÇÃO (Rodrigo, 23/09/2026). As filas do Sidekiq são de
# prioridade estrita: a `low` só anda com as de cima vazias, e com várias cotações em curso a `medium` quase nunca
# esvazia. A resposta da Lia e a entrega dela em pedaços ficam na mesma fila das consultas.
RSpec.describe Autonomia::Agents::Operate::ReplyJob do
  it 'a resposta e a entrega em pedaços rodam na medium, junto das consultas da cotação' do
    expect(described_class.queue_name).to eq('medium')
    expect(Autonomia::Agents::Operate::ChunkedDeliveryJob.queue_name).to eq('medium')
    expect(Autonomia::Agents::Tools::AsyncRunJob.queue_name).to eq('medium')
  end
end
