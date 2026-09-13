# O MOTIVO DE QUEM NÃO COTOU QUE PODE ORIENTAR A FALA DA LIA (fatia 2 do #420, regra registrada na issue
# em 13/09/2026).
#
# O conector manda `reason: { kind, text }` para cada seguradora que não cotou (autonomia-adapters#60). A
# revisão daquela PR mostrou que o `kind` erra: "Senha expirou. Declinando cálculo." sai `risco`,
# "Sistema indisponível: sessão expirada, faça login novamente." sai `passageiro`, e "Usuário
# fulano@corretora.com.br bloqueado." sai `outro`. Por isso o `kind` sozinho não libera o texto.
#
# `permitido` devolve o texto só quando o `kind` é `risco` E o texto não casa nenhum padrão de
# `TERMOS_DE_CONTA` nem de `VALORES`. Em qualquer outro caso devolve nil, e a Lia só pode dizer que a
# seguradora não fez proposta.
#
# A LISTA É DE RADICAIS E VAI ALÉM DOS NOVE TERMOS DA REGRA (login, senha, sessão, token, usuário, acesso,
# permissão, corretor, credencial). A revisão da fatia 2 passou dez textos pelo classificador real do
# conector que saem `risco` e falam da conta da corretora com outras palavras ("Produtor não credenciado",
# "Sistema deslogado", "Código SUSEP inválido", "Corretagem acima do limite"). O que a lista não conhece
# ainda passa: ela recusa pelo vocabulário, não pelo sentido.
#
# `VALORES` recusa valor escrito como número (com `R$`, "reais", "mil", centavos, milhar ou quatro
# dígitos fora de colchete): o texto vai ao modelo, e valor ao cliente é escrito pelo código. O código do
# portal entre colchetes ("[2005]") e o de até três dígitos ("400 - Restrição técnica") passam.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  # O teto do texto no conector (`quote-reason.ts`, `TETO_DO_TEXTO`).
  TETO_DO_TEXTO = 300
  # Cada padrão, casado no texto sem acento e em minúsculas.
  TERMOS_DE_CONTA = {
    # login, logar, logado, logou, logue, logon; deslogado, relogar; "log in".
    'login' => /\b(?:des|re)?log(?:in|on|ar|ad|ou|ue)|\blog\s+in\b/,
    'senha' => /\bsenhas?\b/,
    'sessão' => /\bsess(?:ao|oes)\b/,
    'token' => /\btokens?\b/,
    'usuário' => /\busuari/,
    # "acessório" não casa.
    'acesso' => /\bacess(?!ori)/,
    # "permitida" e "permissionário" não casam.
    'permissão' => /\bpermiss(?!ionari)/,
    # corretor, corretora, corretores; corretagem.
    'corretor' => /\bcorretor|\bcorretag/,
    # credencial, credenciais, credenciado, credenciamento.
    'credencial' => /\bcredenci/,
    # autenticação, reautenticar.
    'autenticação' => /autentic/,
    'autorização' => /\bautoriz/,
    'habilitação' => /\bhabilit/,
    'produtor' => /\bprodutor/,
    'SUSEP' => /\bsusep\b/,
    'cadastro' => /\bcadastr/,
    'comissão' => /\bcomiss/,
    'certificado' => /\bcertificad/,
    'bloqueado' => /\bbloquead/,
    'e-mail' => /@/,
    'link' => %r{https?://|\bwww\.}
  }.freeze
  VALORES = {
    'R$' => /r\$/,
    'reais' => /\breais\b/,
    'mil' => /\d\s*mil\b/,
    'centavos' => /\d,\d{2}\b/,
    'milhar' => /\d{1,3}(?:\.\d{3})+/,
    'quatro dígitos' => /(?<!\[)\b\d{4,}\b(?!\])/
  }.freeze

  module_function

  # -> o texto do portal, aparado, quando ele pode orientar a fala da Lia; nil quando não pode.
  def permitido(reason)
    return nil unless reason.is_a?(Hash) && reason['kind'] == KIND_PERMITIDO

    texto = reason['text']
    return nil unless texto.is_a?(String)

    texto = texto.strip
    return nil if texto.empty? || texto.length > TETO_DO_TEXTO || proibido?(texto)

    texto
  end

  # -> o texto, sem acento e em minúsculas, casa algum padrão de `TERMOS_DE_CONTA` ou de `VALORES`?
  def proibido?(texto)
    alvo = ActiveSupport::Inflector.transliterate(texto).downcase
    TERMOS_DE_CONTA.merge(VALORES).each_value.any? { |padrao| alvo.match?(padrao) }
  end
end
