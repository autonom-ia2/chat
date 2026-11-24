require 'rails_helper'

# #3175 — a rotina de todo dia põe na fila a leitura do PDF do Agger que está guardado e nunca foi lido, ligada à busca
# que o anexou; o que já foi lido, o que não tem nada vazio, o cancelado, o que não veio do conector e a conta sem a
# leitura liberada ficam de fora. Nada é lido aqui: só a fila.
RSpec.describe Carteira::Conector::PdfsSemLeituraJob, :aggregate_failures do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo Dois') }
  let(:leitura) { create(:carteira_leitura, account: account, origem: 'conector', estado: 'trazida') }

  before { Carteira::Leitor::Liberado.ligar!(account) }

  def seguro_com_pdf(numero, origem: 'conector', **dados)
    criar_apolice(pessoa, tipo: 'outro', seguradora: 'Seguradora Exemplo', numero: numero, origem: origem, **dados).tap do |seguro|
      guardar_pdf_na(seguro)
      seguro.eventos.create!(tipo: 'pdf_anexado', quando: 1.minute.ago, valores: { leitura: leitura.id })
    end
  end

  it 'põe na fila só o PDF guardado que ainda vale ler, com a busca que o anexou' do
    sem_leitura = seguro_com_pdf('EX-1')
    lido = seguro_com_pdf('EX-2')
    lido.eventos.create!(tipo: 'pdf_lido', quando: Time.current, valores: { lido: true })
    seguro_com_pdf('EX-3', cancelado_em: Time.current)
    seguro_com_pdf('EX-4', origem: 'planilha')
    criar_apolice(pessoa, tipo: 'outro', seguradora: 'Seguradora Exemplo', numero: 'EX-5', origem: 'conector')

    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Conector::LerPdfJob).exactly(:once)
    expect(Carteira::Conector::LerPdfJob).to have_been_enqueued.with(sem_leitura.id, leitura.id)
  end

  it 'o PDF anexado de novo depois da leitura volta a valer' do
    seguro = seguro_com_pdf('EX-6')
    seguro.eventos.create!(tipo: 'pdf_lido', quando: 2.minutes.ago, valores: { lido: true })
    seguro.eventos.create!(tipo: 'pdf_anexado', quando: Time.current, valores: {})

    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Conector::LerPdfJob).with(seguro.id, nil)
  end

  it 'conta sem a leitura liberada não entra na fila' do
    seguro_com_pdf('EX-7')
    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Conector::LerPdfJob).exactly(:once)

    Carteira::Leitor::Liberado.desligar!(account)

    expect { described_class.perform_now }.not_to have_enqueued_job(Carteira::Conector::LerPdfJob)
  end

  it 'o seguro sem nada vazio não entra na fila' do
    vazio = seguro_com_pdf('EX-8')
    # Os campos que a leitura completa foram decididos à mão (contam como preenchidos) e o ramo veio escrito.
    cheio = seguro_com_pdf('EX-9', ramo_original: '0531 - Automóvel', corrigido_a_mao: Carteira::Conector::LerPdf::CAMPOS)

    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Conector::LerPdfJob).exactly(:once)
    expect(Carteira::Conector::LerPdfJob).to have_been_enqueued.with(vazio.id, leitura.id)
    expect(Carteira::Conector::LerPdfJob).not_to have_been_enqueued.with(cheio.id, anything)
  end

  it 'o PDF que só a cotação leu volta a ser lido, para completar o resto' do
    seguro = seguro_com_pdf('EX-10')
    seguro.eventos.create!(tipo: Carteira::Cotacao::DadosDoPdf::PASSO, quando: Time.current, valores: {})

    expect { described_class.perform_now }.to have_enqueued_job(Carteira::Conector::LerPdfJob).with(seguro.id, leitura.id)
  end
end
