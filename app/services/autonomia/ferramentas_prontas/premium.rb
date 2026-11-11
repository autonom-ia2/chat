# FERRAMENTAS PREMIUM (#2858, F7): as consultas pagas à BigDataCorp, na mesma vitrine das prontas. Cada card é uma fonte
# do catálogo (`Fontes::Premium::*`) e cada consulta do card é um dataset da BigDataCorp, que cobra por dataset.
#
# O que muda em relação às prontas grátis, e onde fica:
#   - a execução (`Premium::Execucao`): uma fonte só, sem reserva, com o cliente da BigDataCorp que a Prospecção já usa
#     (`Prospecting::Research::BigDataCorpClient`, mesma credencial `BIGDATACORP_USER`/`BIGDATACORP_PASSWORD`);
#   - o cache (`Premium::Cache`): por conta e só até o fim do dia — a mesma consulta no mesmo dia não paga de novo, e uma
#     conta nunca lê o que a outra pagou;
#   - a cobrança (`Premium::Cobranca`): 20 consultas grátis por card e por conta; da 21ª em diante, registrada como
#     cobrada, pelo custo × 1,5. Só registra: a fatura é feita a partir da telemetria (`Premium::Registro`);
#   - o orçamento do mês (`Premium::Orcamento`): alerta à equipe quando o custo passa de 80%.
#
# A flag `agente_ferramentas_prontas_premium` desligada tira os 7 cards da vitrine, do turno e do "Incluir" de uma vez,
# sem tocar na Cotação nem na Prospecção (elas não leem esta flag). Os cards não entram no Construtor nem no cartão
# "pode ganhar": consulta paga só entra no agente pela escolha de uma pessoa.
module Autonomia::FerramentasProntas::Premium
  FLAG = 'agente_ferramentas_prontas_premium'.freeze
  GRATIS = 20
  # Limite diário por conta e por card (o acesso da conta pode ter o seu). Proposta da F7, para aprovação do Rodrigo:
  # com o card mais caro (vistoria, R$ 0,39), 100 consultas dão no máximo R$ 39 por dia numa conta.
  LIMITE_DIARIO = 100

  module_function

  def fonte?(fonte)
    fonte.present? && fonte.premium?
  end

  # O que a tela mostra de cada card Premium liberado para a conta: quantas grátis restam e os preços depois delas.
  def para_tela(account, fontes)
    usadas = Saldo.da_conta_por_fonte(account)
    fontes.select(&:premium?).to_h do |fonte|
      [fonte.chave, { 'gratis' => GRATIS, 'restantes' => [GRATIS - usadas.fetch(fonte.chave, 0), 0].max,
                      'precos' => fonte.consultas.map { |consulta| consulta.dataset.preco.to_s('F') }.uniq.sort_by(&:to_d) }]
    end
  end
end
