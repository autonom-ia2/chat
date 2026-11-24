# #3099: qual das duas versões foi melhor, pela mesma régua que a tela mostra (CampaignResult/vencedora.js e a régua da
# F2, comparacaoComControle.js). A conta sai dos números redondos da tela ("De cada 100 que receberam, 12
# responderam"): se a tela diz 12 e 12, não há vencedora.
# - Menos de MINIMO_DE_RESULTADOS respostas (ou compras) somadas nas duas: cedo demais, nil (empate);
# - "De cada 100", ou "de cada 1.000" quando algum lado tem menos de 1 em 100 (senão vira 0);
# - Até 15% de diferença (QUASE_IGUAL) é empate.
# O empate segue a versão 1, quem decide é CampaignJourney::DuasVersoes::Escolha.
module CampaignJourney::DuasVersoes::Vencedora
  MINIMO_DE_RESULTADOS = 10
  QUASE_IGUAL = 1.15

  module_function

  # `versao1`, `versao2`: { receberam:, responderam:, compraram: }. Devolve 1, 2 ou nil (empate ou cedo demais).
  def melhor(versao1, versao2, criterio)
    campo = criterio.to_s == 'compras' ? :compraram : :responderam
    return if versao1[campo].to_i + versao2[campo].to_i < MINIMO_DE_RESULTADOS

    um, dois = de_cada(versao1, versao2, campo)
    return if um == dois

    vencedora = dois > um ? 2 : 1
    menor, maior = [um, dois].minmax
    return vencedora if menor.zero?

    maior.fdiv(menor) >= QUASE_IGUAL ? vencedora : nil
  end

  # [n da versão 1, n da versão 2] de cada 100 (ou 1.000), em inteiros, como emGente da tela.
  def de_cada(versao1, versao2, campo)
    lados = [versao1, versao2].map { |versao| [versao[campo].to_i, versao[:receberam].to_i] }
    escala = lados.any? { |sim, total| sim.positive? && taxa(sim, total) * 100 < 1 } ? 1000 : 100
    lados.map { |sim, total| sim.positive? ? [(taxa(sim, total) * escala).round, 1].max : 0 }
  end

  def taxa(sim, total)
    total.positive? ? sim.fdiv(total) : 0
  end
end
