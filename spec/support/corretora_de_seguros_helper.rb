# Marca a conta como nicho seguros e perfil corretora (#3269): o agente contratado só existe para esse segmento.
# Usa o setter do nicho (`Nicho.atribuir`), nunca `internal_attributes` na mão.
module CorretoraDeSegurosHelper
  def marcar_corretora!(conta, perfil: Autonomia::Agents::Nicho::PERFIL_PADRAO)
    Autonomia::Agents::Nicho.atribuir(conta, nicho: Autonomia::Agents::Nicho::SEGUROS, perfil: perfil)
    conta.save!
    conta
  end
end

RSpec.configure do |config|
  config.include CorretoraDeSegurosHelper
end
