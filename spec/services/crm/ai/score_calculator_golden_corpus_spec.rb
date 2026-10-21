require 'rails_helper'

# CORPUS do golden set: casos gerados por orquestração (classificação Sonnet em lote + arbitragem
# Opus nos ambíguos + revisão final humana/Codex) sobre conversas reais das contas 18, 6, 16 e 3.
#
# A fixture guarda, por caso: os sinais que a IA leria, os dias de silêncio e a faixa que um
# operador experiente daria. Este spec afirma que a aritmética dos pesos reproduz o julgamento.
# Complementa o score_calculator_golden_set_spec (casos curados à mão, com invariantes de ordem).
RSpec.describe Crm::Ai::ScoreCalculator do
  fixture = Rails.root.join('spec/fixtures/crm_score_golden_cases.yml')
  # #1962: caso cuja faixa mudou por regra nova traz `revisado_1962` com a faixa nova e o motivo. O julgamento
  # original fica no arquivo, para a próxima calibragem saber de onde partiu.
  corpus = YAML.safe_load_file(fixture).map do |c|
    c.merge('expected_tier' => c.dig('revisado_1962', 'expected_tier') || c['expected_tier'])
  end
  now = Time.zone.parse('2026-07-30 12:00:00')

  corpus.group_by { |c| c['expected_tier'] }.each do |tier, cases|
    it "reproduz o julgamento do operador nos #{cases.size} casos '#{tier}'" do
      erros = cases.filter_map do |c|
        # #1962: quem falou por último vem do banco; nos casos, é o last_turn_owner gravado. Se a fala pede resposta
        # nossa é leitura do modelo (awaiting_our_reply), que o corpus não tinha: vale "pede" quando o cliente falou
        # por último, salvo o caso que traz a leitura explícita (revisada um a um no #1962).
        cliente_por_ultimo = c.dig('signals', 'last_turn_owner') == 'cliente'
        signals = c['signals'].reverse_merge('awaiting_our_reply' => cliente_por_ultimo)
        last = now - c['idle_days'].to_i.days
        got = described_class.new(signals: signals, last_message_at: last, waiting_since: (last if cliente_por_ultimo),
                                  now: now).perform
        "#{c['ref']} (#{c['resumo']}): esperado #{tier}, saiu #{got.tier} (#{got.value})" if got.tier != tier
      end
      expect(erros).to be_empty, erros.join("\n")
    end
  end

  it 'tem o tamanho mínimo do corpus (não encolher sem decisão explícita)' do
    expect(corpus.size).to be >= 90
  end
end
