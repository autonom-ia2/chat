require 'rails_helper'

# A ENTREGA QUE É UM ARQUIVO (entrega 11 do Agente de Cotação).
#
# O comparativo em PDF chegava ao cliente como LINK num texto; o cliente de WhatsApp espera o
# arquivo na conversa. O que estes exemplos travam é o contrato do objeto que viaja da ferramenta
# ao publicador: a forma (serializável, porque atravessa o Sidekiq), a validação da forma, e o
# DOWNLOAD com as suas guardas — o endereço efetivamente conectado (nada de rede privada), o status
# lido antes do corpo, teto de tamanho, prazo do corpo com teto por leitura e "é PDF de verdade" — cada uma provada por
# mutação em 11/09/2026 (ver `docs/audit/2026-09-11-entrega-11-comparativo-arquivo.md`).
RSpec.describe Autonomia::Agents::Tools::EntregaDeArquivo do
  let(:url) { 'https://arquivos.exemplo.test/comparativo-9.pdf' }
  let(:entrega) do
    described_class.new(url: url, nome: 'Comparativo de seguro, placa ABC1D23.pdf',
                        legenda: 'Comparativo com todas as opções.',
                        reserva: "Comparativo com todas as opções:\n#{url}")
  end
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }
  let(:cabecalho_pdf) { { 'Content-Type' => 'application/pdf' } }

  # O `SafeFetch` resolve o nome ANTES de conectar (é assim que ele confere o endereço): o host de
  # teste ganha um endereço público, e o WebMock responde a chamada.
  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('arquivos.exemplo.test').and_return(['93.184.216.34'])
  end

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

  # O QUE SAI É O BLOB já gravado no armazenamento (`#gravar`): o download e a gravação acontecem
  # ANTES de existir mensagem, para a falha de qualquer um dos dois cair na mesma reserva (o link).
  describe '#gravar' do
    def recusa(motivo, causa: nil)
      raise_error(described_class::Indisponivel) do |e|
        expect(e.motivo).to eq(motivo)
        expect(e.causa).to eq(causa) if causa
      end
    end

    describe 'o download' do
      it 'grava o PDF baixado, com o nome que vai ao cliente, o tipo e os bytes' do
        # Arrange
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)

        # Act
        blob = entrega.gravar(run_id: 42)

        # Assert
        expect(blob).to be_persisted
        expect(blob.filename.to_s).to eq('Comparativo de seguro, placa ABC1D23.pdf')
        expect(blob.content_type).to eq('application/pdf')
        expect(blob.download).to eq(pdf)
        expect(ActiveStorage::Blob.find_signed!(blob.signed_id)).to eq(blob)
        # A MARCA da execução e da finalidade (rodada 7): é por ela que o varredor reconhece o blob que
        # ficou sem dono (o processo morreu entre a linha e o anexo) e o apaga — sem tocar em nenhum outro.
        expect(blob.metadata).to include('autonomia_tool_run_id' => 42, 'autonomia_finalidade' => 'entrega_de_arquivo')
      end

      # O blob do portal do AGGER responde `application/octet-stream`: o que decide é a assinatura
      # dos bytes, e o tipo declarado só precisa não desmentir.
      it 'aceita o tipo generico de bytes quando os bytes sao de PDF' do
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/octet-stream' })

        expect(entrega.gravar(run_id: 42).download).to eq(pdf)
      end

      it 'recusa o que nao e PDF, mesmo com o tipo certo no cabecalho' do
        stub_request(:get, url).to_return(status: 200, body: '<html>não achei</html>', headers: cabecalho_pdf)

        expect { entrega.gravar(run_id: 42) }.to recusa('nao_e_pdf')
        expect(ActiveStorage::Blob.count).to eq(0)
      end

      # O motivo é FECHADO: o valor do cabeçalho é do servidor e não entra no código que vai ao log
      # (rodada 6, 11/09/2026 — antes saía `tipo_text_html`).
      it 'recusa o tipo que desmente o PDF, com motivo fechado e sem o cabecalho dentro dele' do
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'text/html; charset=utf-8' })

        expect { entrega.gravar(run_id: 42) }.to raise_error(described_class::Indisponivel) do |e|
          expect(e.motivo).to eq('tipo_invalido')
          expect(e.message).not_to include('html', 'charset')
        end
      end

      # O 404 do armazenamento do portal (Azure Blob) vem como XML de `BlobNotFound`. Sem esta
      # guarda o cliente receberia um "PDF" de 215 bytes de XML. Só o INTEIRO do status vai ao motivo.
      it 'recusa a URL que nao responde o arquivo, pelo status' do
        stub_request(:get, url).to_return(status: [404, 'Not Found (blob nao existe)'],
                                          body: '<?xml version="1.0"?><Error><Code>BlobNotFound</Code></Error>',
                                          headers: { 'Content-Type' => 'application/xml' })

        expect { entrega.gravar(run_id: 42) }.to raise_error(described_class::Indisponivel) do |e|
          expect(e.motivo).to eq('http_404')
          expect(e.message).not_to include('blob')
        end
      end

      # "Só https" valeria só para o primeiro salto: um 302 para http levaria o download ao transporte
      # sem proteção que a forma recusou. O blob do portal é servido direto, então NENHUM
      # redirecionamento é seguido (rodada 3, 11/09/2026) — nem para um destino que resolveria.
      it 'recusa o redirecionamento, sem seguir para onde ele aponta' do
        # Arrange
        destino = 'http://inseguro.test/comparativo-9.pdf'
        allow(Resolv).to receive(:getaddresses).with('inseguro.test').and_return(['93.184.216.34'])
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => destino })
        stub_request(:get, destino).to_return(status: 200, body: pdf, headers: cabecalho_pdf)

        # Act / Assert
        expect { entrega.gravar(run_id: 42) }.to recusa('redirecionamento')
        expect(a_request(:get, destino)).not_to have_been_made
      end

      it 'recusa o arquivo maior que o teto ANTES de baixar, pelo tamanho anunciado' do
        stub_request(:get, url).to_return(status: 200, body: pdf,
                                          headers: cabecalho_pdf.merge('Content-Length' => (described_class::TETO_BYTES + 1).to_s))

        expect { entrega.gravar(run_id: 42) }.to recusa('tamanho')
      end

      it 'recusa o arquivo maior que o teto DURANTE o download, quando o tamanho nao foi anunciado' do
        grande = pdf + ('x' * described_class::TETO_BYTES)
        stub_request(:get, url).to_return(status: 200, body: grande, headers: cabecalho_pdf)

        expect { entrega.gravar(run_id: 42) }.to recusa('tamanho')
      end

      it 'recusa quando a conexao nao responde no tempo' do
        stub_request(:get, url).to_timeout

        expect { entrega.gravar(run_id: 42) }.to recusa('tempo')
      end

      # O `SafeFetch` embrulha a rede caída num `FetchError`; o que separa "tempo" de "rede" é a
      # CLASSE da causa, nunca a mensagem — e é a classe que vai ao log.
      it 'recusa com motivo `download` e a classe da causa quando a rede cai' do
        stub_request(:get, url).to_raise(Errno::ECONNREFUSED)

        expect { entrega.gravar(run_id: 42) }.to recusa('download', causa: 'Errno::ECONNREFUSED')
      end

      # O contrato deste método é "levanta `Indisponivel` em qualquer falha": uma resposta HTTP
      # malformada (`Net::HTTPBadResponse`) não é classificada por ninguém no caminho e sobe crua —
      # sem esta guarda saía do publicador como `blocked`, nem arquivo nem link (rodada 5).
      it 'recusa com motivo `download` e a classe da causa quando a camada HTTP levanta o que ninguem classifica' do
        stub_request(:get, url).to_raise(Net::HTTPBadResponse)

        expect { entrega.gravar(run_id: 42) }.to recusa('download', causa: 'Net::HTTPBadResponse')
      end

      it 'baixa pelo SafeFetch com os tetos, o prazo e zero redirecionamentos, nao com os padroes dele' do
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)
        allow(SafeFetch).to receive(:fetch).and_call_original

        entrega.gravar(run_id: 42)

        tetos = { max_bytes: described_class::TETO_BYTES, open_timeout: described_class::ABERTURA_SEGUNDOS,
                  total_timeout: described_class::PRAZO_SEGUNDOS, max_redirects: 0 }
        expect(SafeFetch).to have_received(:fetch).with(url, hash_including(tetos))
      end

      # O ENDEREÇO EFETIVAMENTE CONECTADO é conferido (ssrf_filter): a forma só exige https, e um
      # https para dentro da nossa rede — direto, em IPv6, ou por um nome que resolve para lá — é o
      # worker sendo usado para ler o que não deve (rodada 6, 11/09/2026). Nada é pedido ao destino.
      describe 'o endereco' do
        it 'recusa o IPv4 privado' do
          privada = described_class.new(url: 'https://10.0.0.7/comparativo-9.pdf', nome: entrega.nome,
                                        legenda: entrega.legenda, reserva: entrega.reserva)
          stub_request(:get, privada.url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)

          expect { privada.gravar(run_id: 42) }.to recusa('url_insegura')
          expect(a_request(:get, privada.url)).not_to have_been_made
        end

        it 'recusa o IPv6 privado' do
          privada = described_class.new(url: 'https://[fd00::1]/comparativo-9.pdf', nome: entrega.nome,
                                        legenda: entrega.legenda, reserva: entrega.reserva)
          stub_request(:get, privada.url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)

          expect { privada.gravar(run_id: 42) }.to recusa('url_insegura')
          expect(a_request(:get, privada.url)).not_to have_been_made
        end

        it 'recusa o nome que resolve para um endereco privado' do
          allow(Resolv).to receive(:getaddresses).with('arquivos.exemplo.test').and_return(['10.0.0.7'])
          stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)

          expect { entrega.gravar(run_id: 42) }.to recusa('url_insegura')
          expect(a_request(:get, url)).not_to have_been_made
        end
      end
    end

    # O QUE O WEBMOCK NÃO EMULA: o socket. Um servidor real em 127.0.0.1 (a forma exige https, mas
    # `gravar` não a confere — o que se prova aqui é o download; `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`
    # deixa o SafeFetch falar com a máquina local, pelo mesmo `Fetcher`), com o WebMock desligado.
    describe 'o corpo e o tempo, no socket' do
      let(:local) do
        described_class.new(url: servidor.url('/comparativo-9.pdf'), nome: entrega.nome, legenda: entrega.legenda, reserva: entrega.reserva)
      end

      after { servidor.parar }

      def na_rede_local(&)
        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') { sem_webmock(&) }
      end

      # O status é lido ANTES do corpo: o Net::HTTP leria o corpo inteiro em memória depois do bloco
      # (`reading_body`), e um 404 de 32 MB seria materializado só para ser recusado (rodada 6).
      describe 'a resposta que nao e 200 com um corpo enorme' do
        let(:total) { 32.megabytes }
        let(:servidor) do
          servidor_http_local do |s, cliente|
            s.escrever(cliente, s.cabecalhos(404, 'application/xml', total))
            loop { break if s.bytes_escritos >= total || !s.escrever(cliente, 'x' * 65_536) }
          end
        end

        it 'e recusada pelo status, e a conexao e fechada sem materializar o corpo' do
          na_rede_local { expect { local.gravar(run_id: 42) }.to recusa('http_404') }
          servidor.parar

          expect(servidor.bytes_escritos).to be < total
        end
      end

      # O PRAZO DO CORPO É MONOTÔNICO, com teto por leitura: um servidor que entrega pedaços com pausas
      # crescentes nunca estoura um teto por leitura sozinho, e seguraria o worker além dos 25 s de
      # shutdown do Sidekiq. Cada leitura espera só o que resta do prazo: a recusa vem ao vencer (1 s),
      # não no pedaço seguinte (2,1 s). O que o prazo NÃO cobre (DNS, cabeçalhos que gotejam abaixo do
      # saldo) está registrado em `EntregaDeArquivo::PRAZO_SEGUNDOS` (rodada 7).
      describe 'a resposta que chega devagar demais' do
        let(:servidor) do
          servidor_http_local do |s, cliente|
            s.escrever(cliente, "#{s.cabecalhos(200, 'application/pdf', 40)}%PDF-1.4\nx")
            [0.3, 0.6, 1.2].each do |pausa|
              sleep(pausa)
              break unless s.escrever(cliente, 'x' * 10)
            end
          end
        end

        it 'e recusada por tempo ao vencer o prazo, esperando em cada leitura so o que resta' do
          stub_const("#{described_class}::PRAZO_SEGUNDOS", 1)
          inicio = segundos_monotonicos

          na_rede_local { expect { local.gravar(run_id: 42) }.to recusa('tempo') }

          expect(segundos_monotonicos - inicio).to be < 1.6
          expect(ActiveStorage::Blob.count).to eq(0)
        end
      end
    end

    # O ARQUIVO É GRAVADO ANTES DE EXISTIR MENSAGEM, em DUAS FASES: a linha do blob na transação
    # curta dela, e a subida ao armazenamento FORA de transação (rodada 6, 11/09/2026 — a transação em
    # volta de `create_and_upload!` segurava a conexão do banco durante a subida ao S3). A subida que
    # falha é `Indisponivel` como a do download, e a linha sem arquivo vai para a limpeza.
    describe 'a gravacao' do
      it 'sobe o arquivo fora de transacao' do
        # Arrange
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)
        abertas_na_subida = nil
        allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |original, *args, **opcoes|
          abertas_na_subida = ActiveRecord::Base.connection.open_transactions
          original.call(*args, **opcoes)
        end
        abertas_antes = ActiveRecord::Base.connection.open_transactions

        # Act
        blob = entrega.gravar(run_id: 42)

        # Assert — nenhuma transação além das que o exemplo já tinha (a do fixture)
        expect(blob).to be_persisted
        expect(abertas_na_subida).to eq(abertas_antes)
      end

      it 'recusa com o motivo do armazenamento e a classe da causa quando a subida falha, e manda a linha sem arquivo para a limpeza' do
        # Arrange — o serviço de armazenamento indisponível (S3/IAM fora), depois de um download bom
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)
        allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)

        # Act / Assert
        expect { entrega.gravar(run_id: 42) }.to recusa('armazenamento', causa: 'Errno::ECONNREFUSED')
        expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
        perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
        expect(ActiveStorage::Blob.count).to eq(0)
      end

      # A limpeza é CORTESIA (rodadas 4 e 5): o Redis fora no agendamento não pode trocar o motivo
      # da recusa, que é o do armazenamento — fica registrado, com o id do blob.
      it 'mantem o motivo do armazenamento quando a fila nao aceita a limpeza da linha sem arquivo' do
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: cabecalho_pdf)
        allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)
        allow(ActiveStorage::PurgeJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
        allow(Rails.logger).to receive(:warn).and_call_original

        expect { entrega.gravar(run_id: 42) }.to recusa('armazenamento', causa: 'Errno::ECONNREFUSED')
        expect(Rails.logger).to have_received(:warn)
          .with(a_string_matching(/blob sem dono nao agendado gravacao blob=\d+ causa=Redis::CannotConnectError/))
      end

      it 'nao grava nada quando o download ja recusou' do
        stub_request(:get, url).to_return(status: 404, body: 'x')

        expect { entrega.gravar(run_id: 42) }.to recusa('http_404')
        expect(ActiveStorage::Blob.count).to eq(0)
        expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
      end

      # O temporário do download é do `SafeFetch` e não sobrevive ao bloco — gravado ou recusado.
      # Sem isto, cada comparativo deixava até 10 MB em disco no worker até o GC.
      it 'nao deixa o arquivo temporario do download em disco, gravado ou recusado' do
        # Arrange
        temporarios = []
        allow(Tempfile).to receive(:new).and_wrap_original do |original, *args, **opcoes|
          original.call(*args, **opcoes).tap { |arquivo| temporarios << arquivo if args.first == 'chatwoot-safe-fetch' }
        end
        stub_request(:get, url).to_return({ status: 200, body: pdf, headers: cabecalho_pdf },
                                          { status: 200, body: '<html>não achei</html>', headers: cabecalho_pdf })

        # Act
        entrega.gravar(run_id: 42)
        expect { entrega.gravar(run_id: 42) }.to recusa('nao_e_pdf')

        # Assert
        expect(temporarios.size).to eq(2)
        expect(temporarios.map(&:path)).to all(be_nil)
      end
    end
  end
end
