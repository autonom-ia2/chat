# Motor da nota de uma busca nova (#681, frente B). Toda busca calcula a nota do Orth ao lado da legada:
#
# - conta no motor legado: a nota do Orth fica só na busca (lead_scoring[id]['orth']), e nada do que a conta vê muda. Se
#   a nota do Orth falhar, a busca segue, o erro vai para o log e para a busca (score_shadow_error);
# - conta virada para o Orth pelo superadmin: nota, prioridade, posição, detalhe, fatores e frase do lead passam a ser os
#   do Orth, e a legada fica na busca (lead_scoring[id]['legacy']) para comparar. Falha da nota do Orth derruba a busca:
#   mostrar a legada como se fosse a do Orth seria mentir para a conta.
#
# Só a busca nova é gravada; lead e busca antigos ficam como estão.
class Autonomia::Prospecting::Scoring::SearchScoring
  class EngineError < StandardError; end

  LOG_TAG = '[Prospecting::SearchScoring]'.freeze

  attr_reader :shadow_error

  def initialize(setting:, mode:, filters:)
    @setting = setting
    @mode = mode
    @filters = filters
  end

  # Devolve, por id do lead, o que a busca acrescenta em lead_scoring. Com o motor do Orth, grava as colunas do lead.
  def apply!(leads)
    return {} if leads.empty?

    entries = orth_entries(leads)
    return {} if entries.nil?
    return entries.to_h { |entry| [entry.lead.id.to_s, { 'orth' => entry.summary }] } unless @setting.orth_score_engine?

    switch_to_orth!(entries)
  end

  private

  # NotImplementedError não é StandardError: é o que o esboço da fórmula levanta enquanto a frente A não chega.
  def orth_entries(leads)
    Autonomia::Prospecting::Scoring::OrthRanking.new(leads: leads, mode: @mode, weights: @setting.orth_scoring_weights,
                                                     filters: @filters).perform
  rescue StandardError, NotImplementedError => e
    raise EngineError, "#{e.class.name}: #{e.message}" if @setting.orth_score_engine?

    Rails.logger.warn("#{LOG_TAG} score_shadow_failed account_id=#{@setting.account_id} error=#{e.class.name}")
    @shadow_error = e.class.name
    nil
  end

  # A legada é lida antes de o lead receber a do Orth.
  def switch_to_orth!(entries)
    entries.to_h do |entry|
      legacy = legacy_summary(entry.lead)
      entry.lead.update_columns(entry.lead_columns(@mode)) # rubocop:disable Rails/SkipsModelValidations
      [entry.lead.id.to_s, { 'orth' => entry.summary, 'legacy' => legacy }]
    end
  end

  def legacy_summary(lead)
    { 'score' => lead.score&.to_f, 'priority_score' => lead.priority_score&.to_f, 'priority_position' => lead.priority_position,
      'band' => Autonomia::Prospecting::Scoring::Band.code(lead.priority_score), 'human_insight' => lead.human_insight }
  end
end
