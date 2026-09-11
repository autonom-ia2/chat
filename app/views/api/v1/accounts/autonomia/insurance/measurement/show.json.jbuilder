json.payload do
  json.account_id @medida[:conta_id]
  # A JANELA QUE A CONSULTA USOU, de volta. Sem ela, quem cobra não sabe de que período é o número —
  # e "os últimos 30 dias" muda de significado a cada dia.
  json.from @medida[:inicio].iso8601
  json.to @medida[:fim].iso8601
  # O FUSO EM QUE AS DATAS FORAM LIDAS: o da corretora (`reporting_timezone`) quando ela configurou
  # um. "Setembro" dela termina às 23h59 dela, não às nossas.
  json.timezone @medida[:fuso]

  # OS DOIS NÚMEROS. Uma cotação aciona todas as seguradoras habilitadas (dezessete nas três cotações
  # reais de 11/09/2026): contar só execuções não diz nada sobre o que foi consumido.
  json.quotes @medida[:cotacoes]
  json.insurers_called @medida[:seguradoras_acionadas]
  json.insurers_with_price @medida[:seguradoras_com_preco]
  # TERMO 3: quantas COTAÇÕES viraram proposta individual — uma cotação com duas propostas é UMA.
  # A soma dos códigos (`proposals_issued`) fica em separado e não é a linha da fatura. Entrega 8: a
  # ferramenta de proposta por seguradora ainda não existe, e os dois contadores já contam.
  json.quotes_with_proposal @medida[:cotacoes_com_proposta]
  json.proposals_issued @medida[:propostas_emitidas]

  # O QUE A MEDIDA NÃO SABE, DITO EM SEPARADO — nunca somado no total.
  json.unknown do
    json.quotes_without_measure @medida[:cotacoes_sem_medida]
    json.quotes_without_confirmation @medida[:cotacoes_sem_confirmacao]
    json.quotes_possibly_duplicated @medida[:cotacoes_possivelmente_duplicadas]
  end
end
