require 'rails_helper'

# `SafeFetch.fetch` is a custom method that requires a block (it yields a Result);
# it is NOT `Hash#fetch`, so RuboCop's autocorrect to `fetch(url, nil)` would break the API.
# rubocop:disable Style/RedundantFetchBlock
RSpec.describe SafeFetch do
  let(:url) { 'http://example.com/image.png' }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  describe '.fetch' do
    context 'with a valid public URL serving an image' do
      before do
        stub_request(:get, url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )
      end

      it 'yields a Result with tempfile, filename, and content_type' do
        described_class.fetch(url) do |result|
          expect(result.tempfile).to be_a(Tempfile)
          expect(result.filename).to eq('image.png')
          expect(result.content_type).to eq('image/png')
          expect(result.tempfile.size).to be > 0
        end
      end

      it 'closes the tempfile after the block returns' do
        captured = nil
        described_class.fetch(url) { |result| captured = result.tempfile }
        expect(captured.closed?).to be true
      end

      it 'closes the tempfile even when the block raises' do
        captured = nil
        expect do
          described_class.fetch(url) do |result|
            captured = result.tempfile
            raise 'boom'
          end
        end.to raise_error('boom')
        expect(captured.closed?).to be true
      end

      it 'defaults the filename to a unique "download-<timestamp>-<hex>" when the URL has no path' do
        bare_url = 'http://example.com'
        stub_request(:get, bare_url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

        described_class.fetch(bare_url) do |result|
          expect(result.filename).to match(/\Adownload-\d+-[a-f0-9]{8}\z/)
        end
      end

      it 'requires a block' do
        expect { described_class.fetch(url) }.to raise_error(ArgumentError, /block required/)
      end
    end

    context 'with embedded basic auth credentials' do
      it 'passes decoded credentials to the request' do
        authenticated_url = 'http://user+avatar%40example.com:p%40ss+word%3A1@example.com/image.png'
        stub_request(:get, url)
          .with(headers: { 'Authorization' => 'Basic dXNlcithdmF0YXJAZXhhbXBsZS5jb206cEBzcyt3b3JkOjE=' })
          .to_return(
            status: 200,
            body: File.new(Rails.root.join('spec/assets/avatar.png')),
            headers: { 'Content-Type' => 'image/png' }
          )

        described_class.fetch(authenticated_url) do |result|
          expect(result.content_type).to eq('image/png')
        end
      end

      it 'preserves embedded credentials after a same-origin redirect removes userinfo' do
        authenticated_url = 'http://user:pass@example.com/protected.png'
        initial_url = 'http://example.com/protected.png'
        redirect_url = 'http://example.com/public.png'
        redirected_headers = nil

        stub_request(:get, initial_url)
          .with(headers: { 'Authorization' => 'Basic dXNlcjpwYXNz' })
          .to_return(
            status: 302,
            headers: { 'Location' => '/public.png' }
          )
        stub_request(:get, redirect_url)
          .with do |request|
            redirected_headers = request.headers.transform_keys(&:downcase)
            true
          end
          .to_return(
            status: 200,
            body: File.new(Rails.root.join('spec/assets/avatar.png')),
            headers: { 'Content-Type' => 'image/png' }
          )

        described_class.fetch(authenticated_url) do |result|
          expect(result.content_type).to eq('image/png')
        end

        expect(redirected_headers).to include('authorization' => 'Basic dXNlcjpwYXNz')
      end

      it 'strips embedded credentials on cross-origin redirects' do
        authenticated_url = 'http://user:pass@example.com/protected.png'
        initial_url = 'http://example.com/protected.png'
        redirect_url = 'https://example.com/public.png'
        redirected_headers = nil

        stub_request(:get, initial_url)
          .with(headers: { 'Authorization' => 'Basic dXNlcjpwYXNz' })
          .to_return(
            status: 302,
            headers: { 'Location' => redirect_url }
          )
        stub_request(:get, redirect_url)
          .with do |request|
            redirected_headers = request.headers.transform_keys(&:downcase)
            true
          end
          .to_return(
            status: 200,
            body: File.new(Rails.root.join('spec/assets/avatar.png')),
            headers: { 'Content-Type' => 'image/png' }
          )

        described_class.fetch(authenticated_url) do |result|
          expect(result.content_type).to eq('image/png')
        end

        expect(redirected_headers).not_to include('authorization')
      end
    end

    context 'with URL validation' do
      it 'raises InvalidUrlError for javascript: URLs' do
        expect { described_class.fetch('javascript:alert(1)') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end

      it 'raises InvalidUrlError for mailto: URLs' do
        expect { described_class.fetch('mailto:test@example.com') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end

      it 'raises InvalidUrlError for data: URLs' do
        expect { described_class.fetch('data:text/html,<x>') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end

      it 'raises InvalidUrlError for ftp: URLs' do
        expect { described_class.fetch('ftp://example.com/file') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end

      it 'raises InvalidUrlError for malformed URLs' do
        expect { described_class.fetch('not_a_url') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end

      it 'raises InvalidUrlError when host is missing' do
        expect { described_class.fetch('http:///path') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::InvalidUrlError')
        end
      end
    end

    context 'with SSRF protection (integration with ssrf_filter)' do
      it 'raises UnsafeUrlError for private IP literals (10.x.x.x)' do
        expect { described_class.fetch('http://10.0.0.1/secret') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsafeUrlError')
        end
      end

      it 'raises UnsafeUrlError for loopback addresses' do
        expect { described_class.fetch('http://127.0.0.1/secret') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsafeUrlError')
        end
      end

      it 'raises UnsafeUrlError for AWS metadata IP (169.254.169.254)' do
        expect { described_class.fetch('http://169.254.169.254/latest/meta-data/') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsafeUrlError')
        end
      end

      it 'raises UnsafeUrlError when hostname resolves to a private IP (DNS rebinding)' do
        allow(Resolv).to receive(:getaddresses).with('evil.example.com').and_return(['10.0.0.1'])
        expect { described_class.fetch('http://evil.example.com/secret') { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsafeUrlError')
        end
      end

      it 'allows private IP literals when private network access is enabled' do
        private_url = 'http://192.168.3.21/image.png'
        allow(Resolv).to receive(:getaddresses).with('192.168.3.21').and_return(['192.168.3.21'])
        stub_request(:get, private_url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') do
          expect { described_class.fetch(private_url) { nil } }.not_to raise_error
        end
      end

      it 'allows private hostnames when private network access is enabled' do
        private_url = 'http://internal-webhook-service/image.png'
        allow(Resolv).to receive(:getaddresses).with('internal-webhook-service').and_return(['10.0.0.5'])
        stub_request(:get, private_url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') do
          expect { described_class.fetch(private_url) { nil } }.not_to raise_error
        end
      end

      it 'allows redirects to private hostnames when private network access is enabled' do
        redirect_url = 'http://example.com/redirect.png'
        private_url = 'http://private.example.com/image.png'
        allow(Resolv).to receive(:getaddresses).with('private.example.com').and_return(['10.0.0.5'])
        stub_request(:get, redirect_url).to_return(status: 302, headers: { 'Location' => private_url })
        stub_request(:get, private_url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') do
          expect { described_class.fetch(redirect_url) { nil } }.not_to raise_error
        end
      end

      it 'strips caller-provided sensitive headers on private network cross-origin redirects' do
        redirect_url = 'http://example.com/redirect.png'
        private_url = 'http://private.example.com/image.png'
        redirected_headers = nil
        allow(Resolv).to receive(:getaddresses).with('private.example.com').and_return(['10.0.0.5'])
        stub_request(:get, redirect_url).to_return(status: 302, headers: { 'Location' => private_url })
        stub_request(:get, private_url)
          .with do |request|
            redirected_headers = request.headers.transform_keys(&:downcase)
            true
          end
          .to_return(
            status: 200,
            body: File.new(Rails.root.join('spec/assets/avatar.png')),
            headers: { 'Content-Type' => 'image/png' }
          )

        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') do
          described_class.fetch(
            redirect_url,
            headers: { 'X-API-Key' => 'secret-key' },
            sensitive_headers: ['X-API-Key']
          ) { nil }
        end

        expect(redirected_headers).not_to include('x-api-key')
      end
    end

    context 'with content-type allowlist' do
      it 'rejects text/html responses' do
        stub_request(:get, url).to_return(
          status: 200,
          body: '<html></html>',
          headers: { 'Content-Type' => 'text/html' }
        )

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsupportedContentTypeError')
        end
      end

      it 'rejects application/octet-stream responses' do
        stub_request(:get, url).to_return(
          status: 200,
          body: 'x',
          headers: { 'Content-Type' => 'application/octet-stream' }
        )

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsupportedContentTypeError')
        end
      end

      it 'allows video/mp4 responses' do
        stub_request(:get, url).to_return(
          status: 200,
          body: File.new(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'video/mp4' }
        )

        expect { described_class.fetch(url) { nil } }.not_to raise_error
      end

      it 'normalizes parameters and casing before yielding content_type' do
        stub_request(:get, url).to_return(
          status: 200,
          body: 'x',
          headers: { 'Content-Type' => 'IMAGE/PNG; charset=binary' }
        )

        described_class.fetch(url) do |result|
          expect(result.content_type).to eq('image/png')
        end
      end

      it 'allows exact content-type matches when prefixes are empty' do
        pdf_url = 'http://example.com/file.pdf'
        stub_request(:get, pdf_url).to_return(
          status: 200,
          body: 'pdf-data',
          headers: { 'Content-Type' => 'application/pdf' }
        )

        expect do
          described_class.fetch(
            pdf_url,
            allowed_content_type_prefixes: [],
            allowed_content_types: ['application/pdf']
          ) { nil }
        end.not_to raise_error
      end

      it 'rejects exact content-type mismatches when prefixes are empty' do
        stub_request(:get, url).to_return(
          status: 200,
          body: 'x',
          headers: { 'Content-Type' => 'image/webp' }
        )

        expect { described_class.fetch(url, allowed_content_type_prefixes: [], allowed_content_types: ['image/png']) { nil } }
          .to raise_error do |error|
            expect(error.class.name).to eq('SafeFetch::UnsupportedContentTypeError')
          end
      end

      it 'rejects when the content-type header is missing' do
        stub_request(:get, url).to_return(status: 200, body: 'x', headers: {})

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsupportedContentTypeError')
        end
      end
    end

    context 'with custom request options' do
      let(:post_body) { { hello: 'world' }.to_json }
      let(:headers) do
        {
          'Authorization' => 'Bearer test-token',
          'Content-Type' => 'application/json'
        }
      end

      it 'supports POST requests with custom headers when content-type validation is disabled' do
        stub_request(:post, url)
          .with(body: post_body, headers: headers)
          .to_return(status: 200, body: '', headers: {})

        expect do
          described_class.fetch(
            url,
            method: :post,
            body: post_body,
            headers: headers,
            validate_content_type: false
          ) { nil }
        end.not_to raise_error
      end

      it 'preserves non-credential headers on cross-origin redirects' do
        redirect_url = 'https://example.com/image.png'
        redirected_headers = nil
        headers = {
          'Authorization' => 'Bearer test-token',
          'Cookie' => 'session=test',
          'Content-Type' => 'application/json',
          'X-Chatwoot-Delivery' => 'test-uuid',
          'X-Chatwoot-Signature' => 'sha256=test-signature'
        }

        stub_request(:post, url).to_return(
          status: 307,
          headers: { 'Location' => redirect_url }
        )
        stub_request(:post, redirect_url)
          .with do |request|
            redirected_headers = request.headers.transform_keys(&:downcase)
            true
          end
          .to_return(status: 200, body: '', headers: {})

        described_class.fetch(
          url,
          method: :post,
          body: post_body,
          headers: headers,
          validate_content_type: false
        ) { nil }

        expect(redirected_headers).to include(
          'content-type' => 'application/json',
          'x-chatwoot-delivery' => 'test-uuid',
          'x-chatwoot-signature' => 'sha256=test-signature'
        )
        expect(redirected_headers).not_to include('authorization', 'cookie')
      end

      it 'strips caller-provided sensitive headers on cross-origin redirects' do
        redirect_url = 'https://example.com/image.png'
        redirected_headers = nil
        headers = { 'X-API-Key' => 'secret-key' }

        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => redirect_url })
        stub_request(:get, redirect_url)
          .with do |request|
            redirected_headers = request.headers.transform_keys(&:downcase)
            true
          end
          .to_return(status: 200, body: '', headers: {})

        described_class.fetch(
          url,
          headers: headers,
          sensitive_headers: ['X-API-Key'],
          validate_content_type: false
        ) { nil }

        expect(redirected_headers).not_to include('x-api-key')
      end

      it 'preserves caller-provided sensitive headers on same-origin redirects' do
        redirect_url = 'http://example.com/redirected.png'

        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => '/redirected.png' })
        stub_request(:get, redirect_url)
          .with(headers: { 'X-API-Key' => 'secret-key' })
          .to_return(status: 200, body: '', headers: {})

        described_class.fetch(
          url,
          headers: { 'X-API-Key' => 'secret-key' },
          sensitive_headers: ['X-API-Key'],
          validate_content_type: false
        ) { nil }

        expect(WebMock).to have_requested(:get, redirect_url).with(headers: { 'X-API-Key' => 'secret-key' })
      end

      it 'raises UnsupportedMethodError for unsupported HTTP methods' do
        expect { described_class.fetch(url, method: :options) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::UnsupportedMethodError')
        end
      end
    end

    context 'with body size cap' do
      it 'honours a custom max_bytes argument' do
        stub_request(:get, url).to_return(
          status: 200,
          body: 'xxxxx',
          headers: { 'Content-Type' => 'image/png' }
        )

        expect { described_class.fetch(url, max_bytes: 2) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::FileTooLargeError')
        end
      end

      it 'reads the default cap from GlobalConfigService MAXIMUM_FILE_UPLOAD_SIZE (matching Attachment#validate_file_size)' do
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return('1')

        oversize = 'x' * (1.megabyte + 1)
        stub_request(:get, url).to_return(
          status: 200,
          body: oversize,
          headers: { 'Content-Type' => 'image/png' }
        )

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::FileTooLargeError')
        end
      end

      it 'falls back to 40 MB when GlobalConfigService returns a non-positive value' do
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return('-10')

        # 1 MB body should pass under the 40 MB fallback
        stub_request(:get, url).to_return(
          status: 200,
          body: 'x' * 1.megabyte,
          headers: { 'Content-Type' => 'image/png' }
        )

        expect { described_class.fetch(url) { nil } }.not_to raise_error
      end

      it 'allows uploads between the old hardcoded 10 MB and the configured limit (regression check)' do
        # Default config is 40 MB; a 15 MB upload must succeed.
        # This is the exact regression scenario: with the old hardcoded 10 MB cap,
        # this would have failed even though direct file uploads of the same size succeed.
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return('40')

        stub_request(:get, url).to_return(
          status: 200,
          body: 'x' * (15 * 1024 * 1024),
          headers: { 'Content-Type' => 'image/png' }
        )

        expect { described_class.fetch(url) { nil } }.not_to raise_error
      end
    end

    context 'with network failures' do
      it 'maps Net::ReadTimeout to FetchError' do
        stub_request(:get, url).to_raise(Net::ReadTimeout)

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::FetchError')
        end
      end

      it 'maps SocketError to FetchError' do
        stub_request(:get, url).to_raise(SocketError.new('connection refused'))

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::FetchError')
        end
      end
    end

    context 'with non-2xx upstream responses' do
      it 'raises HttpError on non-2xx responses, carrying the status as an integer' do
        stub_request(:get, url).to_return(status: 404, body: '', headers: {})

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::HttpError')
          expect(error.status).to eq(404)
        end
      end

      # O Net::HTTP, depois de entregar a resposta ao bloco, lê o corpo INTEIRO em memória
      # (`reading_body` → `body`) — a menos que o bloco levante. A recusa tem de vir de dentro do
      # bloco, ou um 404 de tamanho arbitrário é materializado só para ser descartado.
      it 'raises before the body of the non-2xx response is read' do
        body_read = false
        response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
        allow(response).to receive(:body) { body_read = true }
        allow(response).to receive(:read_body) { body_read = true }
        allow(SsrfFilter).to receive(:get) do |*, &block|
          block.call(response)
          response.body
          response
        end

        expect { described_class.fetch(url) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::HttpError')
          expect(error.status).to eq(404)
        end
        expect(body_read).to be(false)
      end
    end

    context 'with max_redirects: 0' do
      it 'refuses the first redirect as HttpError with its status, without following it' do
        destination = 'http://example.com/elsewhere.png'
        stub_request(:get, url).to_return(status: 302, body: 'x' * 1000, headers: { 'Location' => destination })
        stub_request(:get, destination).to_return(status: 200, body: 'y', headers: { 'Content-Type' => 'image/png' })

        expect { described_class.fetch(url, max_redirects: 0) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::HttpError')
          expect(error.status).to eq(302)
        end
        expect(a_request(:get, destination)).not_to have_been_made
      end

      it 'rejects a negative or non-integer max_redirects' do
        expect { described_class.fetch(url, max_redirects: -1) { nil } }.to raise_error(ArgumentError, /max_redirects/)
        expect { described_class.fetch(url, max_redirects: '2') { nil } }.to raise_error(ArgumentError, /max_redirects/)
      end
    end

    context 'with an announced Content-Length above max_bytes' do
      it 'raises FileTooLargeError before reading the body' do
        stub_request(:get, url).to_return(status: 200, body: 'x', headers: { 'Content-Type' => 'image/png', 'Content-Length' => '3' })

        expect { described_class.fetch(url, max_bytes: 2) { nil } }.to raise_error do |error|
          expect(error.class.name).to eq('SafeFetch::FileTooLargeError')
        end
      end
    end

    context 'with total_timeout' do
      it 'rejects a non-positive or non-numeric total_timeout' do
        expect { described_class.fetch(url, total_timeout: 0) { nil } }.to raise_error(ArgumentError, /total_timeout/)
        expect { described_class.fetch(url, total_timeout: '5') { nil } }.to raise_error(ArgumentError, /total_timeout/)
      end

      it 'bounds open_timeout and read_timeout by the total, so no single wait outlives it' do
        options = SafeFetch::RequestOptions.new(url: url, open_timeout: 5, read_timeout: 30, total_timeout: 3)

        expect(options.request_options[:http_options]).to eq(open_timeout: 3, read_timeout: 3)
        expect(options.request_options[:max_redirects]).to eq(SsrfFilter::DEFAULT_MAX_REDIRECTS)
      end

      # O socket é a alavanca por leitura. Sem ele (WebMock; ou um Net::HTTP que deixe de expor o ivar),
      # o prazo vale só entre pedaços — degradação REGISTRADA, uma vez por transferência, com código
      # fechado; nunca em silêncio (rodada 7 da entrega 11).
      it 'registers once, with a closed code, when there is no socket to tighten, and keeps the deadline between chunks' do
        allow(Rails.logger).to receive(:warn).and_call_original
        deadline = SafeFetch::Deadline.new(5)

        deadline.enforce!(nil)
        deadline.enforce!(nil)

        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/\[safe_fetch\] total_timeout degradado motivo=sem_socket/)).once
        expect(deadline.binding?).to be(false)
        expect(deadline.remaining).to be <= 5
      end

      it 'tightens the socket read_timeout to what is left, without registering anything' do
        allow(Rails.logger).to receive(:warn).and_call_original
        socket = Struct.new(:read_timeout).new(30)
        deadline = SafeFetch::Deadline.new(5)

        deadline.enforce!(socket)

        expect(socket.read_timeout).to be_between(4, 5)
        expect(deadline.binding?).to be(true)
        expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/safe_fetch/))
      end
    end

    # O QUE O WEBMOCK NÃO EMULA: o socket. Um servidor real em 127.0.0.1, com o WebMock desligado (ele
    # lê a conexão real inteira antes do bloco) e `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` para falar com a
    # máquina local — pelo mesmo `Fetcher` do caminho público.
    context 'with a real connection' do
      after { servidor.parar }

      def on_the_local_network(&)
        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') { sem_webmock(&) }
      end

      context 'when a non-2xx response has a huge body' do
        let(:total) { 32.megabytes }
        let(:servidor) do
          servidor_http_local do |s, cliente|
            s.escrever(cliente, s.cabecalhos(404, 'application/xml', total))
            loop { break if s.bytes_escritos >= total || !s.escrever(cliente, 'x' * 65_536) }
          end
        end

        it 'closes the connection instead of reading the body' do
          on_the_local_network do
            expect { described_class.fetch(servidor.url('/missing'), validate_content_type: false) { nil } }.to raise_error do |error|
              expect(error.class.name).to eq('SafeFetch::HttpError')
              expect(error.status).to eq(404)
            end
          end
          servidor.parar

          expect(servidor.bytes_escritos).to be < total
        end
      end

      # Pedaços com pausas crescentes nunca estouram um `read_timeout` por leitura; só o prazo do corpo
      # (`total_timeout`, monotônico) segura isso — e cada leitura espera só o que resta dele: a recusa
      # vem ao vencer (1 s), não quando o pedaço seguinte chega (2,1 s), nem quando uma leitura isolada
      # estoura (1,9 s).
      context 'when the body arrives slower than the total_timeout' do
        let(:servidor) do
          servidor_http_local do |s, cliente|
            s.escrever(cliente, s.cabecalhos(200, 'application/octet-stream', 40) + ('a' * 10))
            [0.3, 0.6, 1.2].each do |pausa|
              sleep(pausa)
              break unless s.escrever(cliente, 'a' * 10)
            end
          end
        end

        it 'raises TotalTimeoutError when the total is up, waiting on each read only what is left' do
          opcoes = { validate_content_type: false, total_timeout: 1, read_timeout: 5 }
          inicio = segundos_monotonicos

          on_the_local_network do
            expect { described_class.fetch(servidor.url('/slow'), **opcoes) { nil } }.to raise_error do |error|
              expect(error.class.name).to eq('SafeFetch::TotalTimeoutError')
            end
          end

          expect(segundos_monotonicos - inicio).to be < 1.6
        end
      end
    end
  end
end
# rubocop:enable Style/RedundantFetchBlock
