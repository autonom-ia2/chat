# O MOTIVO DE QUEM NÃO COTOU QUE PODE ORIENTAR A FALA DA LIA (fatia 2 do #420, regra registrada na issue
# em 13/09/2026).
#
# O conector manda `reason: { kind, text }` para cada seguradora que não cotou (autonomia-adapters#60). A
# revisão daquela PR mostrou que o `kind` erra: "Senha expirou. Declinando cálculo." sai `risco`,
# "Sistema indisponível: sessão expirada, faça login novamente." sai `passageiro`, e "Usuário
# fulano@corretora.com.br bloqueado." sai `outro`. Por isso o `kind` sozinho não libera o texto.
#
# `permitido` devolve o texto quando, e só quando:
#   1. o `kind` é `risco`;
#   2. sem o código do portal do começo (`CODIGO_DO_PORTAL`: "400 - ", "[2005] - -", "UC00 - "), o texto não
#      casa nenhum padrão de `VALORES`, e o primeiro deles é qualquer dígito;
#   3. não casa nenhum padrão de `TERMOS_DE_CONTA`;
#   4. casa algum padrão de `OBJETOS_DO_RISCO` (o veículo, o condutor, a região, a categoria, o risco...).
# O texto devolvido é o sem o código do começo. Em qualquer outro caso devolve nil, e a Lia só pode dizer que a
# seguradora não fez proposta.
#
# POR QUE O ITEM 4 (terceira rodada de revisão da fatia 2). Os itens 2 e 3 recusam pelo vocabulário, e o
# vocabulário da conta da corretora não fecha: a segunda revisão passou pelo classificador real do conector
# 22 textos de conta que saem `risco` com palavras que a lista não tinha ("Entre novamente no portal da
# seguradora", "Licença do multicálculo vencida", "Vínculo com a sucursal inexistente"). Nenhum deles nomeia o
# objeto do risco, e o item 4 recusa os 22. Os catorze textos reais de risco do corpus do conector nomeiam, e
# passam. O que ainda passa é o texto que nomeia o objeto do risco e fala da conta com palavra fora do item 3.
#
# O item 2 faz com que nenhum dígito do portal chegue ao modelo: o valor ao cliente é escrito pelo código.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  # O teto do texto no conector (`quote-reason.ts`, `TETO_DO_TEXTO`).
  TETO_DO_TEXTO = 300
  # O código do portal no começo do texto: letras opcionais, ao menos um dígito, colchetes opcionais e um ou
  # mais hífens. Casado no texto original, que é o devolvido.
  CODIGO_DO_PORTAL = /\A\[?[[:alpha:]]*\d[[:alnum:]]*\]?(?:\s*-+)+\s*/

  # Os padrões daqui para baixo são casados no texto sem acento e em minúsculas.
  VALORES = {
    'dígito' => /\d/, 'R$' => /r\$/, 'reais' => /\breais\b/, 'mil' => /\bmil\b/, 'milhão' => /\bmilh(?:ao|oes)\b/,
    'centena por extenso' => /\bcem\b|\bcento\b|\b(?:duzent|trezent|quatrocent|quinhent|seiscent|setecent|oitocent|novecent)/
  }.freeze

  TERMOS_DE_CONTA = {
    # login, logar, logado, logou, logue, logon, logoff, logout; deslogado, relogar, autologin; "log in", "log off".
    'login' => /\b(?:des|re|auto)?log(?:in|on|off|out|ar|ad|ou|ue)|\blog\s+(?:in|off|out)\b/,
    'senha' => /\bsenhas?\b|\bpasswords?\b/, 'sessão' => /\bsess(?:ao|oes)\b/, 'token' => /\btokens?\b/,
    'usuário' => /usuari/,
    # "acessório" não casa; "permitida" e "permissionário" não casam.
    'acesso' => /\bacess(?!ori)/, 'permissão' => /\bpermiss(?!ionari)/,
    # corretor, corretora, corretores; corretagem.
    'corretor' => /\bcorretor|\bcorretag/,
    # credencial, credenciado, descredenciado; autenticação, reautenticar; autorizado, desautorizado.
    'credencial' => /credenci/, 'autenticação' => /autentic/, 'autorização' => /autoriz/,
    # habilitação, habilitado; desabilitado, inabilitado (sem o "h").
    'habilitação' => /abilit/,
    'produtor' => /\bprodutor/, 'SUSEP' => /\bsusep\b/,
    # cadastro, recadastramento; comissão; certificado, certificação; bloqueado, bloqueio, desbloqueio.
    'cadastro' => /cadastr/, 'comissão' => /\bcomiss/, 'certificado' => /certific/, 'bloqueio' => /bloque(?:ad|io)/,
    # "por conta de" e "em conta" não casam.
    'conta' => /(?<!por )(?<!em )\bcontas?\b/,
    # suspenso, suspensão; agenciador, agenciamento, agência; expirado, expirou, expiração.
    'suspensão' => /suspens/, 'agenciamento' => /agenci/, 'inadimplência' => /inadimpl/, 'chave' => /\bchaves?\b/,
    'integração' => /integrac/, 'expiração' => /expir/, 'portal' => /\bport(?:al|ais)\b/,
    'e-mail' => /@|\be-?mails?\b/, 'link' => %r{https?://|\bwww\.},
    # A marca com que o conector redige e-mail e segredo no texto.
    'redigido' => /redacted/
  }.freeze

  OBJETOS_DO_RISCO = {
    'veículo' => /\bveicul/, 'carro' => /\bcarros?\b/, 'moto' => /\bmotos?\b|\bmotocic/, 'caminhão' => /\bcaminh(?:ao|oes)\b/,
    'ônibus' => /\bonibus\b/, 'utilitário' => /\butilitari/, 'auto' => /\bauto\b|\bautomove/, 'acessório' => /\bacessori/,
    'modelo' => /\bmodelos?\b/, 'ano' => /\banos?\b/, 'categoria' => /\bcategori/, 'tarifa' => /\btarif/,
    'condutor' => /\bcondutor/, 'motorista' => /\bmotorista/, 'região' => /\bregi(?:ao|oes)\b/, 'circulação' => /\bcircula/,
    'CEP' => /\bcep\b/, 'logradouro' => /\blogradour/, 'pernoite' => /\bpernoite/, 'garagem' => /\bgarage/,
    'uso' => /\buso\b/, 'carga' => /\bcarga/, 'idade' => /\bidade\b/,
    # segurado, segurada; "seguradora" não casa.
    'segurado' => /\bsegurad(?!or)/,
    'risco' => /\briscos?\b/, 'cenário' => /\bcenario/, 'cobertura' => /\bcobertura/, 'blindagem' => /\bblind/,
    'rastreador' => /\brastread/, 'chassi' => /\bchassi/, 'FIPE' => /\bfipe\b/, 'sinistro' => /\bsinistr/,
    'bônus' => /\bbonus\b/, 'vistoria' => /\bvistori/, 'imóvel' => /\bimove(?:l|is)\b/, 'residência' => /\bresiden/,
    'construção' => /\bconstruc/, 'profissão' => /\bprofiss/, 'transporte' => /\btransport/, 'aplicativo' => /\baplicativ/,
    'placa' => /\bplacas?\b/, 'combustível' => /\bcombustiv/, 'frota' => /\bfrotas?\b/
  }.freeze

  module_function

  # -> o texto do portal, aparado e sem o código do começo, quando ele pode orientar a fala da Lia; nil quando
  # não pode.
  def permitido(reason)
    texto = texto_de(reason)
    return nil if texto.nil?

    texto = texto.sub(CODIGO_DO_PORTAL, '')
    alvo = ActiveSupport::Inflector.transliterate(texto).downcase
    recusado?(alvo) || !do_risco?(alvo) ? nil : texto
  end

  # -> o texto aparado de um motivo de `kind` `risco`, não vazio e dentro do teto; nil nos outros casos.
  def texto_de(reason)
    return nil unless reason.is_a?(Hash) && reason['kind'] == KIND_PERMITIDO && reason['text'].is_a?(String)

    texto = reason['text'].strip
    texto.empty? || texto.length > TETO_DO_TEXTO ? nil : texto
  end

  # -> o texto (sem acento, em minúsculas) casa algum padrão de `VALORES` ou de `TERMOS_DE_CONTA`?
  def recusado?(alvo)
    VALORES.merge(TERMOS_DE_CONTA).each_value.any? { |padrao| alvo.match?(padrao) }
  end

  # -> o texto (sem acento, em minúsculas) casa algum padrão de `OBJETOS_DO_RISCO`?
  def do_risco?(alvo)
    OBJETOS_DO_RISCO.each_value.any? { |padrao| alvo.match?(padrao) }
  end
end
