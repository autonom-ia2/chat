# O gatilho "a pessoa completou o cartão fidelidade" (#3100, Gatilhos `contato.completou_cartao_fidelidade`). Quem
# mexe no saldo (a compra, o presente, o ajuste) chama depois do commit, com as pessoas que cruzaram a meta.
#
# Uma execução por cartão completado (decisão do Rodrigo, 24/11): a marca é a pessoa e o número do cartão, contado
# pelos carimbos ganhos (compra, presente e ajuste, menos estorno) dividido pela meta. A venda desfeita e fechada de
# novo volta ao mesmo número e não avisa outra vez; o prêmio e o vencimento não descontam, então completar de novo
# depois deles é o cartão seguinte. Só consulta as automações quando há alguém, e só segue quando alguma automação
# ligada usa o gatilho.
module Fidelidade::CartaoCompleto
  GATILHO = 'contato.completou_cartao_fidelidade'.freeze

  module_function

  # `completos`: [[contato, movimento que completou]].
  def avisar(account, completos)
    return if completos.blank? || !::Autonomia::Automacao::Escuta.automacoes_do_gatilho(account.id, GATILHO).exists?

    completos.each do |contato, movimento|
      ::Autonomia::Automacao::Escuta.comecar(contato, GATILHO, evento: "#{GATILHO}:#{contato.id}:#{cartao(movimento)}")
    end
  end

  GANHOS = [Fidelidade::Movimento::COMPRA, Fidelidade::Movimento::PRESENTE, Fidelidade::Movimento::AJUSTE,
            Fidelidade::Movimento::ESTORNO].freeze

  # O número do cartão que a pessoa completou: 1 no primeiro, 2 no segundo, e assim por diante.
  def cartao(movimento)
    programa = movimento.programa
    Fidelidade::Movimento.da_pessoa(programa, movimento.contact_id).where(tipo: GANHOS).sum(:quantos) / programa.meta
  end
end
