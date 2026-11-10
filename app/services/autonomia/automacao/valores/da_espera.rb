# Os valores que leem a janela do "esperar até" (Valores#lido): a resposta que chegou durante a espera (G11,
# Resposta::VALORES) e a nova entrada do card na etapa do gatilho (G50, EsperaDaEntrada::VALORES). Saiu de `Valores`
# para ele caber no tamanho; onde cada um vale fica no LugarDoValor.
module Autonomia::Automacao::Valores::DaEspera
  VALORES = ::Autonomia::Automacao::Resposta::VALORES.merge(::Autonomia::Automacao::EsperaDaEntrada::VALORES).freeze

  module_function

  def caminho?(caminho) = VALORES.key?(caminho.to_s)

  # Sem a janela (fora do "esperar até", o ensaio), lê false: nunca "respondeu" nem "entrou de novo", e "diferente de
  # true" não vira resposta.
  def ler(caminho, contexto, espera, quem) = !espera.nil? && VALORES.fetch(caminho.to_s).call(contexto, espera, quem) == true
end
