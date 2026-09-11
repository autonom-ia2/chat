# A AUTORIZAÇÃO DE UMA EXECUÇÃO PUBLICAR NUMA CONVERSA, reconferida sem cache (rodada 7 da entrega 11).
#
# Dois lugares fazem a MESMA pergunta imediatamente antes de mexer na conversa, e ela precisa ser uma
# só: o publicador (`AsyncPublisher#publicar_sob_lock`), antes de criar a mensagem; e a retomada do
# envio pendente (`RetomadaDeEnvio#recuperar`), antes de reenfileirar um `SendReplyJob` pelo varredor
# (rodada 9). Um `dead?` relido do banco e o vínculo recalculado — conta habilitada, agente ligado e
# ativo, allowlist, a MESMA caixa que aceitou a execução. Quem hospeda o módulo tem `@run`.
#
# Execução morta (supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da
# conta) não publica nem reenvia: o cliente receberia o resultado de um pedido que já corrigiu. NÃO
# basta exigir `running?` — a entrega final legítima é publicada e a linha fechada logo em seguida,
# então uma republicação adiada (ou uma retomada) encontra a linha já `done`, e isso é legítimo.
module Autonomia::Agents::Tools::AutorizacaoDaExecucao
  # Os dois motivos FECHADOS de recusa, como saem no log.
  RECUSAS = %i[execucao_morta vinculo_mudou].freeze

  private

  # -> o vínculo autorizado AGORA (`AgentInbox`), ou o motivo da recusa (um símbolo de `RECUSAS`).
  def autorizacao(conversation)
    return :execucao_morta if @run.reload.dead?

    agent_inbox = vinculo_autorizado(conversation)
    return :vinculo_mudou unless mesmo_vinculo?(agent_inbox)

    agent_inbox
  end

  def recusada?(autorizacao)
    RECUSAS.include?(autorizacao)
  end

  # O vínculo autorizado AGORA, lido do banco a cada chamada — nunca memoizado: quem memoizava
  # publicava, depois de segundos de download, com a autorização de antes dele (Codex, rodada 7).
  def vinculo_autorizado(conversation)
    ::Autonomia::Agents::Operate.authorized_agent_inbox(conversation)
  end

  # O vínculo autorizado agora é o MESMO que aceitou a execução? A conversa pode ter mudado de caixa
  # (ou o vínculo ter sido recriado) entre o disparo e a entrega — nesse caso a cotação não é mais
  # deste agente. Execução antiga sem `agent_inbox_id` gravado aceita qualquer vínculo autorizado.
  def mesmo_vinculo?(agent_inbox)
    return false if agent_inbox.blank?

    @run.agent_inbox_id.blank? || @run.agent_inbox_id == agent_inbox.id
  end
end
