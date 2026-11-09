# "Cobrir a pessoa enquanto ela não responde" (decisão 18 do Rodrigo, corrigida: a IA fica até a pessoa responder, sem
# vai e vem; exemplo 17, passo 4). A opção `cobrir_pessoa` do passo "Passar para a agente de IA": a agente assume a
# conversa mesmo com uma pessoa no nome, e a conversa volta sozinha para essa pessoa quando ela escrever nela. O dono da
# automação não monta condição nem passo para a volta: ela é da opção.
#
# Sem coluna nova: a cobertura é o registro `cobrindo_pessoa` (dados `tirada_de`, `cobrindo_conversa`, `agente_id`),
# gravado pelo passo na mesma transação da troca (PassoDeIaAssumir). Ela termina com um registro `ok` de fim na mesma
# execução: `pessoa_voltou` ou `cobertura_encerrada`. Vale só para a conversa assumida com a opção, só na conta dela.
#
# - `pessoa_escreveu` (AutomacaoListener#message_created): a pessoa tirada escreve ao cliente na conversa coberta (a
#   régua do "a equipe respondeu", PessoaDaEquipe; nota privada não conta). A conversa volta para ela, pelo mesmo
#   serviço do "Atribuir" (assinado pela automação, Ato), e o histórico registra.
# - `cobrindo?` (EsperaNoExecutor): a mensagem do cliente na conversa que a IA cobre não abre o galho "a cada mensagem"
#   de novo, enquanto a agente ainda pode atender (Fase 2, agente atendendo, vínculo na caixa). Se não pode, o galho
#   abre como sempre e a espera pela pessoa volta a valer.
# - `encerrar` (Executor#finalizar, Definicao#desligar!, VarreduraJob) e `encerrar_sem_motor` (VarreduraJob): a
#   execução fechou, a automação foi desligada ou o Motor saiu da conta, e a IA ainda cobre: a conversa volta para a
#   pessoa tirada, com `cobertura_encerrada`. A IA nunca fica presa.
#
# A volta trava a conversa e confere de novo, dentro da trava, que a cobertura ainda vale: duas mensagens ou a mensagem
# e o fim da execução ao mesmo tempo devolvem uma vez só. Se a volta falhar, a execução ganha um registro `falhou`.
module Autonomia::Automacao::Cobertura
  COMECOU = 'cobrindo_pessoa'.freeze
  VOLTOU = 'pessoa_voltou'.freeze
  ENCERRADA = 'cobertura_encerrada'.freeze
  NAO_DEVOLVEU = 'devolver_falhou'.freeze
  FIM = [VOLTOU, ENCERRADA].freeze

  module_function

  # O registro do começo da cobertura; o passo chama dentro da trava e da transação da troca.
  def comecar!(execucao, passo_id, conversa, pessoa_id, agente_id)
    ::Autonomia::Automacao::Registro.create!(
      account_id: execucao.account_id, automacao_id: execucao.automacao_id, execucao_id: execucao.id, passo: passo_id,
      resultado: 'ok', motivo: COMECOU,
      dados: { 'agente_id' => agente_id, 'tirada_de' => pessoa_id, 'cobrindo_conversa' => conversa.id }
    )
  end

  # A cobertura em curso desta conversa (opcional: desta execução, desta pessoa), ou nil. Só de execução aberta.
  def vigente(conversa, execucao: nil, pessoa_id: nil)
    abertas = ::Autonomia::Automacao::Execucao.abertas.where(account_id: conversa.account_id).select(:id)
    escopo = comecos.where(account_id: conversa.account_id, execucao_id: abertas)
                    .where("dados ->> 'cobrindo_conversa' = ?", conversa.id.to_s)
    escopo = escopo.where(execucao_id: execucao.id) if execucao
    escopo = escopo.where("dados ->> 'tirada_de' = ?", pessoa_id.to_s) if pessoa_id
    ultima = escopo.order(:id).last
    ultima unless ultima.nil? || terminou?(ultima)
  end

  def comecos = ::Autonomia::Automacao::Registro.where(resultado: 'ok', motivo: COMECOU)

  def terminou?(cobertura)
    ::Autonomia::Automacao::Registro.where(execucao_id: cobertura.execucao_id, resultado: 'ok', motivo: FIM)
                                    .exists?(['id > ?', cobertura.id])
  end

  # A IA cobre a conversa nesta execução e ainda pode atendê-la.
  def cobrindo?(conversa, execucao)
    return false unless conversa.present? && conversa.assignee_id.nil? && conversa.ai_assignee_id.present?

    cobertura = vigente(conversa, execucao: execucao)
    cobertura.present? && ::Autonomia::Automacao::PassoDeIaAssumir.pode_cobrir?(conversa, cobertura.dados['agente_id'])
  end

  # Chamada pela escuta da automação antes de acordar quem espera: a falha fica no log e não impede o resto da escuta.
  def pessoa_escreveu(mensagem)
    conversa = mensagem.conversation
    return unless candidata?(mensagem, conversa)

    cobertura = vigente(conversa, pessoa_id: mensagem.sender_id)
    devolver(cobertura, conversa, VOLTOU) if cobertura
  rescue StandardError => e
    Rails.logger.error("[automacao][cobertura] não devolveu a conversa mensagem=#{mensagem&.id} #{e.class} em #{e.backtrace&.first}")
  end

  # Barato antes de qualquer consulta de cobertura: a flag da conta e a conversa com a IA, sem pessoa no nome; depois,
  # mensagem pública de uma pessoa da equipe.
  def candidata?(mensagem, conversa)
    ::Autonomia::Automacao::Motor.ligado?(mensagem.account) && conversa.present? && conversa.ai_assignee_id.present? &&
      conversa.assignee_id.nil? && ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(mensagem)
  end

  # As execuções fecharam (ou o Motor saiu): cada cobertura delas que ainda vale devolve a conversa. Nunca levanta: quem
  # chama está fechando a execução.
  def encerrar(execucao_ids)
    comecos.where(execucao_id: execucao_ids).order(id: :desc).each do |cobertura|
      next if terminou?(cobertura)

      conversa = Conversation.find_by(id: cobertura.dados['cobrindo_conversa'], account_id: cobertura.account_id)
      devolver(cobertura, conversa, ENCERRADA) if conversa
    end
  rescue StandardError => e
    Rails.logger.error("[automacao][cobertura] não encerrou execucoes=#{Array(execucao_ids).first(5)} #{e.class} em #{e.backtrace&.first}")
  end

  # As contas com cobertura em execução aberta e o Motor desligado.
  def encerrar_sem_motor
    abertas = comecos.where(execucao_id: ::Autonomia::Automacao::Execucao.abertas.select(:id))
    contas = Account.where(id: abertas.select(:account_id)).reject { |conta| ::Autonomia::Automacao::Motor.ligado?(conta) }
    encerrar(abertas.where(account_id: contas.map(&:id)).select(:execucao_id)) if contas.any?
  end

  # Sob a trava da conversa, confere de novo: a cobertura não terminou e a conversa segue com a IA, sem pessoa no nome.
  # Se outra pessoa ficou com ela, nada muda.
  def devolver(cobertura, conversa, motivo)
    pessoa_id = cobertura.dados['tirada_de']
    conversa.with_lock do
      next if terminou?(cobertura) || conversa.assignee_id.present? || conversa.ai_assignee_id.nil?

      ::Autonomia::Automacao::Ato.da(cobertura.automacao_id) do
        ::Conversations::AssignmentService.new(conversation: conversa, assignee_id: pessoa_id).perform
      end
      registrar(cobertura, 'ok', motivo, 'pessoa_id' => pessoa_id, 'conversa_id' => conversa.id)
    end
  rescue StandardError => e
    Rails.logger.error("[automacao][cobertura] não devolveu conversa=#{conversa.id} motivo=#{motivo} #{e.class} em #{e.backtrace&.first}")
    registrar(cobertura, 'falhou', NAO_DEVOLVEU, 'para' => motivo, 'erro' => e.class.name, 'conversa_id' => conversa.id)
  end

  def registrar(cobertura, resultado, motivo, dados)
    ::Autonomia::Automacao::Registro.create!(account_id: cobertura.account_id, automacao_id: cobertura.automacao_id,
                                             execucao_id: cobertura.execucao_id, passo: cobertura.passo, resultado: resultado,
                                             motivo: motivo, dados: dados)
  end
end
