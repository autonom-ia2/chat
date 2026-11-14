require 'rails_helper'
require Rails.root.join('db/migrate/20261113181000_create_carteira_leituras.rb')

# E6 (#2899): derrubar a tabela dos itens não apaga arquivo. O `down` tira antes os PDFs deles, e só os deles. O índice
# da migration entra CONCURRENTLY, que não roda dentro da transação do teste: o `up` e o `down` inteiros são exercidos
# pelo job "Migrations do lote" da CI, não aqui.
RSpec.describe CreateCarteiraLeituras do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:pdf) { { io: StringIO.new('%PDF-1.4 exemplo'), filename: 'exemplo.pdf', content_type: 'application/pdf' } }

  it 'antes de derrubar a tabela, tira o PDF de cada item e manda apagar o arquivo, sem tocar no PDF da apólice' do
    item = create(:carteira_leitura_item, leitura: create(:carteira_leitura, account: account))
    item.pdf.attach(pdf)
    seguro = create(:carteira_apolice, account: account, contact: contact)
    seguro.pdf.attach(pdf.merge(io: StringIO.new('%PDF-1.4 outro')))
    do_item = item.pdf.blob

    expect { described_class.new.send(:apagar_os_pdfs_dos_itens) }.to have_enqueued_job(ActiveStorage::PurgeJob).with(do_item).exactly(:once)

    expect(ActiveStorage::Attachment.where(record_type: 'Carteira::LeituraItem')).to be_empty
    expect(seguro.reload.pdf).to be_attached
  end
end
