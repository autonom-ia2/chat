# O MOTIVO DE QUEM NÃO COTOU QUE PODE ORIENTAR A FALA DA LIA (fatia 2 do #420, regra registrada na issue
# em 13/09/2026).
#
# O conector manda `reason: { kind, text }` para cada seguradora que não cotou (autonomia-adapters#60). A
# revisão daquela PR mostrou que o `kind` erra: "Senha expirou. Declinando cálculo." sai `risco`,
# "Sistema indisponível: sessão expirada, faça login novamente." sai `passageiro`, e "Usuário
# fulano@corretora.com.br bloqueado." sai `outro`. Por isso o `kind` sozinho não libera o texto.
#
# `permitido` devolve o texto só quando o `kind` é `risco` E o texto não tem termo de conta nem valor em
# reais. Em qualquer outro caso devolve nil, e a Lia só pode dizer que a seguradora não fez proposta.
#
# O QUE ESTE MÓDULO RECUSA ALÉM DA LISTA DA REGRA (login, senha, sessão, token, usuário, acesso,
# permissão, corretor, credencial): as formas verbais de login (logar, logado, logou, logue, logon),
# autenticação, endereço de e-mail (o achado P2-3 da revisão do conector) e valor em reais (o texto vai
# ao modelo, e valor em reais ao cliente é escrito pelo código).
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  # O teto do texto no conector (`quote-reason.ts`, `TETO_DO_TEXTO`).
  TETO_DO_TEXTO = 300
  # Cada termo, casado no texto sem acento e em minúsculas.
  TERMOS_DE_CONTA = {
    'login' => /\blog(?:in|on|ar|ad|ou|ue)/,
    'senha' => /\bsenhas?\b/,
    'sessão' => /\bsess(?:ao|oes)\b/,
    'token' => /\btokens?\b/,
    'usuário' => /\busuari(?:o|os|a|as)\b/,
    # "acessório" não é termo de conta.
    'acesso' => /\bacess(?!ori)/,
    # "permitida" e "permissionário" não casam.
    'permissão' => /\bpermiss(?:ao|oes)\b/,
    'corretor' => /\bcorretor/,
    'credencial' => /\bcredencia(?:l|is)\b/,
    'autenticação' => /\bautentica/,
    'e-mail' => /@/
  }.freeze
  VALOR_EM_REAIS = /R\$/i

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

  # -> o texto tem valor em reais ou algum termo de `TERMOS_DE_CONTA`?
  def proibido?(texto)
    return true if texto.match?(VALOR_EM_REAIS)

    alvo = ActiveSupport::Inflector.transliterate(texto).downcase
    TERMOS_DE_CONTA.each_value.any? { |padrao| alvo.match?(padrao) }
  end
end
