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

  it 'não põe os argumentos (com o telefone) no log do ActiveJob' do
    saida = StringIO.new
    logger_original = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(Logger.new(saida))
    servico = instance_double(Etiquetas::AplicarEventoDoCelular, perform: nil)
    allow(Etiquetas::AplicarEventoDoCelular).to receive(:new).and_return(servico)

    described_class.perform_later({ inbox_id: 1, acao: 'vinculada', contact_phone: '+5511999990001' })
    described_class.perform_now({ inbox_id: 1, acao: 'vinculada', contact_phone: '+5511999990001' })

    expect(described_class.log_arguments?).to be(false)
    expect(saida.string).to include('WhatsappLabels::AplicarEvento')
    expect(saida.string).not_to include('5511999990001')
  ensure
    ActiveJob::Base.logger = logger_original
  end

  it 'evento malformado é descartado com log (classe, caixa e ação), sem o telefone e sem nova tentativa' do
    account = create(:account)
    account.enable_features!('etiquetas_do_celular')
    inbox = create(:inbox, account: account)
    allow(Rails.logger).to receive(:warn)

    [{ acao: 'arquivada', at: '2026-10-19T12:00:00Z' }, { acao: 'criada', at: 'ontem' }].each do |extra|
      evento = { inbox_id: inbox.id, contact_phone: '+5511999990001', label_wa_id: '7', nome: 'Pago' }.merge(extra)
      expect { described_class.perform_now(evento) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including('Etiquetas::AplicarEventoDoCelular::EventoInvalido', "inbox=#{inbox.id}", "acao=#{extra[:acao]}"))
    end

    expect(Rails.logger).not_to have_received(:warn).with(a_string_including('5511999990001'))
    expect(described_class).not_to have_been_enqueued
    expect(Etiquetas::DoCelular.count).to eq(0)
  end
end
