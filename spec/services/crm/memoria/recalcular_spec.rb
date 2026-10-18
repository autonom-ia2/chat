require 'rails_helper'

# A mensagem de prova apagada ou EDITADA pelo cliente (#1601; edição: decisão do Rodrigo de 17/10, opção A).
RSpec.describe Crm::Memoria::Recalcular do
  include_context 'with crm responsible agent'

  let(:card) { create_card(pipeline: suporte) }

  before do
    ligar_memoria!(account)
    conversation.reload
  end

  def fato!(chave, valor, provas, **extra)
    Crm::Memoria::Gravador.gravar!({ account_id: account.id, contact_id: contact.id, escopo: 'card', card_id: card.id, tipo: 'fato',
                                     chave: chave, valor: valor, fonte: 'cliente', prova_message_ids: provas.map(&:id),
                                     gerado_por: 't' }.merge(extra))
  end

  def editar(message, texto)
    message.update!(content: texto)
    Crm::Memoria::MensagemJob.perform_now(message.id, 'editada')
  end

  it '"2002" editado para "2022": o 2002 deixa de valer na hora e o card é reavaliado de carona (opção A)' do
    mensagem = mensagem!(conversation, :incoming, content: 'o carro é ano 2002')
    ano = fato!('ano', '2002', [mensagem])
    observer = instance_double(Crm::Ai::Observer, schedule_evaluation: nil)
    allow(Crm::Ai::Observer).to receive(:new).and_return(observer)

    editar(mensagem, 'o carro é ano 2022')

    expect(ano.reload.expirado_em).to be_present
    expect(Crm::MemoriaFato.vivos.where(chave: 'ano')).to be_empty
    expect(observer).to have_received(:schedule_evaluation).at_least(:once)
  end

  it 'o valor que continua no texto editado não muda' do
    mensagem = mensagem!(conversation, :incoming, content: 'placa ABC1D23, ano 2002')
    placa = fato!('placa', 'ABC1D23', [mensagem])

    editar(mensagem, 'placa ABC1D23, ano 2022')

    expect(placa.reload.expirado_em).to be_nil
  end

  it 'fato com duas provas perde só a editada: versão nova, gerada pelo recálculo' do
    primeira = mensagem!(conversation, :incoming, content: 'placa ABC1D23')
    segunda = mensagem!(conversation, :incoming, content: 'repetindo, ABC1D23')
    placa = fato!('placa', 'ABC1D23', [primeira, segunda])

    editar(segunda, 'repetindo, XYZ9W87')

    nova = Crm::MemoriaFato.vivos.find_by(chave: 'placa')
    expect(placa.reload.expirado_em).to be_present
    expect(nova).to have_attributes(prova_message_ids: [primeira.id], versao: 2, substitui_id: placa.id, gerado_por: 'codigo:recalculo')
  end

  it 'apagada: o fato que dependia só dela deixa de valer; com outra prova, continua' do
    so_dela = mensagem!(conversation, :incoming, content: 'cep 01310100')
    outra = mensagem!(conversation, :incoming, content: 'placa ABC1D23')
    cep = fato!('cep', '01310100', [so_dela])
    placa = fato!('placa', 'ABC1D23', [so_dela, outra])

    so_dela.update!(content_attributes: { deleted: true })
    Crm::Memoria::MensagemJob.perform_now(so_dela.id, 'apagada')

    expect(cep.reload).to have_attributes(prova_trecho: nil)
    expect(cep.expirado_em).to be_present
    expect(placa.reload.expirado_em).to be_present
    expect(Crm::MemoriaFato.vivos.find_by(chave: 'placa').prova_message_ids).to eq([outra.id])
  end

  it 'apagar as duas provas, uma de cada vez: o fato só deixa de valer quando a última sai' do
    a = mensagem!(conversation, :incoming, content: 'placa ABC1D23')
    b = mensagem!(conversation, :incoming, content: 'de novo ABC1D23')
    fato!('placa', 'ABC1D23', [a, b])

    [a, b].each do |message|
      message.update!(content_attributes: { deleted: true })
      Crm::Memoria::MensagemJob.perform_now(message.id, 'apagada')
    end

    expect(Crm::MemoriaFato.vivos.where(chave: 'placa')).to be_empty
  end

  it 'valor curto se confere por palavra inteira; edição que não mexe em fato não reavalia nada' do
    mensagem = mensagem!(conversation, :incoming, content: 'moro em SP, ano 2002')
    uf = fato!('uf', 'SP', [mensagem])
    ano = fato!('ano', '2002', [mensagem])
    allow(Crm::Ai::Observer).to receive(:new).and_call_original

    editar(mensagem, 'moro em SP, ano 12002')
    expect(uf.reload.expirado_em).to be_nil
    expect(ano.reload.expirado_em).to be_present

    outra = mensagem!(conversation, :incoming, content: 'oi')
    editar(outra, 'oi, tudo bem?')
    expect(Crm::Ai::Observer).to have_received(:new).once
  end

  it 'evento: só a mensagem do cliente com o texto mudado é "editada"; "apagada" só na transição' do
    do_cliente = mensagem!(conversation, :incoming, content: 'a')
    nossa = mensagem!(conversation, :outgoing, content: 'b')

    expect(described_class.evento(do_cliente, 'content' => %w[a c])).to eq('editada')
    expect(described_class.evento(do_cliente, 'status' => %w[sent read])).to be_nil
    expect(described_class.evento(nossa, 'content' => %w[b d])).to be_nil
    expect(described_class.evento(do_cliente, 'content_attributes' => [{}, { 'deleted' => true }])).to eq('apagada')
    expect(described_class.evento(do_cliente, 'content_attributes' => [{ 'deleted' => true }, { 'deleted' => true, 'x' => 1 }])).to be_nil
  end
end
