# A PORTA POR AGENTE das ferramentas do Seguro Viagem Universal (#3211). Quem as recebe é só o agente contratado do
# catálogo cujo modelo as lista (`Contratados.ferramentas`), com o modelo disponível na conta no turno
# (`Contratados.disponivel?`: a flag, as prontas, o cofre e a chave de IA da própria conta) E cujo acesso à seguradora
# foi conferido (`ok`). Agente comum com o slug gravado em `native_tool_slugs`, contratado com o modelo desligado ou
# sem acesso não as recebe: oferecer e falhar na frente do cliente é pior que não oferecer. Incluído no `class << self`
# das três classes (`include`), que dão o próprio `slug`.
module Autonomia::Agents::Tools::Native::SeguroViagem::PortaDoContratado
  def available_for?(agent)
    return false unless agent.respond_to?(:contratado?) && agent.contratado?
    return false unless ::Autonomia::Agents::Contratados.ferramentas(agent)&.include?(slug)
    return false unless ::Autonomia::Agents::Contratados.disponivel?(agent.account, agent.marca_do_contratado['modelo'])

    acesso = agent.acesso_da_seguradora
    !acesso.nil? && acesso.ok?
  end
end
