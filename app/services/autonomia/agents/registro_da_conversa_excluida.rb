# Conversa excluída (#2144, LGPD): o que o agente de IA guardou dela fora da própria conversa perde o texto do cliente.
# As duas tabelas apontam para a conversa sem chave estrangeira, então nada saía junto com ela.
#
# Execuções de ferramenta (autonomia_agent_tool_runs): a linha fica, com ferramenta, faixa, status, código da falha,
# tentativas, contadores de entrega e datas (o que conta e o que diz como terminou). Saem:
# - `arguments`: o que o modelo montou com os dados do cliente (na cotação, placa, CEP, nascimento);
# - `handle`: o que a ferramenta devolveu (o número e o resultado da cotação no portal da seguradora) e a identidade do
#   pedido. Ficam só as marcas do motor que são contagem, sinal ou data (MARCAS_QUE_FICAM). Consequência aceita: o
#   número da cotação no portal sai junto; a cotação continua no portal da seguradora;
# - `origin_message_id`: a mensagem do cliente que pediu.
# A execução ainda viva para: vira `blocked` com o código `conversa_excluida`, no mesmo comando e com as mesmas marcas
# do ToolRun#finish! (a data do encerramento e a "possivelmente duplicada" quando o job decidiu submeter e o número não
# chegou). O job que estiver no meio da passada perde a posse (as escritas dele exigem `running`) e não grava o
# resultado de volta.
#
# Eventos do agente (autonomia_agent_events): a linha fica, com tipo, confiança, motivo em código, modelo e os ids do
# conhecimento usado (a aba Desempenho conta por eles, e pela conversa). Saem o `message_id` e, do `metadata`, tudo
# que não for código, contagem ou custo (METADATA_QUE_FICA).
#
# O id da conversa fica nas duas: é só um número, a conversa não existe mais, e é por ele que "conversas atendidas"
# continua contando a que foi atendida.
#
# Um UPDATE por tabela (e um para as execuções vivas), pelos índices de conversation_id, só nas linhas que ainda têm o
# que limpar, dentro da transação do destroy da conversa.
# rubocop:disable Rails/SkipsModelValidations
class Autonomia::Agents::RegistroDaConversaExcluida
  CODIGO = 'conversa_excluida'.freeze
  RUN = Autonomia::Agents::ToolRun
  MARCAS_QUE_FICAM = [
    RUN::INTENCOES, RUN::POSSIVELMENTE_DUPLICADA, RUN::ENCERRADA_EM, RUN::SUBMITTED_KEY,
    Autonomia::Agents::Tools::Encerramento::CLOSED_KEY,
    Autonomia::Agents::Tools::Evento::COMECO_KEY, Autonomia::Agents::Tools::Evento::FECHO_KEY
  ].freeze
  # Etapa do silêncio (#1669), e do ajudante (tema 14): vínculo, motivo, teto, tempo, rodadas, custo e a base que falhou.
  METADATA_QUE_FICA = %w[etapa principal_id motivo limite ms rodadas custo_usd base].freeze

  # Só as chaves da lista; o que não for objeto vira objeto vazio.
  SO_AS_CHAVES = lambda do |coluna|
    "CASE WHEN jsonb_typeof(#{coluna}) = 'object' THEN (SELECT COALESCE(jsonb_object_agg(chave, valor), '{}'::jsonb) " \
      "FROM jsonb_each(#{coluna}) AS item(chave, valor) WHERE chave = ANY(ARRAY[?]::text[])) ELSE '{}'::jsonb END"
  end
  # Ainda tem chave fora da lista (ou não é objeto): a linha tem o que limpar.
  SOBRA_CHAVE = lambda do |coluna|
    "(CASE WHEN jsonb_typeof(#{coluna}) = 'object' THEN (#{coluna} - ARRAY[?]::text[]) <> '{}'::jsonb ELSE TRUE END)"
  end
  # A marca do ToolRun#finish!: intenção anotada e número ausente.
  DUPLICADA = 'CASE WHEN COALESCE((handle->>?)::int, 0) > 0 AND (handle->>?) IS NULL THEN ?::jsonb ELSE ?::jsonb END'.freeze

  def initialize(account_id:, conversation_id:)
    @da_conversa = { account_id: account_id, conversation_id: conversation_id }
    @agora = Time.current
  end

  def perform
    encerrar_vivas!
    limpar_execucoes!
    limpar_eventos!
  end

  private

  def encerrar_vivas!
    RUN.where(@da_conversa).active.update_all([
                                                "status = 'blocked', failure_code = ?, updated_at = ?, " \
                                                "handle = handle || #{DUPLICADA} || ?::jsonb",
                                                CODIGO, @agora, RUN::INTENCOES, RUN::SUBMITTED_KEY,
                                                { RUN::POSSIVELMENTE_DUPLICADA => true }.to_json, '{}',
                                                { RUN::ENCERRADA_EM => @agora.iso8601(3) }.to_json
                                              ])
  end

  def limpar_execucoes!
    RUN.where(@da_conversa)
       .where("arguments <> '{}'::jsonb OR origin_message_id IS NOT NULL OR #{SOBRA_CHAVE.call('handle')}", MARCAS_QUE_FICAM)
       .update_all([
                     "arguments = '{}'::jsonb, origin_message_id = NULL, handle = #{SO_AS_CHAVES.call('handle')}, updated_at = ?",
                     MARCAS_QUE_FICAM, @agora
                   ])
  end

  def limpar_eventos!
    Autonomia::Agents::AgentEvent.where(@da_conversa)
                                 .where("message_id IS NOT NULL OR #{SOBRA_CHAVE.call('metadata')}", METADATA_QUE_FICA)
                                 .update_all(["message_id = NULL, metadata = #{SO_AS_CHAVES.call('metadata')}", METADATA_QUE_FICA])
  end
end
# rubocop:enable Rails/SkipsModelValidations
