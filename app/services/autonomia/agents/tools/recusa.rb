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
# conversa: só ids, códigos e NOMES de campo. O que não tem forma de código ou de nome de campo
# vira `?` — um valor que entrasse por engano em `faltando` não sobrevive.
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
    'tool_http_error' => 'a ferramenta HTTP respondeu com erro'
  }.freeze
  SEM_DESCRICAO = 'motivo fora do catálogo: falta a frase em MOTIVOS'.freeze

  # Forma de código e de slug: minúsculas, dígitos e sublinhado. Forma de nome de campo: caminho
  # pontuado como `insured.document` ou `configuracoes.valorMercado`. Fora disso não é identificador,
  # é valor — e valor não entra no registro.
  CODIGO = /\A[a-z][a-z0-9_]{0,79}\z/
  CAMPO = /\A[a-z][A-Za-z0-9_]{0,39}(\.[a-z][A-Za-z0-9_]{0,39}){0,5}\z/
  DETALHE = /\A[A-Za-z0-9_.:\-]{1,40}\z/
  MAX_CAMPOS = 20

  module_function

  # Registra a recusa. -> o código registrado, para quem chama poder embutir na saída ao modelo.
  #
  # `conversa` (id) e `agente` podem faltar (Testar, Copiloto): a linha sai mesmo assim, com `-` no
  # lugar — a ausência da conversa É o motivo em `async_indisponivel_nesta_superficie`.
  # `extra`: `faltando` (nomes de campo), `detalhe` (ex.: status HTTP) e `onde` (`turno` ou `envio`).
  def registrar(codigo, slug:, conversa: nil, agente: nil, **extra)
    motivo = codigo(codigo)
    Rails.logger.info(
      "#{PREFIXO} slug=#{codigo(slug)} conversa=#{conversa.presence || '-'} agente=#{agente&.id || '-'} " \
      "conta=#{agente&.account_id || '-'} onde=#{codigo(extra.fetch(:onde, 'turno'))} motivo=#{motivo} " \
      "faltando=#{campos(extra[:faltando])} detalhe=#{detalhe(extra[:detalhe])} " \
      "descricao=\"#{MOTIVOS.fetch(motivo, SEM_DESCRICAO)}\""
    )
    motivo
  end

  # Registra E monta a saída que o modelo lê: `{"error":"<código>"}` ou, com detalhe,
  # `{"error":"<código>: <detalhe>"}` — o formato que o modelo já conhece desde #312.
  def para_modelo(codigo, slug:, delivery: nil, agente: nil, detalhe: nil)
    motivo = registrar(codigo, slug: slug, conversa: delivery&.conversation&.id, agente: agente,
                               detalhe: detalhe)
    { error: [motivo, detalhe(detalhe, vazio: nil)].compact.join(': ') }.to_json
  end

  def codigo(valor)
    texto = valor.to_s
    texto.match?(CODIGO) ? texto : '-'
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
