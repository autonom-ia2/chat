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
#   2. sem o código do portal do começo (`CODIGO_DO_PORTAL`: "400 - ", "[2005] - -", "UC00 - "), o texto só tem
#      letras latinas, espaços e a pontuação de `CARACTERES` (nenhum dígito de nenhum alfabeto, nenhum símbolo);
#   3. toda palavra do texto está em `VOCABULARIO` (`motivo_da_recusa_vocabulario.txt`);
#   4. o texto não casa nenhum padrão de `TERMOS_DE_CONTA` nem de `VALORES`;
#   5. o texto casa algum padrão de `OBJETOS_DO_RISCO` (o veículo, o condutor, a região, a categoria, o risco...).
# O texto devolvido é o sem o código do começo. Em qualquer outro caso devolve nil, e a Lia só pode dizer que a
# seguradora não fez proposta.
#
# O ITEM 3 É O QUE FECHA (quarta rodada de revisão). As três rodadas anteriores recusavam pelo vocabulário da
# conta (item 4), e cada revisão achou texto de conta com palavra que a lista não tinha, inclusive colado a uma
# linha de risco ("Risco fora das políticas de aceitação Licença do multicálculo vencida."). Com o item 3, a
# palavra desconhecida recusa. Hoje nenhuma palavra do vocabulário casa o item 4 (o spec trava isso), e ele
# fica como a regra da issue escrita em código.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  # O teto do texto no conector (`quote-reason.ts`, `TETO_DO_TEXTO`).
  TETO_DO_TEXTO = 300
  # O código do portal no começo do texto: até três letras, ao menos um dígito, colchetes opcionais e um ou
  # mais hífens. Casado no texto original, que é o devolvido.
  CODIGO_DO_PORTAL = /\A\[?[[:alpha:]]{0,3}\d[[:alnum:]]*\]?(?:\s*-+)+\s*/
  # Letras latinas com os seus acentos, espaços e esta pontuação; o resto recusa o texto.
  CARACTERES = %r{\A[\p{Latin}\p{M}[:space:].,;:!?()\[\]/"'-]*\z}
  # O que separa as palavras: espaço e a pontuação de `CARACTERES`.
  SEPARADORES = %r{[[:space:].,;:!?()\[\]/"'-]+}
  # As palavras que o texto pode ter, lidas do arquivo ao lado (sem acento, em minúsculas).
  VOCABULARIO = Set.new(
    Rails.root.join('app/services/autonomia/insurance/motivo_da_recusa_vocabulario.txt').read
         .lines.reject { |linha| linha.start_with?('#') }.join(' ').split
  ).freeze

  # Os padrões daqui para baixo são casados no texto sem acento e em minúsculas.
  VALORES = {
    'reais' => /\breais\b/, 'mil' => /\bmil\b/, 'milhão' => /\bmilh(?:ao|oes)\b/, 'bilhão' => /\bbilh(?:ao|oes)\b/,
    'milhar' => /\bmilhar(?:es)?\b/, 'moeda' => /\b(?:dolar|dolares|euro|euros)\b/,
    'centena por extenso' => /\bcem\b|\bcento\b|\b(?:duzent|trezent|quatrocent|quinhent|seiscent|setecent|oitocent|novecent)/,
    'dezena por extenso' => /\b(?:dez|vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa)\b/,
    'unidade por extenso' => /\b(?:dois|duas|tres|quatro|cinco|seis|sete|oito|nove|onze|doze|treze|quatorze|catorze|quinze)\b/
  }.freeze

  TERMOS_DE_CONTA = {
    # login, logar, logado, logou, logue, logon, logoff, logout; deslogado, relogar, autologin; "log in", "log off".
    'login' => /\b(?:des|re|auto)?log(?:in|on|off|out|ar|ad|ou|ue)|\blog\s+(?:in|off|out)\b/,
    'senha' => /\bsenhas?\b|\bpasswords?\b/, 'sessão' => /\bsess(?:ao|oes)\b/, 'token' => /\btokens?\b/,
    'usuário' => /usuari|\busers?\b/,
    # "acessório" não casa; "permitida" e "permissionário" não casam.
    'acesso' => /\bacess(?!ori)|\baccess/, 'permissão' => /\bpermiss(?!ionari)/,
    # corretor, corretora, corretores; corretagem.
    'corretor' => /\bcorretor|\bcorretag/,
    # credencial, credenciado, descredenciado, credentials; autenticação, reautenticar; autorizado, desautorizado.
    'credencial' => /credenci|credential/, 'autenticação' => /autentic|authentic/, 'autorização' => /autoriz|authoriz/,
    # habilitação, habilitado; desabilitado, inabilitado (sem o "h").
    'habilitação' => /abilit/,
    'produtor' => /\bprodutor/, 'SUSEP' => /\bsusep\b/,
    # cadastro, recadastramento; comissão; certificado, certificação; bloqueado, bloqueio, desbloqueio, locked.
    'cadastro' => /cadastr/, 'comissão' => /\bcomiss/, 'certificado' => /certific/, 'bloqueio' => /bloque(?:ad|io)|\blocked\b/,
    'conta' => /\bcontas?\b|\baccounts?\b/,
    # suspenso, suspensão, suspended; agenciador, agenciamento; expirado, expirou, expiração, expired.
    'suspensão' => /suspen/, 'agenciamento' => /agenci/, 'inadimplência' => /inadimpl/, 'chave' => /\bchaves?\b/,
    'integração' => /integrac/, 'expiração' => /expir/, 'portal' => /\bport(?:al|ais)\b/,
    'licença' => /\blicenc/, 'multicálculo' => /multicalc/, 'operador' => /\boperador/, 'CPF' => /\bcpf\b/,
    'e-mail' => /@|\be[\s-]?mails?\b/, 'link' => %r{https?://|\bwww\.},
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
    texto = texto_de(reason)&.sub(CODIGO_DO_PORTAL, '')
    return nil unless texto&.match?(CARACTERES)

    alvo = ActiveSupport::Inflector.transliterate(texto).downcase
    do_vocabulario?(alvo) && !recusado?(alvo) && do_risco?(alvo) ? texto : nil
  end

  # -> o texto aparado de um motivo de `kind` `risco`, não vazio e dentro do teto; nil nos outros casos.
  def texto_de(reason)
    return nil unless reason.is_a?(Hash) && reason['kind'] == KIND_PERMITIDO && reason['text'].is_a?(String)

    texto = reason['text'].strip
    texto.empty? || texto.length > TETO_DO_TEXTO ? nil : texto
  end

  # -> toda palavra do texto (sem acento, em minúsculas) está no vocabulário?
  def do_vocabulario?(alvo)
    alvo.split(SEPARADORES).reject(&:empty?).all? { |palavra| VOCABULARIO.include?(palavra) }
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
