# "Cobrir a pessoa enquanto ela não responde" (decisão 18 do Rodrigo, corrigida: a IA fica até a pessoa responder, sem
# vai e vem; exemplo 17, passo 4). A opção `cobrir_pessoa` do passo "Passar para a agente de IA": a agente assume a
# conversa mesmo com uma pessoa no nome, e a conversa volta sozinha para essa pessoa quando ela escrever nela. O dono da
# automação não monta condição nem passo para a volta: ela é da opção.
#
# Sem coluna nova: a cobertura é o registro `ok` do passo que tirou a conversa (dados `tirada_de` e `cobrindo_conversa`),
# e termina com o registro `pessoa_voltou` da mesma execução ou com o fim dela. Vale só para a conversa assumida com a
# opção.
#
# - `pessoa_escreveu` (AutomacaoListener#message_created): a pessoa tirada escreve ao cliente na conversa coberta (a régua do "a
#   equipe respondeu", PessoaDaEquipe; nota privada não conta). A conversa volta para ela, pelo mesmo serviço do
#   "Atribuir" (assinado pela automação, Ato), e o histórico registra. Se ela já ficou com a conversa ao enviar
#   (#2067), só registra. Só olha a conversa que está com a IA, sem pessoa no nome.
# - `cobrindo?` (EsperaNoExecutor): a mensagem do cliente na conversa que a IA cobre não abre o galho "a cada mensagem"
#   de novo: a espera não recomeça, a pessoa não é chamada, e a IA segue.
module Autonomia::Automacao::Cobertura
  VOLTOU = 'pessoa_voltou'.freeze

  module_function

  # O registro da cobertura em curso desta conversa (opcional: desta execução, desta pessoa), ou nil. Só de execução
  # aberta: acabada a automação, a cobertura acaba junto.
  def vigente(conversa, execucao: nil, pessoa_id: nil)
    abertas = ::Autonomia::Automacao::Execucao.abertas.where(account_id: conversa.account_id).select(:id)
    escopo = ::Autonomia::Automacao::Registro.where(account_id: conversa.account_id, resultado: 'ok', execucao_id: abertas)
                                             .where("dados ->> 'cobrindo_conversa' = ?", conversa.id.to_s)
    escopo = escopo.where(execucao_id: execucao.id) if execucao
    escopo = escopo.where("dados ->> 'tirada_de' = ?", pessoa_id.to_s) if pessoa_id
    ultimo = escopo.order(:id).last
    ultimo unless ultimo.nil? || terminou?(ultimo)
  end

  def terminou?(registro)
    ::Autonomia::Automacao::Registro.where(execucao_id: registro.execucao_id, motivo: VOLTOU).exists?(['id > ?', registro.id])
  end

  # A IA cobre a conversa nesta execução: a cobertura em curso e a conversa ainda sem pessoa no nome.
  def cobrindo?(conversa, execucao)
    conversa.present? && conversa.assignee_id.nil? && conversa.ai_assignee_id.present? && vigente(conversa, execucao: execucao).present?
  end

  # Chamada pela escuta da automação antes de acordar quem espera: a falha fica no log e não impede o resto da escuta.
  def pessoa_escreveu(mensagem)
    conversa = mensagem.conversation
    return unless candidata?(mensagem, conversa)

    cobertura = vigente(conversa, pessoa_id: mensagem.sender_id)
    devolver(cobertura, conversa, mensagem.sender) if cobertura
  rescue StandardError => e
    Rails.logger.error("[automacao][cobertura] não devolveu a conversa mensagem=#{mensagem&.id} #{e.class} em #{e.backtrace&.first}")
  end

  # Barato antes da consulta: mensagem pública de saída de uma pessoa, numa conversa sem pessoa no nome (ou já com essa
  # pessoa, que ficou com ela ao enviar), com a automação ligada na conta.
  def candidata?(mensagem, conversa)
    mensagem.outgoing? && !mensagem.private? && mensagem.sender_type == 'User' && conversa.present? &&
      [nil, mensagem.sender_id].include?(conversa.assignee_id) &&
      ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(mensagem) && ::Autonomia::Automacao::Motor.ligado?(mensagem.account)
  end

  def devolver(cobertura, conversa, pessoa)
    ::Autonomia::Automacao::Ato.da(cobertura.automacao_id) do
      ::Conversations::AssignmentService.new(conversation: conversa, assignee_id: pessoa.id).perform unless conversa.reload.assignee_id == pessoa.id
    end
    ::Autonomia::Automacao::Registro.create!(account_id: cobertura.account_id, automacao_id: cobertura.automacao_id,
                                             execucao_id: cobertura.execucao_id, passo: cobertura.passo, resultado: 'ok',
                                             motivo: VOLTOU, dados: { 'pessoa_id' => pessoa.id, 'conversa_id' => conversa.id })
  end
end
