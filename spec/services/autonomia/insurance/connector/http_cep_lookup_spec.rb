require 'rails_helper'

# O CONTRATO DA CONSULTA DE CEP na fronteira (autonomia-adapters#87). Os corpos NÃO são escritos aqui:
# vêm de `spec/fixtures/files/autonomia_cep_lookup_handler.json`, que é a saída de `handleRequest` do
# adapter (`POST /v1/agger/cep/lookup`, commit 848aaee da branch `feat/consulta-cep`), status e corpo
# byte a byte, com o portal dublado pelo `fetch`. Corpo escrito supondo o formato foi o que fez o mock
# em snake_case de 04/09/2026 aprovar a si mesmo (`http_contrato_real_spec`).
#
# O que se prova: o `Http` entrega as chaves que a ferramenta lê (`cep`, `logradouro`, `bairro`,
# `cidade`, `uf`), e a recusa do adapter chega como `validation` com `details['perguntas']` intacto.
# Quando o contrato do adapter mudar, regerar a fixture pelo handler e ver o que quebra.
RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }
  let(:sessao) { { 'multicalculoToken' => 'm' } }
  let(:do_handler) { JSON.parse(Rails.root.join('spec/fixtures/files/autonomia_cep_lookup_handler.json').read) }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo'))
  end

  # A invocação devolve 200; o status e o corpo do handler vão dentro, como no Lambda.
  def stub_lambda(caso)
    stub_request(:post, invoke_url).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: do_handler.fetch(caso).to_json
    )
  end

  def consultar(cep = '01310-100')
    described_class.new.cep_lookup(provider: 'agger', session: sessao, cep: cep)
  end

  def recusa
    consultar
  rescue Autonomia::Insurance::Connector::Error => e
    e
  end

  it 'chama a rota do adapter com a sessao e o CEP, no teto curto da conferencia' do
    tempos = []
    # O timeout é posto num `Net::HTTP` que o próprio conector cria; não há costura para injetar.
    allow_any_instance_of(Net::HTTP).to receive(:read_timeout=) { |_, valor| tempos << valor } # rubocop:disable RSpec/AnyInstance
    stub_lambda('urbano')

    consultar

    expect(WebMock).to(have_requested(:post, invoke_url).with do |req|
      evento = JSON.parse(req.body)
      evento['rawPath'] == '/v1/agger/cep/lookup' &&
        JSON.parse(evento['body']) == { 'session' => sessao, 'cep' => '01310-100' }
    end)
    expect(tempos).to eq([described_class::CONFERENCIA_TIMEOUT])
  end

  it 'entrega as chaves que a ferramenta le, com o endereco que o adapter devolveu' do
    stub_lambda('urbano')

    expect(consultar).to eq('cep' => '01310100', 'logradouro' => 'Avenida Paulista - de 612 A 1510 - Lado Par',
                            'bairro' => 'Bela Vista', 'cidade' => 'São Paulo', 'uf' => 'SP')
  end

  it 'CEP inexistente chega como validation com as perguntas do adapter' do
    stub_lambda('inexistente')

    erro = recusa

    expect(erro.kind).to eq(:validation)
    expect(erro.details['perguntas']).to eq(
      [{ 'campo' => 'cep', 'motivo' => 'o portal não encontrou este CEP. Confirme o CEP com o cliente.' }]
    )
  end

  it 'cidade de CEP unico chega com a rua e o bairro a perguntar' do
    stub_lambda('cep_unico')

    expect(recusa.details['perguntas'].pluck('campo')).to eq(%w[logradouro bairro])
  end

  it 'portal fora chega como unavailable, sem perguntas' do
    stub_lambda('portal_fora')

    erro = recusa

    expect(erro.kind).to eq(:unavailable)
    expect(erro.details).to eq({})
  end

  # O MOCK ENSINA A MESMA FORMA: o que o `Http` entrega com a saída do handler é o que o mock devolve, e
  # as perguntas do mock são as do adapter, palavra por palavra.
  it 'o mock devolve as mesmas chaves e as mesmas perguntas que o Http entrega' do
    mock = Autonomia::Insurance::Connector::Mock.new
    stub_lambda('urbano')
    real = consultar
    stub_lambda('inexistente')
    do_inexistente = recusa.details['perguntas']
    stub_lambda('cep_unico')
    do_cep_unico = recusa.details['perguntas']

    expect(mock.cep_lookup(provider: 'agger', session: sessao, cep: '01310-100')).to eq(real)
    expect { mock.cep_lookup(provider: 'agger', session: sessao, cep: '99999999') }
      .to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.details['perguntas']).to eq(do_inexistente) }
    expect { mock.cep_lookup(provider: 'agger', session: sessao, cep: '12600000') }
      .to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.details['perguntas']).to eq(do_cep_unico) }
  end
end
