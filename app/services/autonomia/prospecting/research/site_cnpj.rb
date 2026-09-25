# O CNPJ que o site do lead mostra, lido pela própria pesquisa (#679). Porta collectSiteSignal do Orth
# (company-owner/pipeline.ts e site-scraper.ts): o sinal do site é coletado dentro da pesquisa, sem depender do
# enriquecimento (EnrichLeadJob) ter terminado antes. Ao fim da busca os dois jobs entram juntos na fila, e esperar o
# enriquecimento deixava a corroboração e a recusa por conflito desligadas justo no primeiro passe de todo lead.
#
# Fonte só do site, nunca do que a pesquisa gravou: a página é baixada pelo WebsiteScraper (SafePageFetcher, guarda de
# destino e IP fixo). Se a página não abre, vale o CNPJ que o raspador guardou em enriched_data['cnpj'], chave que só o
# enriquecimento escreve a partir do site. enriched_cnpj não é lido aqui: é coluna de exibição.
#
# Devolve o texto do CNPJ como o site mostrou, ou nil. A validação pelo dígito fica com quem usa (Research::Cnpj).
module Autonomia::Prospecting::Research::SiteCnpj
  module_function

  def read(lead)
    return nil if lead.website.blank?

    scraped = Autonomia::Prospecting::WebsiteScraper.new(url: lead.website).perform.data
    return scraped['cnpj'].presence if scraped['error'].blank?

    lead.enriched_data.to_h['cnpj'].presence
  end
end
