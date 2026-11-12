# Quanto a IA das automações custou (#2500 C2): a soma de cada automação, para a lista, e a média por passo, para o
# cartão ("cerca de US$ X por vez"). Lê o custo que o registro de cada passo já guarda (`dados.ia.custo_usd`), dos
# últimos 30 dias, que é o tempo em que os registros ficam. Só informação: nenhum número trava nada.
#
# É dinheiro da conta: quem chama confere `financial_view` antes (#1969, #2557).
class Autonomia::Automacao::CustosDaIa
  JANELA = ::Autonomia::Automacao::Registro::RETENCAO
  CUSTO = Arel.sql("(dados -> 'ia' ->> 'custo_usd')::numeric")
  TOKENS = Arel.sql("(dados -> 'ia' ->> 'tokens_entrada')::numeric + (dados -> 'ia' ->> 'tokens_saida')::numeric")

  # { automacao_id => soma em US$ }, só das que custaram algo.
  def self.por_automacao(automacao_ids)
    recentes(automacao_ids).group(:automacao_id).sum(CUSTO).transform_values(&:to_f).select { |_id, soma| soma.positive? }
  end

  # { passo => { media:, vezes:, tokens: } } de uma automação. `tokens` (#2574): a média de entrada + saída, quando o
  # registro os tem.
  def self.por_passo(automacao_id)
    recentes(automacao_id).group(:passo).pluck(:passo, Arel.sql("AVG(#{CUSTO})"), Arel.sql('COUNT(*)'), Arel.sql("AVG(#{TOKENS})"))
                          .to_h { |passo, media, vezes, tokens| [passo, { media: media.to_f, vezes: vezes, tokens: tokens&.round }.compact] }
  end

  # Só o registro com o custo em número: um valor torto nunca quebra a conta da tela.
  def self.recentes(automacao_ids)
    ::Autonomia::Automacao::Registro.where(automacao_id: automacao_ids, created_at: JANELA.ago..)
                                    .where("jsonb_typeof(dados -> 'ia' -> 'custo_usd') = 'number'")
  end
  private_class_method :recentes
end
