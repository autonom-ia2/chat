# #2858 F3 — o agente já nasce com as ferramentas prontas. No turno de criação, o Construtor recebe como DADO as prontas
# liberadas para a conta (bloco de contexto, nunca na instrução-mãe: o prefixo em cache segue igual entre as contas) e
# escolhe, no campo `ferramentas_prontas` do schema, as que o agente precisa. Lista vazia é a saída "nenhuma combina".
# Quem decide é o modelo, pelo sentido do agente; o código só filtra pelo que a conta tem liberado.
#
# O campo é o mesmo em todas as contas (o schema é estrito e fica no prefixo em cache): o enum leva todas as chaves do
# catálogo que a vitrine oferece (fora as de uso interno), e sem a flag do Construtor nada é guardado. As escolhidas
# vão para o state da thread e para o config do agente: as MAXIMO primeiras em `ferramentas_sugeridas` (o "já vem com"
# da Confira), as seguintes, até MAX_TAMBEM, em `ferramentas_tambem` (a linha "Também combina", com "Incluir também").
# Quem inclui é a Confira, no "Começar", pelo endpoint da vitrine (pessoa real e permissão dela). A Lia
# (`insurance_quote`) nunca recebe pronta.
module Autonomia::Agents::Builder::ProntasSugeridas
  CAMPO = 'ferramentas_prontas'.freeze
  # Teto de prontas no nascimento: o Confira mostra uma linha por ferramenta, e mais que isso vira lista longa para
  # quem nao e de tecnologia. As seguintes, ate MAX_TAMBEM, ficam numa linha so ("Tambem combina"), a um toque.
  MAXIMO = 4
  MAX_TAMBEM = 4
  DESCRIPTION =
    'Chaves das ferramentas prontas do bloco FERRAMENTAS PRONTAS que um atendente experiente deste ramo usaria no ' \
    'processo inteiro do atendimento descrito: entender o pedido, cotar, conferir os dados e documentos de quem ' \
    'contrata, localizar o endereco do risco e calcular prazos. Pense no passo a passo real desse atendimento, alem do ' \
    "que o dono citou. Escolha no maximo #{MAXIMO + MAX_TAMBEM}, da mais usada para a menos usada, e deixe de fora as que nao " \
    'servem a nenhum passo desse atendimento. Lista vazia quando nenhuma serve ou quando nao ha o bloco.'.freeze
  TITULO = 'FERRAMENTAS PRONTAS (contexto interno da plataforma, nao e fala do usuario): consultas que o agente pode ' \
           'ganhar ja na criacao. Escolha no campo ferramentas_prontas so as que o agente precisa.'.freeze

  module_function

  def schema
    { type: 'array', items: { type: 'string', enum: Autonomia::FerramentasProntas::Catalogo.chaves_da_vitrine }, description: DESCRIPTION }
  end

  def ligado?(account)
    Autonomia::FerramentasProntas.construtor?(account)
  end

  # O bloco de contexto do turno de criação, ou nil (flag desligada ou nenhuma fonte liberada).
  def contexto(account)
    return unless ligado?(account)

    linhas = Autonomia::FerramentasProntas.da_vitrine(account).map { |fonte| "- #{fonte.chave}: #{fonte.nome}. #{fonte.descricao}" }
    return if linhas.empty?

    [TITULO, *linhas].join("\n")
  end

  # As chaves que o modelo escolheu, só as liberadas para a conta e fora das que a pessoa já dispensou (`fora`, de um
  # rascunho que volta à criação), sem repetir, na ordem do array devolvido pelo modelo, que o campo pede da mais usada
  # para a menos usada: { sugeridas: as MAXIMO primeiras, tambem: as seguintes, até MAX_TAMBEM }.
  def dividir(account, parsed, fora: [])
    return { sugeridas: [], tambem: [] } unless ligado?(account)

    liberadas = Autonomia::FerramentasProntas.da_vitrine(account).map(&:chave) - Array(fora)
    chaves = Array(parsed.to_h[CAMPO]).map(&:to_s).uniq.select { |chave| liberadas.include?(chave) }
    { sugeridas: chaves.first(MAXIMO), tambem: chaves.drop(MAXIMO).first(MAX_TAMBEM) }
  end
end
