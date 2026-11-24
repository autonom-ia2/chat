require 'rails_helper'

# E7 (#2900) e #3175 — o PDF de cada seguro que a busca no conector trouxe: o PDF puro, o ZIP com um PDF dentro (o portal
# do Agger manda assim parte dos documentos), as recusas com motivo claro, o teto contra bomba de ZIP, a nova tentativa
# depois da espera e o teto de tentativas por seguro. O conector e o download são dublês; o PDF e os ZIPs são fictícios,
# montados aqui mesmo.
RSpec.describe Carteira::Conector::BaixarPdf, :aggregate_failures do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo Um') }
  let(:fim) { 1.year.from_now.to_date }
  let(:seguro) do
    criar_apolice(pessoa, tipo: 'outro', seguradora: 'Seguradora Azul (exemplo)', numero: 'EX-0001', origem: 'conector',
                          origem_ref: 'mock-ref-1', fim_vigencia: fim)
  end
  let(:leitura) { busca }
  let(:portal) { instance_double(Carteira::Conector::Portal, documento: { 'url' => 'https://documentos.exemplo.test/d/1' }) }
  let(:pdf) { "%PDF-1.4\n% apolice de exemplo\n%%EOF\n".b }
  let(:baixado) { [pdf] }
  let(:pendentes) { Carteira::Conector::PdfsPendentes }

  before do
    allow(SafeFetch).to receive(:fetch) do |*_args, **_opcoes, &bloco|
      bloco.call(SafeFetch::Result.new(tempfile: arquivo_com(baixado.first), filename: 'documento.pdf', content_type: 'application/pdf'))
    end
  end

  def busca(**dados)
    create(:carteira_leitura, account: account, origem: 'conector', estado: 'trazida', confirmada_em: Time.current,
                              totais: { 'diaria' => 1 }, **dados)
  end

  def arquivo_com(bytes)
    Tempfile.new(%w[baixado .pdf], binmode: true).tap do |arquivo|
      arquivo.write(bytes)
      arquivo.rewind
    end
  end

  def registro(na: leitura, estado: 'trazido', apolice: seguro, **campos)
    create(:carteira_leitura_item, leitura: na, estado: estado, apolice: apolice,
                                   campos: { 'ref' => 'mock-ref-1', 'pdf_ref' => 'mock-pdf-1', 'seguradora' => 'Seguradora Azul (exemplo)',
                                             'numero' => 'EX-0001', 'fim_vigencia' => fim.iso8601 }.merge(campos))
  end

  def zip(entradas)
    Zip::OutputStream.write_buffer(StringIO.new) do |saida|
      entradas.each do |nome, conteudo|
        saida.put_next_entry(nome)
        saida.write(conteudo)
      end
    end.string
  end

  def baixar(com: leitura)
    described_class.new(com, portal: portal).bloco
  end

  def marcas(item)
    item.reload.campos.slice(pendentes::TENTATIVAS, pendentes::MOTIVO, pendentes::FIM)
  end

  it 'guarda o PDF com nome neutro, sem nome de pessoa no passo, e põe a leitura do PDF na fila' do
    item = registro

    expect { expect(baixar).to eq(:terminou) }.to have_enqueued_job(Carteira::Conector::LerPdfJob).with(seguro.id, leitura.id)

    expect(seguro.reload.pdf).to be_attached
    expect(seguro.pdf.filename.to_s).to eq("apolice-#{seguro.id}.pdf")
    expect(seguro.eventos.sole).to have_attributes(tipo: 'pdf_anexado', user_id: nil, valores: { 'leitura' => leitura.id })
    expect(marcas(item)).to eq(pendentes::TENTATIVAS => 0, pendentes::FIM => 'baixado')
  end

  it 'aceita o ZIP com um PDF dentro: guarda o PDF de dentro, não o ZIP' do
    baixado.replace([zip('leia-me.txt' => 'texto de exemplo', 'documento.pdf' => pdf)])
    registro

    baixar

    expect(seguro.reload.pdf.download).to eq(pdf)
  end

  it 'recusa o ZIP sem PDF e o ZIP com mais de um PDF, com o motivo, e o registro volta depois' do
    { 'zip_sem_pdf' => zip('leia-me.txt' => 'texto de exemplo'),
      'zip_com_varios_pdfs' => zip('um.pdf' => pdf, 'outro.pdf' => pdf) }.each do |motivo, arquivo|
      baixado.replace([arquivo])
      item = registro(na: busca)

      expect { expect(baixar(com: item.leitura)).to eq(:mais_tarde) }.not_to have_enqueued_job(Carteira::Conector::LerPdfJob)

      expect(seguro.reload.pdf).not_to be_attached
      expect(marcas(item)).to eq(pendentes::TENTATIVAS => 1, pendentes::MOTIVO => motivo, pendentes::FIM => nil)
    end
  end

  it 'recusa o arquivo que não é PDF nem ZIP' do
    baixado.replace(['<html>não é PDF</html>'.b])
    item = registro

    baixar

    expect(seguro.reload.pdf).not_to be_attached
    expect(marcas(item)[pendentes::MOTIVO]).to eq('nao_e_pdf')
  end

  it 'recusa o PDF de dentro do ZIP maior que o teto, antes de abrir' do
    stub_const('Carteira::Conector::BaixarPdf::TETO_BYTES', 1.kilobyte)
    baixado.replace([zip('documento.pdf' => pdf + ('0' * 2.kilobytes))])
    item = registro

    baixar

    expect(seguro.reload.pdf).not_to be_attached
    expect(marcas(item)[pendentes::MOTIVO]).to eq('grande_demais')
  end

  it 'para a bomba de ZIP que mente o tamanho: os bytes descompactados também contam' do
    stub_const('Carteira::Conector::BaixarPdf::TETO_BYTES', 1.kilobyte)
    baixado.replace([mentindo_o_tamanho(zip('documento.pdf' => pdf + ('0' * 64.kilobytes)))])
    item = registro

    baixar

    expect(seguro.reload.pdf).not_to be_attached
    expect(marcas(item)[pendentes::MOTIVO]).to eq('grande_demais')
  end

  it 'a falha volta a ser tentada depois da espera, e no teto o registro sai da fila' do
    allow(portal).to receive(:documento).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'fora do ar'))
    item = registro

    expect(baixar).to eq(:mais_tarde)
    expect(baixar).to eq(:mais_tarde)
    expect(portal).to have_received(:documento).once

    travel(pendentes::ESPERA + 1.minute) { expect(baixar).to eq(:mais_tarde) }
    travel(2 * (pendentes::ESPERA + 1.minute)) { expect(baixar).to eq(:terminou) }

    expect(portal).to have_received(:documento).exactly(3).times
    expect(marcas(item)).to eq(pendentes::TENTATIVAS => 3, pendentes::MOTIVO => 'Autonomia::Insurance::Connector::Error',
                               pendentes::FIM => 'desistiu')
  end

  it 'a nova tentativa que dá certo guarda o PDF' do
    respostas = [:falha, { 'url' => 'https://documentos.exemplo.test/d/1' }]
    allow(portal).to receive(:documento) do
      resposta = respostas.shift
      raise Autonomia::Insurance::Connector::Error.new(:unavailable, 'fora do ar') if resposta == :falha

      resposta
    end
    item = registro

    baixar
    travel(pendentes::ESPERA + 1.minute) { expect(baixar).to eq(:terminou) }

    expect(seguro.reload.pdf).to be_attached
    expect(marcas(item)).to include(pendentes::TENTATIVAS => 1, pendentes::FIM => 'baixado')
  end

  it 'o registro `igual` da busca do dia seguinte traz o PDF que falhou antes, até o teto do seguro' do
    registro(na: busca, pendentes::TENTADO => 1.day.ago.iso8601, pendentes::TENTATIVAS => 1, pendentes::FIM => 'desistiu')
    igual = registro(estado: 'igual', apolice: nil)

    baixar

    expect(seguro.reload.pdf).to be_attached
    expect(igual.reload.campos[pendentes::APOLICE]).to eq(seguro.id)
  end

  it 'o teto de tentativas soma as buscas: o seguro que já falhou no teto não é pedido de novo' do
    registro(na: busca, pendentes::TENTADO => 2.days.ago.iso8601, pendentes::TENTATIVAS => 2)
    registro(na: busca, estado: 'igual', apolice: nil, pendentes::TENTADO => 1.day.ago.iso8601, pendentes::TENTATIVAS => 1,
                        pendentes::APOLICE => seguro.id)
    igual = registro(estado: 'igual', apolice: nil)

    expect(baixar).to eq(:terminou)

    expect(portal).not_to have_received(:documento)
    expect(marcas(igual)[pendentes::FIM]).to eq('desistiu')
  end

  it 'o registro `igual` de outro termo (ou sem seguro) não baixa nada' do
    igual = registro(estado: 'igual', apolice: nil, 'fim_vigencia' => (fim + 1.year).iso8601)

    baixar

    expect(portal).not_to have_received(:documento)
    expect(marcas(igual)[pendentes::FIM]).to eq('sem_seguro')
  end

  it 'o seguro que já tem PDF fica com o dele, sem pedir nada ao conector' do
    guardar_pdf_na(seguro)
    item = registro

    baixar

    expect(portal).not_to have_received(:documento)
    expect(marcas(item)[pendentes::FIM]).to eq('ja_tinha')
  end

  it 'a busca que não está trazida não baixa nada' do
    desfazendo = busca(estado: 'desfazendo')
    registro(na: desfazendo)

    expect(baixar(com: desfazendo)).to eq(:terminou)
    expect(portal).not_to have_received(:documento)
  end

  # O tamanho descompactado que o ZIP declara (no diretório central e no cabeçalho da entrada) vira 1 byte.
  def mentindo_o_tamanho(bytes)
    bytes = bytes.b.dup
    central = bytes.index("PK\x01\x02".b)
    bytes[central + 24, 4] = [1].pack('V')
    local = bytes.index("PK\x03\x04".b)
    bytes[local + 22, 4] = [1].pack('V')
    bytes
  end
end
