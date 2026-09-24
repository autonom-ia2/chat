require 'rails_helper'

# Uma linha por entrada do mapa de erros do Google (#677): cada status, cada código HTTP sem status e cada motivo de
# configuração leva a uma frase escrita aqui por extenso. Trocar a frase de uma entrada no mapa quebra a linha dela.
RSpec.describe Autonomia::Prospecting::Providers::GooglePlacesProvider do
  indisponivel = 'A busca no Google está indisponível no momento. Fale com o suporte.'
  sobrecarregado = 'A busca no Google está sobrecarregada agora. Tente de novo em alguns minutos.'
  parametros = 'O Google recusou os dados da busca. Confira o termo, o local e a área e tente de novo.'
  sem_resposta = 'O Google não respondeu a tempo. Tente de novo em alguns minutos.'
  local_nao_encontrado = 'O Google não encontrou esse local. Escolha outra sugestão da lista.'

  let(:provider) do
    described_class.new(query: 'restaurante', location: 'Sao Paulo', radius: 5000, limit: 1, api_key: 'chave', account_id: 42)
  end

  def stub_google_error(http_status, google_status: nil, reason: nil)
    error = { code: http_status, message: 'texto do Google', status: google_status }.compact
    error[:details] = [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: reason }] if reason
    stub_request(:post, described_class::ENDPOINT).to_return(status: http_status, body: { error: error }.to_json)
  end

  def expect_message(expected)
    expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError) { |error|
      expect(error.message).to eq(expected)
    }
  end

  {
    'PERMISSION_DENIED' => [403, indisponivel],
    'UNAUTHENTICATED' => [401, indisponivel],
    'FAILED_PRECONDITION' => [400, indisponivel],
    'RESOURCE_EXHAUSTED' => [429, sobrecarregado],
    'INVALID_ARGUMENT' => [400, parametros],
    'NOT_FOUND' => [404, local_nao_encontrado],
    'UNAVAILABLE' => [503, sem_resposta],
    'DEADLINE_EXCEEDED' => [504, sem_resposta],
    'INTERNAL' => [500, sem_resposta]
  }.each do |google_status, (http_status, expected)|
    it "traduz o status #{google_status}" do
      stub_google_error(http_status, google_status: google_status)

      expect_message(expected)
    end
  end

  it 'cobre todos os status do mapa' do
    expect(Autonomia::Prospecting::GoogleErrorMessage::STATUS_KEYS.keys).to contain_exactly(
      'PERMISSION_DENIED', 'UNAUTHENTICATED', 'FAILED_PRECONDITION', 'RESOURCE_EXHAUSTED', 'INVALID_ARGUMENT',
      'NOT_FOUND', 'UNAVAILABLE', 'DEADLINE_EXCEEDED', 'INTERNAL'
    )
  end

  # Sem error.status no corpo, vale o código HTTP.
  {
    429 => sobrecarregado,
    404 => local_nao_encontrado,
    500 => sem_resposta,
    503 => sem_resposta,
    504 => sem_resposta,
    418 => indisponivel
  }.each do |http_status, expected|
    it "traduz o HTTP #{http_status} sem status do Google" do
      stub_google_error(http_status)

      expect_message(expected)
    end
  end

  it 'cobre todos os códigos HTTP do mapa' do
    expect(Autonomia::Prospecting::GoogleErrorMessage::HTTP_KEYS.keys).to contain_exactly(429, 404, 500, 503, 504)
  end

  # Chave vencida ou API desligada chegam como INVALID_ARGUMENT ou PERMISSION_DENIED e não são culpa de quem busca.
  %w[API_KEY_INVALID API_KEY_EXPIRED API_KEY_SERVICE_BLOCKED SERVICE_DISABLED].each do |reason|
    it "trata o motivo #{reason} como indisponível, mesmo em INVALID_ARGUMENT" do
      stub_google_error(400, google_status: 'INVALID_ARGUMENT', reason: reason)

      expect_message(indisponivel)
    end
  end

  it 'cobre todos os motivos de configuração do mapa' do
    expect(Autonomia::Prospecting::GoogleErrorMessage::CONFIGURATION_REASONS).to contain_exactly(
      'API_KEY_INVALID', 'API_KEY_EXPIRED', 'API_KEY_SERVICE_BLOCKED', 'SERVICE_DISABLED'
    )
  end
end
