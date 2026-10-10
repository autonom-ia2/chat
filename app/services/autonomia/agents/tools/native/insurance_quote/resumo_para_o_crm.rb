# A COTAÇÃO EM UMA FRASE PARA O CRM (#1146): o ramo, o bem, o menor prêmio e quantas seguradoras cotaram. A IA do card
# lê isso com as mensagens e preenche os campos que a corretora criou ("Valor cotado", "Seguradora"...). Só cotação
# com algum preço. Separado da ferramenta, que está no teto de linhas.
#
# O MENOR PRÊMIO SEGUE O CRITÉRIO DA LISTA AO CLIENTE (`QuoteOffers#quoted`, entrega 13): período diferente não se
# compara pelo número cru. O menor TOTAL; sem nenhum total, o menor mensal, dito "por mês"; preço sem período não entra
# na comparação. Senão R$ 351,59 por mês "ganhava" de R$ 1.321,25 no total e virava o valor cotado do card.
module Autonomia::Agents::Tools::Native::InsuranceQuote::ResumoParaOCrm
  def resumo_para_o_crm(run)
    com_preco = ofertas_com_preco(run)
    melhor, periodo = melhor_oferta(com_preco)
    return if melhor.nil?

    "Cotação de seguro #{bem_cotado(run)}: menor prêmio #{::Autonomia::Insurance::PremiumText.money(melhor.dig('premio', 'amount'))} " \
      "#{periodo} (#{melhor['nome']}); #{com_preco.size} seguradora(s) com preço."
  end

  private

  def ofertas_com_preco(run)
    run.handle.to_h[self::Resultado::RESULTADO_KEY].to_h.values.select do |oferta|
      oferta['desfecho'] == ::Autonomia::Insurance::ResultadoPorSeguradora::COM_PRECO && oferta.dig('premio', 'amount').present?
    end
  end

  # -> [oferta, 'no total' | 'por mês'] ou nil quando nenhuma tem período.
  def melhor_oferta(ofertas)
    mensais, outras = ofertas.partition { |oferta| ::Autonomia::Insurance::PremiumText.new(oferta['premio']).mensal? }
    totais = outras.reject { |oferta| ::Autonomia::Insurance::PremiumText.new(oferta['premio']).indefinido? }
    grupo, periodo = totais.any? ? [totais, 'no total'] : [mensais, 'por mês']
    melhor = grupo.min_by { |oferta| oferta.dig('premio', 'amount').to_f }
    melhor && [melhor, periodo]
  end

  def bem_cotado(run)
    ramo = run.handle.to_h['produto'].presence || ::Autonomia::Insurance::Faixa.ramo(run.faixa)
    [ramo, run.arguments.to_h['item'].to_s.squish.presence].compact.join(' — ')
  end
end
