require 'rails_helper'

# `max_retries:` (#2906): o `Net::HTTP` repete uma vez o GET que estourou o `read_timeout` esperando os cabeçalhos, com
# conexão nova e o prazo inteiro de novo. Quem tem prazo para cumprir passa 0; sem a opção, nada muda.
RSpec.describe SafeFetch::RequestOptions do
  it 'passes max_retries to Net::HTTP when given' do
    options = described_class.new(url: 'https://example.com/a.json', max_retries: 0)

    expect(options.request_options[:http_options]).to include(max_retries: 0)
  end

  it 'leaves the Net::HTTP default when not given' do
    expect(described_class.new(url: 'https://example.com/a.json').request_options[:http_options]).not_to have_key(:max_retries)
  end

  it 'refuses a negative or non-integer max_retries' do
    [-1, 1.5, '0'].each do |valor|
      expect { described_class.new(url: 'https://example.com/a.json', max_retries: valor) }.to raise_error(ArgumentError)
    end
  end
end
