# #2858 F3 — o agente já nasce com as ferramentas prontas. No turno de criação, o Construtor recebe como DADO as prontas
# liberadas para a conta (bloco de contexto, nunca na instrução-mãe: o prefixo em cache segue igual entre as contas) e
# escolhe, no campo `ferramentas_prontas` do schema, as que o agente precisa. Lista vazia é a saída "nenhuma combina".
# Quem decide é o modelo, pelo sentido do agente; o código só filtra pelo que a conta tem liberado.
#
# O campo é o mesmo em todas as contas (o schema é estrito e fica no prefixo em cache): o enum leva todas as chaves do
# catálogo, e sem a flag do Construtor nada é guardado. As escolhidas vão para o state da thread e para o config do
# agente (`ferramentas_sugeridas`); quem inclui é a Confira, no "Começar", pelo endpoint da vitrine (pessoa real e
# permissão dela). A Lia (`insurance_quote`) nunca recebe pronta.
module Autonomia::Agents::Builder::ProntasSugeridas
  CAMPO = 'ferramentas_prontas'.freeze
  DESCRIPTION =
    'Chaves das ferramentas prontas do bloco FERRAMENTAS PRONTAS que este agente precisa para atender bem: so as que ' \
    'tem relacao direta com o que ele faz (ex.: o atendimento de seguro auto precisa do valor do carro; uma padaria ' \
    'nao precisa de nenhuma). Na duvida, deixe de fora. Lista vazia quando nenhuma combina ou quando nao ha o bloco.'.freeze
  TITULO = 'FERRAMENTAS PRONTAS (contexto interno da plataforma, nao e fala do usuario): consultas que o agente pode ' \
           'ganhar ja na criacao. Escolha no campo ferramentas_prontas so as que o agente precisa.'.freeze

  module_function

  def schema
    { type: 'array', items: { type: 'string', enum: Autonomia::FerramentasProntas::Catalogo.chaves }, description: DESCRIPTION }
  end

  def ligado?(account)
    Autonomia::FerramentasProntas.construtor?(account)
  end

  # O bloco de contexto do turno de criação, ou nil (flag desligada ou nenhuma fonte liberada).
  def contexto(account)
    return unless ligado?(account)

    linhas = Autonomia::FerramentasProntas.disponiveis(account).map { |fonte| "- #{fonte.chave}: #{fonte.nome}. #{fonte.descricao}" }
    return if linhas.empty?

    [TITULO, *linhas].join("\n")
  end

  # As chaves que o modelo escolheu, só as liberadas para a conta, sem repetir, na ordem do catálogo.
  def filtrar(account, parsed)
    return [] unless ligado?(account)

    escolhidas = Array(parsed.to_h[CAMPO]).map(&:to_s)
    Autonomia::FerramentasProntas.disponiveis(account).map(&:chave) & escolhidas
  end
end
