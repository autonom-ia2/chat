# Os passos novos da Automação livre que rodam na hora (#2931–#2936, épico #2414): "fazer para cada um de uma lista"
# (#2932, PassoRepetirLista), "usar outra automação" (#2933, PassoUsarBloco) e "buscar informação em outro sistema"
# (#2934, PassoConsultar). Os outros três, que perguntam e esperam a resposta (aprovação, reunião e pesquisa), ficam em
# PassosQueEsperam, com a mesma flag.
#
# Só com a flag `automacao_passos_novos`: desligada, o salvar recusa a receita que tem um deles e o motor para a execução
# que chega num deles (BlocoNoExecutor#passo_novo). É o rollback.
module Autonomia::Automacao::PassosNovos
  FLAG = 'automacao_passos_novos'.freeze
  TIPOS = %w[repetir_lista usar_bloco consultar].freeze

  # O que o validador de cada passo recebe da Receita: a conta, quem salva (nil na leitura sem pessoa), o tipo do alvo em
  # que o passo roda (Receita#alvo) e se ele está no galho de uma execução filha (`dentro`: o "em outro registro" e o
  # "para cada").
  Conferencia = Data.define(:conta, :account_user, :alvo, :dentro)

  module_function

  def do_tipo?(passo) = TIPOS.include?(passo['tipo'])

  def ligados?(conta) = conta.present? && conta.feature_enabled?(FLAG)

  def problemas_ao_salvar(passo, conferencia)
    return [I18n.t('autonomia.automacao.receita.passos_novos_desligados', passo: passo['id'])] unless ligados?(conferencia.conta)

    case passo['tipo']
    when 'repetir_lista' then ::Autonomia::Automacao::PassoRepetirLista.problemas_ao_salvar(passo, conferencia)
    when 'usar_bloco' then ::Autonomia::Automacao::PassoUsarBloco.problemas_ao_salvar(passo, conferencia)
    else ::Autonomia::Automacao::PassoConsultar.problemas_ao_salvar(passo, conferencia)
    end
  end
end
