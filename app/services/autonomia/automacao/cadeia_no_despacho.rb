# Leva a cadeia de automações (Autonomia::Automacao::Cadeia) junto com o evento (#2414 F1).
#
# Os listeners das regras e do CRM rodam no EventDispatcherJob, em outra thread e depois do `Current.reset`. O
# evento sai com a lista de quem já rodou e o job a devolve enquanto os listeners trabalham.
module Autonomia::Automacao::CadeiaNoDespacho
  CHAVE = :autonomia_cadeia

  # Só o despacho assíncrono: os listeners síncronos rodam na mesma thread, com a cadeia ainda no lugar.
  module Despacho
    def dispatch(event_name, timestamp, data)
      return super unless Autonomia::Automacao::Cadeia.ativa? && data.is_a?(Hash)

      super(event_name, timestamp, data.merge(CHAVE => Autonomia::Automacao::Cadeia.origens))
    end
  end

  module Job
    def perform(event_name, timestamp, data)
      cadeia = data.is_a?(Hash) ? data[CHAVE] : nil
      return super if cadeia.blank?

      Autonomia::Automacao::Cadeia.restaurada(cadeia) { super }
    end
  end
end
