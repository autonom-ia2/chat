# O QUE CADA CONSULTA DA COTAÇÃO GRAVA NO HANDLE, E QUANDO A CONSULTA SEGUINTE VEM LOGO (fatia 2 do #420).
#
# Separado da ferramenta pelo mesmo motivo de `Fecho` e `Comparativo`: a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Resultado
  extend ActiveSupport::Concern

  # O resultado de cada seguradora desta cotação (`Insurance::ResultadoPorSeguradora`), gravado em toda
  # consulta. É chave da FERRAMENTA: não está em `AsyncRunJob::MARCAS`, então viaja no handle que a
  # ferramenta recebe e é regravada pelo `record_attempt!` do fim da passada, como `seguradoras_acionadas`.
  RESULTADO_KEY = 'resultado_por_seguradora'.freeze

  class_methods do
    # -> este handle tem ao menos uma seguradora com preço guardado? Lido sem instância por
    # `ToolRun#resultado_obtido?`.
    def resultado_guardado?(handle)
      ::Autonomia::Insurance::ResultadoPorSeguradora.com_preco?(handle.to_h[RESULTADO_KEY])
    end
  end

  private

  # O que toda consulta grava: a união das acionadas, a leitura assentada, a união do resultado por
  # seguradora com as ofertas desta leitura, a união dos códigos de quem cotou (`DELIVERED_KEY`) e, quando
  # há, o motivo de cada preço sem período (`SEM_PERIODO_KEY`, acumulado entre consultas).
  def marcas_da_leitura(result, leitura, handle)
    marcas = { self.class::ACIONADAS_KEY => acionadas(leitura, handle),
               self.class::LEITURA_ASSENTADA_KEY => leitura.assentada,
               RESULTADO_KEY => ::Autonomia::Insurance::ResultadoPorSeguradora.unir(handle[RESULTADO_KEY], result.to_h['offers']),
               self.class::DELIVERED_KEY => cotaram(leitura, handle) }
    sem_periodo = leitura.sem_periodo
    return marcas if sem_periodo.empty?

    marcas.merge(self.class::SEM_PERIODO_KEY => handle[self.class::SEM_PERIODO_KEY].to_h.merge(sem_periodo))
  end

  def cotaram(leitura, handle)
    Array(handle[self.class::DELIVERED_KEY]).map(&:to_s) | leitura.quoted.map { |oferta| ::Autonomia::Insurance::QuoteOffers.code(oferta) }
  end

  # A passada que não fechou a cotação. `handle` é o que a passada recebeu. `confirmar_logo` é verdade
  # quando a próxima leitura, repetindo esta, fecha a cotação (`QuoteOffers#confirma_na_proxima?`).
  def em_andamento(next_handle, leitura, handle)
    confirmar = leitura.confirma_na_proxima?(handle[self.class::ACIONADAS_KEY])
    progress_class.running(handle: next_handle, confirmar_logo: confirmar)
  end
end
