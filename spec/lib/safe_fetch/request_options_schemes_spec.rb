require 'rails_helper'

# `schemes:` (#1099): quem só aceita https passa a lista ao ssrf_filter, que a confere em CADA salto — um
# redirecionamento para http é recusado sem ser seguido.
RSpec.describe SafeFetch::RequestOptions do
  it 'passes the allowed schemes to every hop of the redirect chain' do
    options = described_class.new(url: 'https://example.com/a.png', schemes: ['https'])

    expect(options.request_options).to include(scheme_whitelist: ['https'])
  end

  it 'keeps the default schemes when none is given' do
    expect(described_class.new(url: 'https://example.com/a.png').request_options).not_to have_key(:scheme_whitelist)
  end

  it 'refuses a redirect to http before following it' do
    stub_request(:get, 'https://example.com/a.png').to_return(status: 302, headers: { 'Location' => 'http://example.com/a.png' })
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])

    expect { SafeFetch.fetch('https://example.com/a.png', schemes: ['https']) { |result| result } }
      .to raise_error(SafeFetch::InvalidUrlError)
    expect(a_request(:get, 'http://example.com/a.png')).not_to have_been_made
  end
end
