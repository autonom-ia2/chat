# Leva a cadeia de automações (Autonomia::Automacao::Cadeia) junto com o evento (#2414 F1).
#
# Os listeners das regras e do CRM rodam no EventDispatcherJob, em outra thread e depois do `Current.reset`. O
# evento sai com a lista de quem já rodou e a conta, e o job a devolve enquanto os listeners trabalham, se a conta
# ainda tiver a flag. Os listeners nunca veem a chave.
module Autonomia::Automacao::CadeiaNoDespacho
  CHAVE = :autonomia_cadeia

  # Só o despacho assíncrono: os listeners síncronos rodam na mesma thread, com a cadeia ainda no lugar.
  module Despacho
    def dispatch(event_name, timestamp, data)
      cadeia = Autonomia::Automacao::Cadeia
      return super unless cadeia.ativa? && data.is_a?(Hash)

      super(event_name, timestamp, data.merge(CHAVE => { 'conta' => cadeia.conta_id, 'origens' => cadeia.origens }))
    end
  end

  module Job
    def perform(event_name, timestamp, data)
      return super unless data.is_a?(Hash) && data.key?(CHAVE)

      cadeia = data[CHAVE].to_h
      Autonomia::Automacao::Cadeia.retomar(cadeia['origens'], Account.find_by(id: cadeia['conta'])) do
        super(event_name, timestamp, data.except(CHAVE))
      end
    end
  end
end
