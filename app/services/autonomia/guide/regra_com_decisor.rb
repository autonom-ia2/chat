# #858 — automação com Decisor que fica LIGADA depois do pedido do Guia age sozinha em toda mensagem
# nova: pergunta ao Jev, manda mensagem, move card. O desfazer apaga a regra, não o que ela já fez.
# Então criar ligada (a regra nasce ligada quando o corpo não diz), ligar, ou pôr o Decisor numa regra
# ligada não tem desfazer e passa pela confirmação da pessoa (`Acoes#desfazivel?`). É isto que garante
# "só liga depois que a pessoa aprova o teste" — não o texto do manual.
class Autonomia::Guide::RegraComDecisor
  ACOES = ['POST automation_rules', 'PATCH automation_rules/:id'].freeze

  def initialize(account)
    @account = account
  end

  def fica_ligada?(acao, dados)
    return false if dados.nil? || ACOES.exclude?(acao)

    corpo = (dados[:corpo] || {}).to_h.with_indifferent_access
    regra = acao.start_with?('PATCH') ? regra_alterada(dados) : nil
    ligada?(corpo, regra) && com_decisor?(passos(corpo, regra))
  end

  private

  def passos(corpo, regra)
    corpo.key?(:actions) ? corpo[:actions] : regra&.actions
  end

  def ligada?(corpo, regra)
    return ActiveModel::Type::Boolean.new.cast(corpo[:active]) == true if corpo.key?(:active)

    regra.nil? || regra.active?
  end

  def com_decisor?(passos)
    Array(passos).any? { |passo| passo.to_h.with_indifferent_access[:action_name] == ::Autonomia::Decisores::PASSO }
  end

  def regra_alterada(dados)
    @account.automation_rules.find_by(id: (dados[:caminho] || {}).to_h.with_indifferent_access[:id])
  end
end
