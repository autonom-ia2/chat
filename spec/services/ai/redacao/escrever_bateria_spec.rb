require 'rails_helper'

# Bateria do canal whatsapp_texto com os casos dos avisos do agendamento (#1354). Aqui roda SÓ com a resposta simulada
# de cada caso (`resposta_simulada`), para provar a conferência: o que quebra regra é descartado. A rodada com IA de
# verdade (mesmas entradas, critério em `esperado`) fica para o Rodrigo autorizar, com teto de custo.
RSpec.describe Ai::Redacao::Escrever do
  custom = Crm::BookingV2::Notices::CustomText
  casos = Rails.root.join('spec/fixtures/files/ai_redacao/whatsapp_texto.jsonl').readlines.map { |linha| JSON.parse(linha) }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  casos.each do |caso|
    it "#{caso['caso']}: #{caso['nota']}" do
      opcoes = caso['resposta_simulada'].map do |texto|
        { texto: texto, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: nil, certeza_categoria: nil, motivo_categoria: nil }
      end
      allow(client).to receive(:create)
        .and_return(text: { status: 'ok', pergunta: nil, sugestoes: [], problemas_encontrados: [], opcoes: opcoes }.to_json)

      resultado = described_class.call(
        account: account, feature: 'aviso_redacao', canal: 'whatsapp_texto', proposito: caso['proposito'], tom: caso['tom'],
        limites: { max_chars: custom::MAX_LENGTH }, chaves: { permitidas: custom::ALLOWED_KEYS, obrigatorias: custom::REQUIRED_KEYS },
        opcoes: 2
      )
      validas = resultado[:opcoes].select { |opcao| custom.problem(opcao[:texto]).nil? }

      expect(resultado[:status]).to eq(caso['esperado']['status'])
      expect(validas.size).to eq(caso['esperado']['validas'])
    end
  end
end
