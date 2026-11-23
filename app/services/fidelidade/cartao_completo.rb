# O gatilho "a pessoa completou o cartão fidelidade" (#3100, Gatilhos `contato.completou_cartao_fidelidade`). Quem
# mexe no saldo (a compra, o presente, o ajuste) chama depois do commit, com as pessoas que cruzaram a meta.
#
# Uma execução por cartão completado: a marca é a pessoa e o movimento que completou. O mesmo movimento nunca dispara
# duas vezes; dar o prêmio e completar de novo é outro movimento, outra vez. Só consulta as automações quando há
# alguém, e só segue quando alguma automação ligada usa o gatilho.
module Fidelidade::CartaoCompleto
  GATILHO = 'contato.completou_cartao_fidelidade'.freeze

  module_function

  # `completos`: [[contato, movimento que completou]].
  def avisar(account, completos)
    return if completos.blank? || !::Autonomia::Automacao::Escuta.automacoes_do_gatilho(account.id, GATILHO).exists?

    completos.each do |contato, movimento|
      ::Autonomia::Automacao::Escuta.comecar(contato, GATILHO, evento: "#{GATILHO}:#{contato.id}:#{movimento.id}")
    end
  end
end
