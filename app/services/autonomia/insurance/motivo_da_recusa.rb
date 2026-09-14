# O MOTIVO DE QUEM NÃO COTOU, EM CATEGORIA (fatia 2 do #420; decisão do CEO de 13/09/2026, sétima rodada).
#
# NENHUM TEXTO DO PORTAL VAI AO MODELO. O conector manda `reason: { kind, text }` (autonomia-adapters#60), e cinco
# rodadas de revisão mostraram que nenhuma regra por palavra impede texto de conta da corretora ou de dado da pessoa de
# passar quando o próprio texto vai ao modelo. Aqui o código lê o texto e devolve uma categoria fechada; o modelo
# recebe só a categoria (`Native::InsuranceQuoteResult::MOTIVOS`) e fala com as palavras dele.
#
# `categoria` devolve `VEICULO` ou `REGIAO` quando, e só quando:
#   1. o `kind` do conector é `risco` e o texto é String;
#   2. o texto, sem acento e em minúsculas, não tem letra que a transliteração não sabe escrever;
#   3. não casa nenhum padrão de `TERMOS_DE_CONTA` (a conta da corretora), de `TERMOS_DA_PESSOA` (segurado, condutor,
#      dado pessoal ou financeiro: pode ser restrição da pessoa) nem de `TERMOS_DE_DUVIDA` (critério interno, análise);
#   4. casa os padrões de UMA categoria só (`CATEGORIAS`), que nomeiam o atributo recusado: idade, modelo, tipo ou
#      categoria tarifária do veículo; CEP, localidade, região, circulação ou pernoite.
# Em qualquer outro caso devolve nil, e a Lia diz só que a seguradora não fez proposta. Na dúvida, nil: o erro aceitável
# é o genérico; o inaceitável é contar ao cliente um motivo que fala da conta da corretora ou de uma restrição da pessoa.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  VEICULO = 'veiculo'.freeze
  REGIAO = 'regiao'.freeze
  # A letra que `ActiveSupport::Inflector.transliterate` não sabe escrever vira isto.
  ILEGIVEL = '#'.freeze
  # Os nomes do veículo, sem acento e em minúsculas, para os padrões de `CATEGORIAS`.
  NOME_DO_VEICULO = '(?:veicul\w*|carros?|motos?|motocicletas?|automove\w*|caminh(?:ao|oes)|onibus|utilitari\w*)'.freeze

  # Os padrões daqui para baixo são casados no texto sem acento e em minúsculas.
  CATEGORIAS = {
    VEICULO => {
      'idade do veículo' => /\bidades?\s+d[oa]s?\s+#{NOME_DO_VEICULO}|\b#{NOME_DO_VEICULO}\s+acima\s+da\s+idade\b/,
      'ano modelo' => /\bano\W{1,3}modelo\b|\bano\s+de\s+fabricacao\b/,
      'modelo' => Regexp.union(/\b(?:este|esse|deste|desse)\s+modelo\b/, /\bmodelos?\s+d[oa]s?\s+#{NOME_DO_VEICULO}/,
                               /\bmodelos?\s+(?:restrit|sem\s+aceitacao|nao\s+aceit|recusad)/),
      'tipo de veículo' => /\btipos?\s+d[eo]s?\s+#{NOME_DO_VEICULO}/,
      'categoria tarifária' => /\bcategorias?\s+tarifari|\bcategorias?\s+d[oa]s?\s+#{NOME_DO_VEICULO}/
    },
    REGIAO => {
      'CEP' => /\bcep\b/,
      'localidade' => /\blocalidades?\b/,
      'região' => /\bregi(?:ao|oes)\b/,
      'circulação' => /\bcirculac(?:ao|oes)\b/,
      'pernoite' => /\bpernoite\b/
    }
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
    'licença' => /\blicenc/, 'multicálculo' => /multicalc/, 'operador' => /\boperador/,
    'sucursal' => /\bsucursa/, 'filial' => /\bfilia(?:l|is)\b/, 'convênio' => /\bconvenio/, 'pró-labore' => /\bpro\W?labore\b/,
    'vínculo' => /\bvincul/, 'perfil' => /\bperfi(?:l|s)\b/, 'verificação' => /verificac/,
    # parceiro, parceria; comercial; contrato, contratos ("contratação" não casa).
    'parceiro' => /\bparce(?:ir|ri)/, 'comercial' => /\bcomercia/, 'contrato' => /\bcontratos?\b/,
    'e-mail' => /@|\be[\s-]?mails?\b/, 'link' => %r{https?://|\bwww\.},
    # A marca com que o conector redige e-mail e segredo no texto.
    'redigido' => /redacted/
  }.freeze

  TERMOS_DA_PESSOA = {
    # segurado, segurada, segurados; "seguradora" não casa.
    'segurado' => /\bsegurad(?!or)/,
    'condutor' => /\bcondutor/, 'motorista' => /\bmotorista/, 'proprietário' => /\bproprietari/,
    'cliente' => /\bclientes?\b/, 'pessoa' => /\bpessoa/, 'documento' => /\bcpf\b|\bcnpj\b|\bcnh\b/,
    # crédito; financeira, financiado, financiamento.
    'crédito' => /\bcredito/, 'financeiro' => /\bfinanc/,
    # sinistro, sinistralidade; a classe de bônus é o histórico da pessoa.
    'sinistro' => /\bsinistr/, 'bônus' => /\bbonus\b/, 'profissão' => /\bprofiss/
  }.freeze

  TERMOS_DE_DUVIDA = {
    'interno' => /\binternos?\b|\binternas?\b/, 'critério' => /\bcriterios?\b/, 'análise' => /\banalises?\b/
  }.freeze

  module_function

  # -> `VEICULO` ou `REGIAO`, ou nil (o genérico).
  def categoria(reason)
    alvo = alvo_de(reason)
    return nil if alvo.nil? || recusado?(alvo)

    encontradas = CATEGORIAS.select { |_categoria, padroes| casa?(alvo, padroes) }.keys
    encontradas.one? ? encontradas.first : nil
  end

  # -> o texto de um motivo de `kind` `risco`, sem acento e em minúsculas, ou nil.
  def alvo_de(reason)
    return nil unless reason.is_a?(Hash) && reason['kind'] == KIND_PERMITIDO && reason['text'].is_a?(String)

    ActiveSupport::Inflector.transliterate(reason['text'], ILEGIVEL).downcase
  end

  # -> o texto tem letra ilegível, termo de conta, termo da pessoa ou termo de dúvida?
  def recusado?(alvo)
    alvo.include?(ILEGIVEL) || [TERMOS_DE_CONTA, TERMOS_DA_PESSOA, TERMOS_DE_DUVIDA].any? { |padroes| casa?(alvo, padroes) }
  end

  def casa?(alvo, padroes)
    padroes.each_value.any? { |padrao| alvo.match?(padrao) }
  end
end
