require 'rails_helper'

# A ENTREGA QUE É UM ARQUIVO (entrega 11 do Agente de Cotação).
#
# O comparativo em PDF chegava ao cliente como LINK num texto; o cliente de WhatsApp espera o
# arquivo na conversa. O que estes exemplos travam é o contrato do objeto que viaja da ferramenta
# ao publicador: a forma (serializável, porque atravessa o Sidekiq), a validação da forma, e o
# DOWNLOAD com as suas três guardas — teto de tamanho, tempo, e "é PDF de verdade" — cada uma
# provada por mutação em 11/09/2026 (ver `docs/audit/2026-09-11-entrega-11-comparativo-arquivo.md`).
RSpec.describe Autonomia::Agents::Tools::EntregaDeArquivo do
  let(:url) { 'https://arquivos.exemplo.test/comparativo-9.pdf' }
  let(:entrega) do
    described_class.new(url: url, nome: 'Comparativo de seguro — placa ABC1D23.pdf',
                        legenda: 'Comparativo com todas as opções.',
                        reserva: "Comparativo com todas as opções:\n#{url}")
  end
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }

  describe '.de' do
    it 'reconhece o proprio objeto e a forma serializada dele, e nada mais' do
      expect(described_class.de(entrega)).to be(entrega)
      expect(described_class.de(entrega.to_h)).to have_attributes(url: url, nome: entrega.nome,
                                                                  legenda: entrega.legenda, reserva: entrega.reserva)
      expect(described_class.de('texto comum')).to be_nil
      expect(described_class.de({ 'outra' => 'coisa' })).to be_nil
      expect(described_class.de(nil)).to be_nil
    end

    it 'recusa a forma sem os quatro campos, sem https, ou com nome que nao e de PDF' do
      base = entrega.to_h[described_class::CHAVE]

      expect(described_class.de(described_class::CHAVE => base.except('nome'))).to be_nil
      expect(described_class.de(described_class::CHAVE => base.merge('url' => 'http://inseguro.test/x.pdf'))).to be_nil
      expect(described_class.de(described_class::CHAVE => base.merge('url' => 'ftp://x.test/x.pdf'))).to be_nil
      expect(described_class.de(described_class::CHAVE => base.merge('nome' => 'comparativo.exe'))).to be_nil
      expect(described_class.de(described_class::CHAVE => base.merge('nome' => '../fora.pdf'))).to be_nil
      expect(described_class.de(described_class::CHAVE => base.merge('reserva' => ' '))).to be_nil
    end
  end

  # O DEFEITO DA FORMA tem nome curto, para o log de quem cai para o link (a ferramenta) ou descarta
  # (o publicador) dizer O QUE reprovou — sem a URL nem o texto, que são dados de fora.
  describe '#defeito' do
    it 'e nil na forma valida, e o campo que reprovou nas outras' do
      expect(entrega.defeito).to be_nil
      expect(described_class.new(url: 'http://inseguro.test/x.pdf', nome: entrega.nome, legenda: entrega.legenda,
                                 reserva: entrega.reserva).defeito).to eq('url')
      expect(described_class.new(url: url, nome: 'comparativo.exe', legenda: entrega.legenda,
                                 reserva: entrega.reserva).defeito).to eq('nome')
      expect(described_class.new(url: url, nome: entrega.nome, legenda: ' ', reserva: entrega.reserva).defeito).to eq('legenda')
      expect(described_class.new(url: url, nome: entrega.nome, legenda: entrega.legenda, reserva: nil).defeito).to eq('reserva')
    end
  end

  it 'serializa com chaves de texto, porque atravessa os argumentos de um job' do
    expect(entrega.to_h).to eq(described_class::CHAVE => { 'url' => url, 'nome' => entrega.nome,
                                                           'legenda' => entrega.legenda, 'reserva' => entrega.reserva })
    expect(ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize([entrega.to_h])).first).to eq(entrega.to_h)
  end

  it 'tem identidade pela URL, para a publicacao ser idempotente como arquivo e como link' do
    expect(entrega.identidade).to eq("arquivo:#{url}")
  end

  describe '#baixar' do
    it 'devolve o PDF como arquivo enviado, com o nome que vai ao cliente' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

      # Act
      arquivo = entrega.baixar

      # Assert
      expect(arquivo).to be_a(ActionDispatch::Http::UploadedFile)
      expect(arquivo.original_filename).to eq('Comparativo de seguro — placa ABC1D23.pdf')
      expect(arquivo.content_type).to eq('application/pdf')
      expect(arquivo.read).to eq(pdf)
    end

    # O blob do portal do AGGER responde `application/octet-stream`: o que decide é a assinatura
    # dos bytes, e o tipo declarado só precisa não desmentir.
    it 'aceita o tipo generico de bytes quando os bytes sao de PDF' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/octet-stream' })

      expect(entrega.baixar.content_type).to eq('application/pdf')
    end

    it 'recusa o que nao e PDF, mesmo com o tipo certo no cabecalho' do
      stub_request(:get, url).to_return(status: 200, body: '<html>não achei</html>', headers: { 'Content-Type' => 'application/pdf' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('nao_e_pdf') }
    end

    it 'recusa o tipo que desmente o PDF, mesmo com os bytes certos' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'text/html' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('tipo_text_html') }
    end

    # O 404 real de 11/09/2026: o portal devolve a URL do comparativo e o blob não existe
    # (`BlobNotFound`, XML). Sem esta guarda o cliente receberia um "PDF" de 215 bytes de XML.
    it 'recusa a URL que nao responde o arquivo' do
      stub_request(:get, url).to_return(status: 404, body: '<?xml version="1.0"?><Error><Code>BlobNotFound</Code></Error>',
                                        headers: { 'Content-Type' => 'application/xml' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('http_404') }
    end

    it 'recusa o arquivo maior que o teto ANTES de baixar, pelo tamanho anunciado' do
      stub_request(:get, url).to_return(status: 200, body: pdf,
                                        headers: { 'Content-Type' => 'application/pdf',
                                                   'Content-Length' => (described_class::TETO_BYTES + 1).to_s })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('tamanho') }
    end

    it 'recusa o arquivo maior que o teto DURANTE o download, quando o tamanho nao foi anunciado' do
      grande = pdf + ('x' * described_class::TETO_BYTES)
      stub_request(:get, url).to_return(status: 200, body: grande, headers: { 'Content-Type' => 'application/pdf' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('tamanho') }
    end

    it 'recusa quando a rede nao responde no tempo' do
      stub_request(:get, url).to_timeout

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('tempo') }
    end

    it 'baixa com teto de tempo de conexao e de leitura, nao com o padrao de 30 s do Down' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Down).to receive(:download).and_call_original

      entrega.baixar

      tetos = { max_size: described_class::TETO_BYTES, open_timeout: described_class::ABERTURA_SEGUNDOS,
                read_timeout: described_class::LEITURA_SEGUNDOS }
      expect(Down).to have_received(:download).with(url, hash_including(tetos))
    end
  end
end
