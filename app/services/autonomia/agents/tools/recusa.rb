# REGISTRO DE RECUSA: por que uma ferramenta NÃO fez o que o modelo pediu (entrega 6 do plano do
# Agente de Cotação).
#
# Até 10/09/2026 o agente recusava e não deixava rastro. O código curto voltava ao modelo, o modelo
# explicava ao cliente com as próprias palavras, e para quem olhava de fora a cotação simplesmente
# não tinha acontecido. Em 08/09 uma cotação não abriu e foi impossível saber por quê: um dia
# adivinhando, e duas explicações afirmadas que a medição depois desmentiu.
#
# UMA LINHA POR RECUSA, com quatro coisas: qual conversa, qual agente, o motivo (código curto e a
# frase em português) e quais informações faltavam. NUNCA dado do cliente e NUNCA texto da
# conversa. A garantia real é a ORIGEM: código vem de literal no código (a guarda confere), slug vem
# do catálogo ou do cadastro da conta, nome de campo vem da validação do adapter, detalhe é status
# HTTP. A exceção é `tool_not_available`: o slug ali é o NOME QUE O MODELO PEDIU, e o modelo repete
# o que o cliente escreve ("use a função cotar_seguro_cpf_…"). Por isso `slug_conhecido` só deixa
# passar nome que EXISTE em algum catálogo — é o diagnóstico do caso de 08/09 (`cotar_seguro` pedido
# sem estar ligado) — e o resto vira `desconhecida`. Os filtros de forma abaixo são defesa em
# profundidade — o que não tem forma de identificador vira `?` ou `-` —, não a garantia.
#
# O REGISTRO NUNCA LEVANTA. Ele é cortesia sobre um caminho que já deu errado; se o logger falhar,
# a recusa continua chegando ao modelo do mesmo jeito, e o turno não morre por causa da nossa linha.
#
# NÍVEL `info`, e não `debug`. A produção roda com LOG_LEVEL=info (lido na instância em
# 10/09/2026: `docker exec chatwoot-worker printenv LOG_LEVEL`) e o logger é o stdout do
# container, driver json-file. Registrar em `debug` seria entregar nada, em silêncio — a forma mais
# cara de falsa entrega, porque some do radar.
#
# PRODUTOR ÚNICO. A camada de ferramentas não escreve `{ error: ... }` em lugar nenhum além daqui:
# `recusa_guarda_spec` varre o código por AST e reprova a suíte quando aparece uma saída de recusa
# que não passa por este módulo, ou um código que não está em MOTIVOS.
module Autonomia::Agents::Tools::Recusa
  PREFIXO = '[autonomia][tool][recusa]'.freeze

  # Código -> frase em português. Um código sem frase aqui é um código que a guarda reprova, e
  # `recusa_registro_spec` exige um exemplo que dispare cada um.
  MOTIVOS = {
    'invalid_tool_arguments' => 'os argumentos que o modelo escreveu não eram JSON válido',
    'tool_not_available' => 'o modelo pediu uma ferramenta que este agente não tem',
    'async_indisponivel_nesta_superficie' => 'não há conversa para receber o resultado (Testar, Copiloto, playground)',
    'async_desligado' => 'a ferramenta assíncrona está desligada nesta conta ou na instalação',
    'execucao_ja_aberta_neste_turno' => 'este turno já abriu esta execução; é retry, não pedido novo',
    'execucao_ja_em_andamento' => 'duas aceitações correram e esta perdeu para o índice único',
    'conferencia_recusou' => 'a conferência da própria ferramenta recusou o pedido',
    'faltam_dados' => 'a conferência encontrou dado obrigatório faltando',
    'json_invalido' => 'o campo `dados` não era um objeto JSON válido',
    'tool_execution_error' => 'a ferramenta levantou uma exceção ao executar',
    'tool_http_error' => 'a ferramenta HTTP respondeu com erro',
    'capabilities_unavailable' => 'a lista de ramos que a corretora cota não pôde ser lida',
    # O especialista é o único caminho até a cotação; quando ele não roda, o pedido morreu antes.
    'especialista_sem_pedido' => 'o principal chamou o especialista sem escrever o pedido',
    'especialista_sem_credencial' => 'a conta não tem credencial de IA para o especialista',
    'especialista_sem_resposta' => 'o modelo do especialista falhou ou não devolveu o formato combinado',
    'especialista_falhou' => 'o especialista levantou uma exceção',
    'especialista_nao_concluiu' => 'o especialista respondeu vazio, sem resposta e sem pendência',
    'condicoes_sem_seguradora' => 'a consulta às condições gerais veio sem o nome da seguradora',
    'condicoes_sem_pergunta' => 'a consulta às condições gerais veio sem a dúvida do cliente'
  }.freeze
  SEM_DESCRICAO = 'motivo fora do catálogo: falta a frase em MOTIVOS'.freeze
  DESCONHECIDA = 'desconhecida'.freeze

  # Forma de código e de slug: minúsculas, dígitos e sublinhado. Forma de nome de campo: caminho
  # pontuado como `insured.document` ou `configuracoes.valorMercado`. Detalhe: SÓ status HTTP — é o
  # único detalhe que existe hoje; quem precisar de outro amplia isto de propósito, não por acidente.
  CODIGO = /\A[a-z][a-z0-9_]{0,79}\z/
  CAMPO = /\A[a-z][A-Za-z0-9_]{0,39}(\.[a-z][A-Za-z0-9_]{0,39}){0,5}\z/
  DETALHE = /\A[1-5]\d{2}\z/
  MAX_CAMPOS = 20

  module_function

  # Registra a recusa. Nunca levanta.
  #
  # `conversa` (id) e `agente` podem faltar (Testar, Copiloto): a linha sai mesmo assim, com `-` no
  # lugar — a ausência da conversa É o motivo em `async_indisponivel_nesta_superficie`.
  # `extra`: `faltando` (nomes de campo), `detalhe` (status HTTP) e `onde` (`turno` ou `envio`).
  def registrar(codigo, slug:, conversa: nil, agente: nil, **extra)
    motivo = codigo(codigo)
    Rails.logger.info(
      "#{PREFIXO} slug=#{codigo(slug)} conversa=#{Integer(conversa, exception: false) || '-'} agente=#{agente&.id || '-'} " \
      "conta=#{agente&.account_id || '-'} onde=#{codigo(extra.fetch(:onde, 'turno'))} motivo=#{motivo} " \
      "faltando=#{campos(extra[:faltando])} detalhe=#{detalhe(extra[:detalhe])} " \
      "descricao=\"#{MOTIVOS.fetch(motivo, SEM_DESCRICAO)}\""
    )
    nil
  rescue StandardError
    # Sem logger não há para onde avisar; e a recusa ao modelo vale mais que a nossa linha.
    nil
  end

  # Registra E monta a saída que o modelo lê: `{"error":"<código>"}` ou, com detalhe,
  # `{"error":"<código>: <detalhe>"}` — o formato que o modelo conhece desde #312, montado com o
  # código e o detalhe COMO VIERAM. O filtro de forma é só do registro: mudar o que o modelo lê
  # por causa de uma linha de log seria regressão.
  def para_modelo(codigo, slug:, delivery: nil, agente: nil, detalhe: nil)
    registrar(codigo, slug: slug, conversa: delivery&.conversation&.id, agente: agente, detalhe: detalhe)
    { error: [codigo.to_s, detalhe.presence].compact.join(': ') }.to_json
  end

  def codigo(valor)
    texto = valor.to_s
    texto.match?(CODIGO) ? texto : '-'
  end

  # O nome que o modelo pediu, só se for ferramenta que existe: no catálogo das nativas, no cadastro
  # da conta ou entre os especialistas do agente. Nome que não existe em lugar nenhum é texto livre.
  def slug_conhecido(nome, agente)
    texto = nome.to_s
    return texto if ::Autonomia::Agents::Tools::Registry.slugs.include?(texto)
    return DESCONHECIDA if agente.nil?

    especialista = texto.delete_prefix(::Autonomia::Agents::Specialist::FUNCTION_PREFIX)
    agente.tools.exists?(slug: texto) || agente.specialists.exists?(slug: especialista) ? texto : DESCONHECIDA
  end

  def campos(itens)
    nomes = Array(itens).map { |item| item.to_s.match?(CAMPO) ? item.to_s : '?' }.uniq.first(MAX_CAMPOS)
    nomes.empty? ? '-' : nomes.join(',')
  end

  def detalhe(valor, vazio: '-')
    texto = valor.to_s
    texto.match?(DETALHE) ? texto : vazio
  end
end
