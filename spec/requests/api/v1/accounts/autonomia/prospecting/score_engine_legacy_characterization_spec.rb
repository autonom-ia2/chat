require 'rails_helper'

# Sem regressão (#681): enquanto o superadmin não vira a conta para o motor do Orth, a tela recebe exatamente o que
# recebia antes do modo sombra. A referência foi gravada com o código de antes (spec/support/prospecting_payload_snapshot.rb);
# qualquer byte diferente em nota, prioridade, ordem, faixa, frase ou detalhe da nota quebra este spec.
RSpec.describe 'Autonomia prospecting legacy score engine characterization', type: :request do
  include_context 'with prospecting legacy engine snapshot'
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:reference) { file_fixture(ProspectingPayloadSnapshot::FIXTURE).read }
  let(:orth_scorer) { Autonomia::Prospecting::Scoring::OrthScorer }

  it 'devolve o mesmo payload de antes, byte a byte, com a nota do Orth indisponível' do
    expect("#{JSON.pretty_generate(legacy_engine_snapshot)}\n").to eq(reference)
  end

  # A nota sombra existe e é bem diferente da legada, e mesmo assim nada dela chega à tela.
  it 'devolve o mesmo payload de antes, byte a byte, com a nota do Orth calculada em sombra' do
    allow(orth_scorer).to receive(:new) do |leads:, **|
      instance_double(orth_scorer, perform: leads.each_index.map do |index|
        orth_scorer::Result.new(score: 99 - index, priority_score: index * 10, components: [], negative_factors: ['sombra'],
                                human_insight: 'Frase do Orth', effective_weights: {})
      end)
    end

    expect("#{JSON.pretty_generate(legacy_engine_snapshot)}\n").to eq(reference)
    expect(orth_scorer).to have_received(:new).twice
  end
end
