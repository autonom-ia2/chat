# A PORTA POR AGENTE das ferramentas do Seguro Viagem Universal (#3211). Quem as recebe é só o agente contratado do
# catálogo cujo modelo as lista (`Contratados.ferramentas`) E cujo acesso à seguradora foi conferido (`ok`). Agente comum
# com o slug gravado em `native_tool_slugs`, ou contratado sem acesso, não as recebe: oferecer e falhar na frente do
# cliente é pior que não oferecer. Estendido nas três classes (`extend`), que dão o próprio `slug`.
module Autonomia::Agents::Tools::Native::SeguroViagem::PortaDoContratado
  def available_for?(agent)
    return false unless agent.respond_to?(:contratado?) && agent.contratado?
    return false unless ::Autonomia::Agents::Contratados.ferramentas(agent)&.include?(slug)

    acesso = agent.acesso_da_seguradora
    !acesso.nil? && acesso.ok?
  end
end
