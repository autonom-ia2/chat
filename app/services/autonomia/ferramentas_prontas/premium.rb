# FERRAMENTAS PREMIUM (#2858, F7): as consultas pagas à BigDataCorp, na mesma vitrine das prontas. Cada card é uma fonte
# do catálogo (`Fontes::Premium::*`) e cada consulta do card é um dataset da BigDataCorp, que cobra por dataset.
#
# O que muda em relação às prontas grátis, e onde fica:
#   - a execução (`Premium::Execucao`): uma fonte só, sem reserva, com o cliente da BigDataCorp que a Prospecção já usa
#     (`Prospecting::Research::BigDataCorpClient`, mesma credencial `BIGDATACORP_USER`/`BIGDATACORP_PASSWORD`);
#   - o cache (`Premium::Cache`): por conta e só até o fim do dia — a mesma consulta no mesmo dia não paga de novo, e uma
#     conta nunca lê o que a outra pagou;
#   - a cobrança (`Premium::Cobranca`): 20 consultas grátis por card e por conta A CADA MÊS (renovam no 1º dia, no
#     fuso da conta); da 21ª do mês em diante, registrada como cobrada, pelo custo × 1,5 arredondado para cima ao
#     centavo. Só registra: a fatura é feita a partir da telemetria (`Premium::Registro`);
#   - sem limite diário por conta e card nem alerta de orçamento (decisões do Rodrigo, 11/11): o cache do dia segura a
#     repetição, e a telemetria mostra o gasto.
#
# A flag `agente_ferramentas_prontas_premium` desligada tira os 7 cards da vitrine, do turno e do "Incluir" de uma vez,
# sem tocar na Cotação nem na Prospecção (elas não leem esta flag). Os cards não entram no Construtor nem no cartão
# "pode ganhar": consulta paga só entra no agente pela escolha de uma pessoa.
module Autonomia::FerramentasProntas::Premium
  FLAG = 'agente_ferramentas_prontas_premium'.freeze
  GRATIS = 20
  # OS DATASETS QUE A BIGDATACORP DESLIGOU (#2946). Teste direto na API em 12/11/2026: cada um respondeu
  # `-1203 DATASET DISABLED TEMPORARILY` em 0,4 s, sem cobrança. A consulta de um dataset desta lista sai do card
  # inteiro: da ferramenta do agente (o schema e as consultas aceitas), do "Responde N tipos de pergunta", da faixa de
  # preço e do Experimente (`ligadas`). O código da consulta fica no arquivo do card (`Fontes::Premium::*::CONSULTAS`):
  # quando a BigDataCorp religar, a consulta volta tirando a linha dela daqui. Os textos escritos à mão (a descrição do
  # card na vitrine e o artigo 11.14 da Central) voltam junto, no mesmo PR.
  DESLIGADAS_NA_FONTE = %w[
    ondemand_pgfn_company
    ondemand_cert_labor_debt_absence_company
    ondemand_fgts_company
    ondemand_cadin_company
    ondemand_rf_status_person
    ondemand_ibama_embargados_company
    partner_rede_vistorias_address
  ].freeze

  module_function

  # As consultas do card que a BigDataCorp responde hoje: fora as de `DESLIGADAS_NA_FONTE`.
  def ligadas(consultas)
    consultas.reject { |consulta| DESLIGADAS_NA_FONTE.include?(consulta.dataset.nome) }.freeze
  end

  # O maior prazo total entre as consultas Premium do catálogo, em segundos (o do dataset mais lento, com a folga da
  # `ConsultaPaga`). Os prazos do Experimente Premium e do varredor saem daqui (`Experimente::Pedido`,
  # `FecharEmAndamentoJob`): um dataset mais lento os estica sozinho.
  def prazo_maximo
    Autonomia::FerramentasProntas::Catalogo.premium.map(&:prazo_maximo).max
  end

  def fonte?(fonte)
    fonte.present? && fonte.premium?
  end

  # O dia de hoje no fuso da conta (o mesmo da `Execucao`, com a volta para o da plataforma).
  def hoje_da_conta(account)
    Autonomia::FerramentasProntas.fuso_da_conta(account).today
  end

  # O 1º dia do mês corrente no fuso da conta: a chave do saldo das grátis.
  def mes_da_conta(account)
    hoje_da_conta(account).beginning_of_month
  end

  # O que a tela mostra de cada card Premium liberado para a conta: quantas grátis restam no mês, os preços depois delas,
  # se o card confere CPF ou CNPJ (o "Quanto custa" só diz que número errado não conta nesse card) e quantos tipos de
  # pergunta ele responde (`consultas`, o selo do cartão: muda sozinho com `DESLIGADAS_NA_FONTE`).
  def para_tela(account, fontes)
    usadas = Saldo.da_conta_por_fonte(account, mes: mes_da_conta(account))
    fontes.select(&:premium?).to_h do |fonte|
      [fonte.chave, { 'gratis' => GRATIS, 'restantes' => [GRATIS - usadas.fetch(fonte.chave, 0), 0].max,
                      'precos' => fonte.consultas.map { |consulta| consulta.dataset.preco.to_s('F') }.uniq.sort_by(&:to_d),
                      'confere_documento' => confere_documento?(fonte), 'consultas' => fonte.consultas.size }]
    end
  end

  # Alguma consulta do card recebe CPF ou CNPJ. São esses parâmetros (`Premium::Parametros::CPF` e `CNPJ`) que recusam o
  # dígito verificador errado antes da BigDataCorp, e por isso o número errado não conta; a placa, o endereço e o código
  # do CAR não têm essa conferência.
  def confere_documento?(fonte)
    documentos = [Parametros::CPF, Parametros::CNPJ]
    fonte.consultas.any? { |consulta| consulta.parametros.any? { |parametro| documentos.include?(parametro) } }
  end
end
