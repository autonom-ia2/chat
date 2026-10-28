require 'rails_helper'

# Prazo de quem chama (Seus posts, #2304): cada requisição usa só o tempo que falta, inclusive a cada página de posts;
# passado o prazo, a requisição nem sai e volta com o erro TEMPO.
RSpec.describe Meta::AdsGraphClient::Prazo do
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:agora) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def cliente(prazo: nil)
    Meta::AdsGraphClient.new(access_token: 'page-token-de-teste', api_version: 'v23.0', prazo: prazo)
  end

  def stub_perfil
    stub_request(:get, 'https://graph.facebook.com/v23.0/1001')
      .with(query: hash_including({}))
      .to_return(status: 200, headers: json, body: { name: 'Studio Acme' }.to_json)
  end

  it 'sem prazo, cada requisição espera o tempo de sempre' do
    stub_perfil
    allow(HTTParty).to receive(:get).and_call_original

    expect(cliente.page_profile('1001').ok).to be(true)
    expect(HTTParty).to have_received(:get).with(anything, hash_including(timeout: Meta::AdsGraphClient::TIMEOUT_SECONDS))
  end

  it 'com prazo perto, a requisição espera só o que falta dele' do
    stub_perfil
    allow(HTTParty).to receive(:get).and_call_original

    cliente(prazo: agora + 3).page_profile('1001')

    expect(HTTParty).to have_received(:get).with(anything, hash_including(timeout: be <= 3))
  end

  it 'prazo passado: a requisição nem sai e volta com o erro TEMPO' do
    stub_perfil

    resultado = cliente(prazo: agora - 1).page_profile('1001')

    expect(resultado).to have_attributes(ok: false, error_code: described_class::TEMPO)
    expect(a_request(:get, 'https://graph.facebook.com/v23.0/1001').with(query: hash_including({}))).not_to have_been_made
  end

  it 'o prazo vale a cada página de posts: a lista para quando ele passa' do
    pagina = { data: [{ id: 'p1' }], paging: { cursors: { after: 'X' }, next: 'https://graph.facebook.com/next' } }
    # Relógio parado em 0 até a 1ª página voltar; ela leva 30 s, e a 2ª já sairia depois do prazo de 20 s.
    relogio = 0.0
    allow(Process).to receive(:clock_gettime).and_wrap_original do |original, *args|
      args.first == Process::CLOCK_MONOTONIC ? relogio : original.call(*args)
    end
    stub_request(:get, 'https://graph.facebook.com/v23.0/1001/published_posts').with(query: hash_including({})).to_return do
      relogio += 30
      { status: 200, headers: json, body: pagina.to_json }
    end

    resultado = cliente(prazo: 20.0).page_posts('1001', since: 1, until: 2)

    expect(resultado).to have_attributes(ok: false, error_code: described_class::TEMPO)
    expect(a_request(:get, 'https://graph.facebook.com/v23.0/1001/published_posts').with(query: hash_including({}))).to have_been_made.once
  end
end
