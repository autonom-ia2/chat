# O QUE CADA CONSULTA DA COTAÇÃO GRAVA NO HANDLE, E QUANDO A CONSULTA SEGUINTE VEM LOGO (fatia 2 do #420).
#
# Separado da ferramenta pelo mesmo motivo de `Fecho` e `Comparativo`: a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Resultado
  extend ActiveSupport::Concern

  # O resultado de cada seguradora desta cotação (`Insurance::ResultadoPorSeguradora`), gravado em toda
  # consulta. É chave da FERRAMENTA: não está em `AsyncRunJob::MARCAS`, então viaja no handle que a
  # ferramenta recebe e é regravada pelo `record_attempt!` do fim da passada, como `seguradoras_acionadas`.
  RESULTADO_KEY = 'resultado_por_seguradora'.freeze
  # Os códigos de cada lote de preço, pela identidade da entrega do lote (`ToolRun#delivery_token`), gravados na
  # passada que emite o lote (quarta rodada de revisão). É por eles que a ferramenta da Lia sabe quais preços
  # ainda estão a caminho do cliente (`Insurance::ResultadoDaCotacao#a_caminho`). Chave da ferramenta, como a de cima.
  LOTES_KEY = 'codigos_por_lote_de_preco'.freeze

  class_methods do
    # -> este handle tem ao menos uma seguradora com preço guardado? Lido sem instância por
    # `ToolRun#resultado_obtido?`.
    def resultado_guardado?(handle)
      ::Autonomia::Insurance::ResultadoPorSeguradora.com_preco?(handle.to_h[RESULTADO_KEY])
    end
  end

  private

  # As três chaves que toda consulta grava: a união das acionadas, a leitura assentada e a união do
  # resultado por seguradora com as ofertas desta leitura.
  def marcas_da_leitura(result, leitura, handle)
    { self.class::ACIONADAS_KEY => acionadas(leitura, handle),
      self.class::LEITURA_ASSENTADA_KEY => leitura.assentada,
      RESULTADO_KEY => ::Autonomia::Insurance::ResultadoPorSeguradora.unir(handle[RESULTADO_KEY], result.to_h['offers']) }
  end

  # -> o handle com os códigos deste lote de preço sob a identidade da entrega dele. Sem execução não há
  # identidade, e o handle volta como veio.
  def lote_de_preco(handle, texto, codigos)
    token = token_da_entrega(texto)
    return handle if token.blank?

    handle.merge(LOTES_KEY => handle[LOTES_KEY].to_h.merge(token => codigos))
  end

  # A passada que não fechou a cotação. `handle` é o que a passada recebeu. `confirmar_logo` é verdade
  # quando a próxima leitura, repetindo esta, fecha a cotação (`QuoteOffers#confirma_na_proxima?`).
  def em_andamento(deliveries, next_handle, leitura, handle)
    confirmar = leitura.confirma_na_proxima?(handle[self.class::ACIONADAS_KEY])
    progress_class.running(deliveries: deliveries, handle: next_handle, confirmar_logo: confirmar)
  end
end
