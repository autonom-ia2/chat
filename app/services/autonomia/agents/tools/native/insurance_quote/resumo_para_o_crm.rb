# A COTAÇÃO EM UMA FRASE PARA O CRM (#1146): o ramo, o bem, o menor prêmio e quantas seguradoras cotaram. A IA do card
# lê isso com as mensagens e preenche os campos que a corretora criou ("Valor cotado", "Seguradora"...). Só cotação
# terminada com algum preço. Separado da ferramenta, que está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::ResumoParaOCrm
  def resumo_para_o_crm(run)
    com_preco = ofertas_com_preco(run)
    return if com_preco.empty?

    melhor = com_preco.min_by { |oferta| oferta.dig('premio', 'amount').to_f }
    "Cotação de seguro #{bem_cotado(run)}: menor prêmio #{::Autonomia::Insurance::PremiumText.money(melhor.dig('premio', 'amount'))} " \
      "(#{melhor['nome']}); #{com_preco.size} seguradora(s) com preço."
  end

  private

  def ofertas_com_preco(run)
    run.handle.to_h[self::Resultado::RESULTADO_KEY].to_h.values.select do |oferta|
      oferta['desfecho'] == ::Autonomia::Insurance::ResultadoPorSeguradora::COM_PRECO && oferta.dig('premio', 'amount').present?
    end
  end

  def bem_cotado(run)
    ramo = run.handle.to_h['produto'].presence || ::Autonomia::Insurance::Faixa.ramo(run.faixa)
    [ramo, run.arguments.to_h['item'].to_s.squish.presence].compact.join(' — ')
  end
end
