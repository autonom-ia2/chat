# O que um pedido de escrita faz e que o desfazer não alcança, além das rotas de `Acoes::SEM_DESFAZER`.
# `Acoes#desfazivel?` pergunta aqui; cada regra mora na própria classe.
module Autonomia::Guide::SemVolta
  module_function

  # `conferencia` é a `Formatos::Conferencia` do pedido (nil sem dados).
  def pelo_que_faz?(account, acao, dados, conferencia)
    # #3106: as regras leem o corpo como a plataforma o recebe (envelope aberto ou fechado pela conferência).
    # Lendo o corpo cru, `{automation_rule: {active: true}}` passava por desligado e ia ligado.
    dados = dados&.merge(corpo: conferencia.corpo)
    # #858: regra com Decisor que fica ligada. #2889: ajuste numa automação do motor novo ligada vale na hora.
    # #3106: trocar a credencial do canal da caixa. E o que cai num nó `x-sem-volta` do esquema.
    ::Autonomia::Guide::RegraComDecisor.new(account).fica_ligada?(acao, dados) ||
      ::Autonomia::Guide::MotorNovo.new(account).ajusta_ligada?(acao, dados) ||
      ::Autonomia::Guide::CredencialDaCaixa.troca?(acao, dados) ||
      conferencia&.sem_volta? || false
  end
end
