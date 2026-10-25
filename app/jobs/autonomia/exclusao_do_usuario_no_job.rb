# Exclusão do usuário (#2135): quando a pessoa ainda tem linha que espera decisão (Autonomia::ExclusaoDoUsuario), o
# destroy! é recusado. Repetir o job não muda nada até a decisão, então ele termina sem erro e sem nova tentativa: o
# aviso com o id e as tabelas já ficou no log. A pessoa continua sem conta nenhuma (o vínculo já saiu antes do job).
module Autonomia::ExclusaoDoUsuarioNoJob
  def perform(object, *)
    super
  rescue ActiveRecord::RecordNotDestroyed => e
    raise unless object.is_a?(User) && e.record == object && object.errors.of_kind?(:base, Autonomia::ExclusaoDoUsuario::ERRO)

    nil
  end
end
