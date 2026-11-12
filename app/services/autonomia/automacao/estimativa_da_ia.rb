# Quanto um passo de IA deve custar antes de rodar a primeira vez (#2574, F5.4): o modelo do passo e uma ordem de tokens
# do tipo dele, pela tabela de preço que também calcula o custo gravado (Crm::Ai::Pricing). Nunca chama a IA. Depois que
# o passo roda, a tela usa a média real dele (CustosDaIa.por_passo); isto é só para a confirmação do ligar não ficar sem
# número na primeira vez.
#
# - Entrada: o teto do que o passo lê por padrão (Decisor::LEITURAS_PADRAO: as mensagens anteriores até
#   Decisores::Estado::MAX_CARACTERES e a da vez até o mesmo teto), a regra comum (PassoDeIa::REGRA) e uma instrução de
#   tamanho médio, a cerca de 4 caracteres por token. É teto, não média: conversa curta custa menos.
# - Saída: a ordem da resposta em JSON de cada tipo, com o raciocínio baixo (PassoDeIa::ESFORCO). O "para cada item"
#   devolve uma lista, por isso é o maior.
# - Fora da conta: anexos (foto, PDF) e o galho "a cada mensagem", que vai à IA uma vez por mensagem (a tela já avisa).
#
# É dinheiro da conta: quem chama confere `financial_view` antes, como no CustosDaIa.
class Autonomia::Automacao::EstimativaDaIa
  CARACTERES_POR_TOKEN = 4
  INSTRUCAO = 1_000
  CONVERSA = 2 * ::Autonomia::Decisores::Estado::MAX_CARACTERES
  ENTRADA = (CONVERSA + ::Autonomia::Automacao::PassoDeIa::REGRA.length + INSTRUCAO) / CARACTERES_POR_TOKEN
  SAIDA = { 'decidir' => 300, 'extrair' => 500, 'escrever' => 800, 'resumir' => 800, 'para_cada' => 2_000 }.freeze

  # { tipo => { modelo:, tokens:, custo_usd: } } de cada passo de IA do motor (IaNoExecutor::IA).
  def self.por_tipo
    ::Autonomia::Automacao::IaNoExecutor::IA.to_h do |tipo, classe|
      saida = SAIDA.fetch(tipo)
      custo = ::Crm::Ai::Pricing.cost(model: classe::MODELO, input_tokens: ENTRADA, output_tokens: saida)
      [tipo, { modelo: classe::MODELO, tokens: ENTRADA + saida, custo_usd: custo.round(6) }]
    end
  end
end
