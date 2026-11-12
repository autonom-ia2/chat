# O passo "Marcar reunião pela conversa" (#2935): oferece ao cliente os 3 próximos horários livres de quem atende (o
# responsável do card ou uma pessoa), espera a escolha e marca a reunião sozinho. O cliente não abre link nenhum.
#
# - Pergunta: o convite com os horários em botões, ou numerados quando o canal não tem botão (MensagemComOpcoes), com
#   todas as regras do passo "mensagem": quem não recebe pula; a janela de 24 h fechada manda o modelo aprovado no
#   lugar, ou nada e a execução para nesta conversa (decisão do Rodrigo, 12/11). Com o modelo, os horários vão quando o
#   cliente responder a ele, e só com a janela desta conversa aberta; nunca sai um segundo modelo (DepoisDoModelo).
# - Sem com quem marcar (o card sem responsável, a pessoa escolhida fora da conta) ou sem página de agendamento para a
#   pessoa, segue sem reunião pelo galho "Se o cliente não responder" (`nao_respondeu`), e o histórico diz por quê. A
#   execução não trava (decisão do Rodrigo, 12/11), e a saída é a mesma antes e depois do modelo da janela fechada. Sem
#   nenhum horário livre na janela da página, segue pelo galho "Se pedir outro horário" (`sem_horario`).
# - Resposta: a IA de decidir lê o que o cliente escreveu (o botão chega como o texto dele) e escolhe o horário 1, 2 ou
#   3, "outro horário" ou "não ficou claro" (RespostaDoCliente). Não ficou claro: espera a próxima resposta, até o prazo.
# - Escolheu: marca pela agenda do CRM (AgendaDaReuniao), na página e com a pessoa da pergunta, e segue para o passo
#   seguinte. Outro cliente pegou o horário antes (a trava do Booker): segue pelo galho "Se pedir outro horário"
#   (`horario_ocupado`), que avisa o responsável.
class Autonomia::Automacao::PassoDeReuniao
  include ::Autonomia::Automacao::NaConversa
  include ::Autonomia::Automacao::DepoisDoModelo

  Falha = ::Autonomia::Automacao::PassoDeIa::Falha
  OUTRO = 'outro_horario'.freeze
  NAO_RESPONDEU = 'nao_respondeu'.freeze
  NENHUM = 'nenhum'.freeze
  SEM_RESPONSAVEL = 'reuniao_sem_responsavel'.freeze
  SEM_PAGINA = 'reuniao_sem_pagina'.freeze
  INSTRUCOES = <<~TEXTO.freeze
    O cliente recebeu um convite para uma reunião com horários numerados (em "pergunta") e respondeu (em "respostas_do_cliente"). Responda só com JSON no schema.
    "escolha": o número do horário que ele escolheu; "outro_horario" quando ele recusou todos ou pediu outro dia ou hora; "nenhum" quando a resposta não deixa claro qual horário ele quer ou não fala dos horários. Uma escolha errada é pior que nenhuma.
  TEXTO

  def initialize(execucao:, passo:, alvo:, acesso: nil)
    super(execucao: execucao, passo: passo, alvo: alvo)
    @acesso = acesso
  end

  def perguntar
    return sem_conversa if @conversa.nil?

    pessoa = ::Autonomia::Automacao::QuemDoPasso.pessoas(conta, @passo['com'], contexto).first
    return sem_reuniao(SEM_RESPONSAVEL) unless pessoa

    oferecer(pessoa)
  end

  # Depois do modelo (janela fechada), a primeira resposta do cliente abre a janela, e os horários vão agora.
  def resposta(pedido, marco:, ate:)
    leitor = ::Autonomia::Automacao::RespostaDoCliente.new(conta: conta, contato: contexto.contato, quem: quem_ligou, marco: marco, ate: ate)
    return Resultado.new(tipo: :esperar, dados: {}) unless leitor.novas?
    return depois_do_modelo(pedido, leitor) if esperando_o_modelo?(pedido)

    entender(pedido, leitor)
  rescue Falha => e
    Resultado.new(tipo: :passageiro, motivo: e.motivo, dados: {})
  end

  def depois_de_esperar(_registro) = nil

  def fechar(_pedido) = nil

  private

  def conta = @execucao.account

  def contexto = (@contexto ||= ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao))

  def quem_ligou = @execucao.automacao.ligada_por

  # Sem com quem marcar, ou sem a página dela: segue sem reunião, pelo galho "Se o cliente não responder".
  def sem_reuniao(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados.merge('ramo' => NAO_RESPONDEU))

  # Depois do modelo, o convite sai sem o modelo da receita: o segundo modelo nunca sai.
  def oferecer(pessoa, depois_do_modelo: false)
    agenda = ::Autonomia::Automacao::AgendaDaReuniao.new(conta, pessoa, @passo['duracao'])
    return sem_reuniao(SEM_PAGINA, 'por' => agenda.por) unless agenda.pagina

    horarios = agenda.horarios
    return Resultado.new(tipo: :pulado, motivo: 'sem_horario', dados: { 'ramo' => OUTRO }) if horarios.empty?

    rotulos = horarios.map { |inicio| agenda.rotulo(inicio) }
    mandado = ::Autonomia::Automacao::MensagemComOpcoes.new(
      execucao: @execucao, passo: depois_do_modelo ? passo_sem_modelo : @passo, alvo: @alvo, texto: @passo['convite'], opcoes: rotulos
    ).executar
    return mandado unless mandado.tipo == :ok

    Resultado.new(tipo: depois_do_modelo ? :de_novo : :esperar, dados: oferta(mandado, horarios, rotulos, pessoa))
  end

  # O que a resposta vai precisar: o marco, os horários oferecidos e a pessoa. Com o modelo, só o marco: os horários vão
  # depois, e são lidos de novo naquela hora.
  def oferta(mandado, horarios, rotulos, pessoa)
    marco = { 'marco' => ::Autonomia::Automacao::Resposta.marco(contexto.contato, quem_ligou), 'pessoa' => pessoa.id }
    return mandado.dados.merge(marco, fase(mandado)) if mandado.dados['modelo']

    mandado.dados.merge(marco, 'horarios' => horarios.map(&:iso8601), 'opcoes' => rotulos)
  end

  # A resposta ao modelo. A mensagem do cliente em outra conversa dele não abre a janela desta: nada sai, e a espera
  # continua com o mesmo prazo, a partir de um marco novo. Aberta, os horários vão agora, e a espera recomeça (:de_novo).
  def depois_do_modelo(pedido, leitor)
    return esperar_a_janela(leitor) if janela_ainda_fechada?

    pessoa = conta.users.find_by(id: pedido.dados['pessoa'])
    return sem_reuniao(SEM_RESPONSAVEL) unless pessoa

    feito = oferecer(pessoa, depois_do_modelo: true)
    return esperar_a_janela(leitor) if janela_fechou?(feito)
    return feito if %i[de_novo laco sem_acesso].include?(feito.tipo)

    Resultado.new(tipo: :pulado, motivo: feito.motivo, dados: feito.dados.merge('ramo' => feito.dados['ramo'] || NAO_RESPONDEU))
  end

  def entender(pedido, leitor)
    horarios = Array(pedido.dados['horarios'])
    novo = leitor.marco_novo
    pergunta = ::Autonomia::Automacao::MensagemComOpcoes.numerado(@passo['convite'], Array(pedido.dados['opcoes']))
    resposta, custo = leitor.entender(feature: 'automacao_marcar_reuniao', instrucoes: INSTRUCOES, pergunta: pergunta,
                                      schema: schema(horarios.size))
    escolha = resposta&.dig('escolha')
    return Resultado.new(tipo: :esperar, dados: { 'marco' => novo }) if escolha.nil? || escolha == NENHUM
    return Resultado.new(tipo: :ok, dados: { 'ramo' => OUTRO, 'ia' => custo }) if escolha == OUTRO

    marcar(pedido, Time.zone.parse(horarios[escolha.to_i - 1]), custo)
  end

  def marcar(pedido, inicio, custo)
    agenda = ::Autonomia::Automacao::AgendaDaReuniao.new(conta, conta.users.find_by(id: pedido.dados['pessoa']), @passo['duracao'])
    chave = "automacao:#{@execucao.id}:#{@passo['id']}:#{inicio.utc.iso8601}"
    reuniao = agenda.marcar(inicio, contato: contexto.contato, card: card_aberto, conversa: @conversa, chave: chave)
    Resultado.new(tipo: :ok, dados: { 'reuniao_id' => reuniao.id, 'horario' => inicio.iso8601, 'ia' => custo })
  rescue ArgumentError => e
    motivo = e.message == 'slot_unavailable' ? 'horario_ocupado' : 'reuniao_nao_marcou'
    Rails.logger.info("[automacao][reuniao] não marcou execucao=#{@execucao.id} codigo=#{e.message}")
    Resultado.new(tipo: :pulado, motivo: motivo, dados: { 'ramo' => OUTRO, 'ia' => custo })
  end

  # O card do alvo, aberto e do mesmo contato; senão o Booker acha (ou cria) o card do contato no funil da página.
  def card_aberto
    card = contexto.card
    card if card&.open? && card.contact_id == contexto.contato&.id
  end

  def schema(quantos)
    escolhas = (1..quantos).map(&:to_s) + [OUTRO, NENHUM]
    { name: 'automacao_marcar_reuniao',
      schema: { type: 'object', additionalProperties: false, required: %w[escolha],
                properties: { escolha: { type: 'string', enum: escolhas } } } }
  end
end
