# As contas pequenas do painel de desempenho (#2251), iguais às do adaptador do protótipo (bin/contrato.py), para a
# tela, o PDF e a planilha baterem com o que foi aprovado.
module Autonomia::Desempenho::Conta
  module_function

  # Porcentagem com 1 casa, metade para cima (6,25 -> 6,3). Base 0 ou nula -> nil (nunca 0 no lugar de "não dá").
  def pct(parte, total)
    return nil if total.nil? || total.zero?

    (BigDecimal(100) * parte / total).round(1, BigDecimal::ROUND_HALF_UP).to_f
  end

  # Chave de ordenação de um id de texto: nil ordena como o texto "None" (o protótipo usava str(id)).
  def texto(valor)
    valor.nil? ? 'None' : valor.to_s
  end

  # [[id, vezes]] da mais frequente para a menos, desempate pelo id.
  def contagem(valores)
    valores.tally.sort_by { |id, vezes| [-vezes, texto(id)] }
  end

  # Os marcos que fazem uma procura chegar a uma etapa do funil: os da etapa; sem lista, o próprio id da etapa.
  # Regra única do agregador, da planilha e da tela (desempenhoContrato.js, marcosDaEtapa).
  def marcos_da_etapa(etapa)
    marcos = Array(etapa['marcos'])
    marcos.empty? ? [etapa['id']] : marcos
  end

  # 'AAAA-MM-DDTHH:MM' -> 'AAAA-MM-DD' (o texto já está no fuso da conta).
  def dia_de(data_hora)
    data_hora.to_s[0, 10]
  end

  def data(data_hora)
    Date.iso8601(dia_de(data_hora))
  end

  def hora(data_hora)
    data_hora.to_s[11, 2].to_i
  end
end
