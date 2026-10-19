require 'rails_helper'

# #1823, F1b — o job do contrato com o webhook do Híbrido chama o serviço com o evento.
RSpec.describe WhatsappLabels::AplicarEvento do
  it 'entra na fila default e aplica o evento' do
    evento = { inbox_id: 1, acao: 'apagada', label_wa_id: '5' }
    servico = instance_double(Etiquetas::AplicarEventoDoCelular, perform: nil)
    allow(Etiquetas::AplicarEventoDoCelular).to receive(:new).with(evento).and_return(servico)

    expect { described_class.perform_later(evento) }.to have_enqueued_job(described_class).on_queue('default')
    described_class.perform_now(evento)

    expect(servico).to have_received(:perform)
  end

  it 'aceita o evento serializado pela fila (chaves em texto)' do
    account = create(:account)
    account.enable_features!('etiquetas_do_celular')
    inbox = create(:inbox, account: account)
    evento = { 'inbox_id' => inbox.id, 'chat_id' => nil, 'contact_phone' => nil, 'label_wa_id' => '7', 'nome' => 'Pago',
               'color_index' => 2, 'acao' => 'criada', 'origem' => 'celular', 'at' => '2026-10-19T12:00:00Z' }

    perform_enqueued_jobs { described_class.perform_later(evento) }

    expect(Etiquetas::DoCelular.sole).to have_attributes(label_wa_id: '7', nome: 'Pago', color_index: 2)
  end
end
