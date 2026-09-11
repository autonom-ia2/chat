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

  # O QUE SAI DO DOWNLOAD é o `Tempfile` conferido; o que vai ao publicador é o BLOB já gravado
  # (`#gravar`). O tempfile é fechado nos dois destinos — gravado ou recusado —, porque quem baixa
  # até 10 MB por comparativo no worker não pode deixar isso em disco até o GC.
  describe '#baixar' do
    it 'devolve o PDF baixado, aberto e rebobinado' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

      # Act
      arquivo = entrega.baixar

      # Assert
      expect(arquivo).to be_a(Tempfile)
      expect(arquivo.read).to eq(pdf)
      arquivo.close!
    end

    # O blob do portal do AGGER responde `application/octet-stream`: o que decide é a assinatura
    # dos bytes, e o tipo declarado só precisa não desmentir.
    it 'aceita o tipo generico de bytes quando os bytes sao de PDF' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/octet-stream' })

      arquivo = entrega.baixar

      expect(arquivo.read).to eq(pdf)
      arquivo.close!
    end

    it 'recusa o que nao e PDF, mesmo com o tipo certo no cabecalho' do
      stub_request(:get, url).to_return(status: 200, body: '<html>não achei</html>', headers: { 'Content-Type' => 'application/pdf' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('nao_e_pdf') }
    end

    it 'recusa o tipo que desmente o PDF, mesmo com os bytes certos' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'text/html' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('tipo_text_html') }
    end

    # O 404 do armazenamento do portal (Azure Blob) vem como XML de `BlobNotFound`. Sem esta
    # guarda o cliente receberia um "PDF" de 215 bytes de XML.
    it 'recusa a URL que nao responde o arquivo' do
      stub_request(:get, url).to_return(status: 404, body: '<?xml version="1.0"?><Error><Code>BlobNotFound</Code></Error>',
                                        headers: { 'Content-Type' => 'application/xml' })

      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('http_404') }
    end

    # "Só https" valeria só para o primeiro salto: um 302 para http levaria o download ao transporte
    # sem proteção que a forma recusou. O blob do portal é servido direto, então NENHUM
    # redirecionamento é seguido (rodada 3, 11/09/2026).
    it 'recusa o redirecionamento, sem seguir para onde ele aponta' do
      # Arrange
      destino = 'http://inseguro.test/comparativo-9.pdf'
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => destino })
      stub_request(:get, destino).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

      # Act / Assert
      expect { entrega.baixar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('redirecionamento') }
      expect(a_request(:get, destino)).not_to have_been_made
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

    it 'baixa com teto de tempo, de tamanho e sem redirecionamento, nao com os padroes do Down' do
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Down).to receive(:download).and_call_original

      entrega.baixar.close!

      tetos = { max_size: described_class::TETO_BYTES, open_timeout: described_class::ABERTURA_SEGUNDOS,
                read_timeout: described_class::LEITURA_SEGUNDOS, max_redirects: 0 }
      expect(Down).to have_received(:download).with(url, hash_including(tetos))
    end

    # O tempfile recusado não tem quem o feche: `baixar` não o devolve. Sem isto, cada comparativo
    # recusado deixava até 10 MB em disco no worker até o GC (rodada 3, 11/09/2026).
    it 'fecha e apaga o arquivo temporario quando recusa o que baixou' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: '<html>não achei</html>', headers: { 'Content-Type' => 'application/pdf' })
      baixado = nil
      allow(Down).to receive(:download).and_wrap_original do |original, *args, **opcoes|
        baixado = original.call(*args, **opcoes)
      end

      # Act
      expect { entrega.baixar }.to raise_error(described_class::Indisponivel)

      # Assert
      expect(baixado).to be_a(Tempfile)
      expect(baixado.path).to be_nil
    end
  end

  # O ARQUIVO É GRAVADO NO ARMAZENAMENTO ANTES DE EXISTIR MENSAGEM: o ActiveStorage subiria o
  # arquivo só no `after_commit` da mensagem, e uma subida que falhasse ali deixaria a legenda no ar
  # com um anexo sem bytes e o token já publicado (rodada 3, 11/09/2026). Gravando aqui, a falha do
  # armazenamento é `Indisponivel` como a do download, e o publicador cai para a mesma reserva.
  describe '#gravar' do
    it 'devolve o blob gravado, com o nome que vai ao cliente, o tipo e os bytes do PDF' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/octet-stream' })

      # Act
      blob = entrega.gravar

      # Assert
      expect(blob).to be_persisted
      expect(blob.filename.to_s).to eq('Comparativo de seguro — placa ABC1D23.pdf')
      expect(blob.content_type).to eq('application/pdf')
      expect(blob.download).to eq(pdf)
      expect(ActiveStorage::Blob.find_signed!(blob.signed_id)).to eq(blob)
    end

    it 'fecha e apaga o arquivo temporario depois de gravar' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      baixado = nil
      allow(Down).to receive(:download).and_wrap_original do |original, *args, **opcoes|
        baixado = original.call(*args, **opcoes)
      end

      # Act
      entrega.gravar

      # Assert
      expect(baixado).to be_a(Tempfile)
      expect(baixado.path).to be_nil
    end

    it 'recusa com o motivo do armazenamento e a classe da causa quando a subida falha, sem deixar blob sem arquivo' do
      # Arrange — o serviço de armazenamento indisponível (S3/IAM fora), depois de um download bom
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)
      blobs_antes = ActiveStorage::Blob.count

      # Act / Assert
      expect { entrega.gravar }.to raise_error(described_class::Indisponivel) do |e|
        expect(e.motivo).to eq('armazenamento')
        expect(e.causa).to eq('Errno::ECONNREFUSED')
      end
      expect(ActiveStorage::Blob.count).to eq(blobs_antes)
    end

    it 'fecha e apaga o arquivo temporario tambem quando a subida falha' do
      # Arrange
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)
      baixado = nil
      allow(Down).to receive(:download).and_wrap_original do |original, *args, **opcoes|
        baixado = original.call(*args, **opcoes)
      end

      # Act
      expect { entrega.gravar }.to raise_error(described_class::Indisponivel)

      # Assert
      expect(baixado.path).to be_nil
    end

    it 'nao grava nada quando o download ja recusou' do
      stub_request(:get, url).to_return(status: 404, body: 'x')
      blobs_antes = ActiveStorage::Blob.count

      expect { entrega.gravar }.to raise_error(described_class::Indisponivel) { |e| expect(e.motivo).to eq('http_404') }
      expect(ActiveStorage::Blob.count).to eq(blobs_antes)
    end
  end
end
