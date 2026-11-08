# UM EVENTO DA EXECUÇÃO ASSÍNCRONA, e quem fala sobre ele é o agente (PR C, decisão do CEO de 22/09/2026).
#
# Até aqui o motor publicava TEXTO PRONTO ao cliente em cada momento da cotação: o aviso de espera, o pedido do
# dado que falta, a legenda do comparativo, o desfecho. As frases eram constantes nossas ou frases que o
# especialista escrevia no pedido, e saíam iguais para quem estivesse do outro lado. Agora o motor só publica
# ARQUIVO; onde ele publicaria texto, ele DISPARA um evento, e a Lia fala num turno de modelo acionado por ele
# (`Operate::EventoJob`, `Operate::ResponderAoEvento`). Frase pronta ao cliente não existe mais neste fluxo.
#
# O EVENTO É: a execução, o TIPO (lista fechada, `TIPOS`) e os FATOS, texto para o MODELO, nunca para o cliente.
# Os fatos vêm da ferramenta (`Native::Base.fatos_do_evento`, de classe: funciona com o agente apagado).
#
# UM EVENTO POR SLOT, adquirido no banco (`merge_handle!(ausente:)`): o começo tem o dele, e todo o resto divide
# o do FECHO (recusa inclusive), porque a execução tem um desfecho só. Quem não adquire não dispara: o retry do
# Sidekiq, o varredor cruzando com o motor e a passada que reentra depois de um processo morto não fazem a Lia
# falar duas vezes. A segunda guarda é a MARCA na mensagem (`CHAVE`), que o turno confere antes de postar.
class Autonomia::Agents::Tools::Evento
  # A marca que a mensagem do turno de evento carrega: "<id da execução>:<tipo>". A nota privada ao atendente
  # carrega a mesma, e é por ela que a idempotência pergunta à conversa "este evento já teve palavra?".
  CHAVE = 'autonomia_evento'.freeze
  # Os dois slots, marcas do motor (`AsyncRunJob::MARCAS`): a ferramenta não os vê nem os regrava.
  COMECO_KEY = 'autonomia_evento_comeco'.freeze
  FECHO_KEY = 'autonomia_evento_fecho'.freeze

  COMECO = 'cotacao_comecou'.freeze
  # #1430: os desfechos da ferramenta HTTP assíncrona (`HttpAssincronaJob`). Genéricos: a ferramenta é do dono da conta,
  # e o resultado pode ser de qualquer assunto. Os fatos são o que o job gravou na linha, não o catálogo das nativas.
  CONSULTA_CONCLUIDA = 'consulta_concluida'.freeze
  CONSULTA_FALHOU = 'consulta_falhou'.freeze
  CONSULTAS = [CONSULTA_CONCLUIDA, CONSULTA_FALHOU].freeze
  # O resultado da consulta é DADO DE UM SISTEMA DE FORA, e não entra cru no aviso do sistema: vai cercado, com o aviso
  # de dado externo (`Recusa::AVISO_DE_DADO_EXTERNO`). A cerca leva um marcador aleatório por evento: o sistema de fora
  # não o conhece, e não tem como fechá-la por dentro.
  CERCA_DO_RESULTADO = '<<<RESULTADO_DA_CONSULTA_%<marcador>s>>>'.freeze
  # A lista fechada. `falta_dado` e `ramo_desconhecido` são as recusas do envio; `concluida`, `valores_guardados`,
  # `falhou`, `incerta`, `encerrada_por_prazo` e `sem_aceitacao` são os desfechos que `Tools::Encerramento` escolhe.
  TIPOS = [COMECO, 'falta_dado', 'ramo_desconhecido', 'concluida', 'valores_guardados', 'falhou', 'incerta',
           'encerrada_por_prazo', 'sem_aceitacao', *CONSULTAS].freeze

  # O que o modelo lê sobre cada tipo, antes dos fatos da ferramenta. Texto para o MODELO: nenhuma palavra daqui
  # chega ao cliente como está.
  DESCRICOES = {
    COMECO => 'a consulta que a pessoa pediu começou agora, e o turno em que ela pediu terminou sem falar com ela.',
    'falta_dado' => 'a consulta não foi aberta porque falta um dado que a pessoa precisa dar.',
    'ramo_desconhecido' => 'a consulta não foi aberta porque o tipo de seguro pedido não é feito por aqui.',
    'concluida' => 'a consulta terminou, e o resultado acabou de ser enviado nesta conversa.',
    'valores_guardados' => 'a consulta terminou com resultado, mas o arquivo não pôde ser enviado; o resultado está guardado.',
    'falhou' => 'a consulta não pôde ser concluída, e nada chegou à pessoa.',
    'incerta' => 'não foi possível confirmar se a consulta chegou a ser feita, e nada chegou à pessoa.',
    'encerrada_por_prazo' => 'a consulta terminou, e o resultado já foi enviado nesta conversa.',
    # chat#612: nada falhou; nenhuma seguradora trouxe proposta. O motivo fica com a equipe (`Tools::NotaInterna`).
    'sem_aceitacao' => 'a consulta terminou e nenhuma seguradora trouxe proposta; nada chegou à pessoa.',
    CONSULTA_CONCLUIDA => 'a consulta que a pessoa pediu terminou. O resultado está no bloco abaixo e ainda não foi dito a ela.',
    CONSULTA_FALHOU => 'a consulta que a pessoa pediu não pôde ser concluída (erro ou tempo esgotado), e nada chegou a ela. ' \
                       'Diga que não conseguiu agora.'
  }.freeze
  # #1430: a falha da consulta que tem motivo próprio, pelo código gravado na linha (`ToolRun::CODIGO_DA_CONSULTA`). No
  # lugar da descrição genérica de `consulta_falhou`, e sem o bloco do resultado (que só repetiria o código).
  FALHAS_DA_CONSULTA = {
    ::Autonomia::Agents::ToolRun::INCERTA => 'o pedido que a pessoa fez saiu para o sistema, mas a resposta se perdeu: não dá ' \
                                             'para confirmar se ele foi registrado, e nada chegou a ela. Diga que não ' \
                                             'conseguiu confirmar agora e que a equipe vai conferir; não diga que deu certo ' \
                                             'nem que deu errado.',
    ::Autonomia::Agents::ToolRun::BLOQUEADA => 'a consulta que a pessoa pediu não foi feita, porque o atendimento automático ' \
                                               'desta conversa foi pausado ou mudou de responsável, e nada chegou a ela. Diga ' \
                                               'que não conseguiu fazer a consulta agora.'
  }.freeze

  attr_reader :run, :tipo

  # Dispara o evento: adquire o slot e enfileira o turno. -> true quando ESTA chamada disparou; false quando o slot
  # já era de outra passada ou o tipo não é da lista. Enfileirar que levanta devolve o slot e sobe: quem chama
  # decide (o `concluir` do motor tenta de novo; o encerramento registra).
  #
  # `depois_de`: tokens de entregas que o turno deve esperar virar mensagem além das da lista do aceite — o
  # arquivo que o encerramento acabou de adiar, quando a escrita do aceite dele falhou.
  def self.disparar(run, tipo, depois_de: [])
    tipo = tipo.to_s
    return nao_disparado(run, tipo, 'tipo_desconhecido') unless TIPOS.include?(tipo)

    slot = slot_de(tipo)
    return nao_disparado(run, tipo, 'slot_ocupado') unless run.merge_handle!({ slot => tipo }, ausente: slot)

    enfileirar(run, tipo, slot, Array(depois_de).compact_blank.map(&:to_s))
  end

  def self.enfileirar(run, tipo, slot, depois_de)
    ::Autonomia::Agents::Operate::EventoJob.perform_later(run.id, tipo, 0, 0, depois_de)
    Rails.logger.info("[autonomia][evento] disparado run=#{run.id} tipo=#{tipo}")
    true
  rescue StandardError
    run.merge_handle!({}, remover: [slot])
    raise
  end

  def self.slot_de(tipo)
    tipo == COMECO ? COMECO_KEY : FECHO_KEY
  end

  # Um resultado de sistema de fora entre as cercas, com o aviso de dado externo; nil quando vazio.
  def self.cercado(texto)
    limpo = texto.to_s.strip
    return nil if limpo.blank?

    cerca = format(CERCA_DO_RESULTADO, marcador: SecureRandom.hex(8))
    "Resultado da consulta (#{::Autonomia::Agents::Tools::Recusa::AVISO_DE_DADO_EXTERNO}):\n#{cerca}\n#{limpo}\n#{cerca}"
  end

  def self.nao_disparado(run, tipo, motivo)
    Rails.logger.info("[autonomia][evento] nao disparado run=#{run&.id} tipo=#{tipo.presence || '-'} motivo=#{motivo}")
    false
  end

  private_class_method :enfileirar, :nao_disparado

  def initialize(run:, tipo:)
    @run = run
    @tipo = tipo.to_s
  end

  def valido?
    TIPOS.include?(tipo)
  end

  def comeco?
    tipo == COMECO
  end

  def consulta?
    CONSULTAS.include?(tipo)
  end

  def marca
    "#{run.id}:#{tipo}"
  end

  # -> a mensagem desta conversa (pública ou nota privada) que já carrega a marca deste evento, ou nil. O `LIKE` é
  # a peneira barata; quem decide é a comparação exata do atributo.
  def mensagem(conversation)
    return nil if conversation.blank?

    conversation.messages.where('content_attributes::text LIKE ?', "%#{marca}%")
                .detect { |message| message.content_attributes.to_h[CHAVE].to_s == marca }
  end

  def publicado?(conversation)
    mensagem(conversation).present?
  end

  # Os fatos da ferramenta para este tipo. NUNCA levanta: sem ferramenta, ou com ela falhando, sai só a descrição.
  # A consulta HTTP (#1430) traz o que o job gravou; o slug dela pode ser o de uma nativa, e o catálogo não é lido.
  def fatos
    return @fatos if defined?(@fatos)
    return @fatos = (falha_com_motivo ? nil : self.class.cercado(run.resultado_da_consulta)) if run.consulta_http?

    @fatos = ::Autonomia::Agents::Tools::Registry.find(run.slug)&.fatos_do_evento(tipo, run).to_s.strip.presence
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] fatos indisponiveis run=#{run.id} tipo=#{tipo} #{e.class}")
    @fatos = nil
  end

  # O que o modelo recebe no lugar da mensagem do cliente: claramente do sistema, com o que aconteceu e os fatos.
  # A da consulta HTTP (#1430) não fala em cotação: o assunto é o da ferramenta do dono da conta.
  def nota_do_sistema
    [
      "AVISO DO SISTEMA SOBRE #{consulta? ? 'UMA CONSULTA' : 'A COTAÇÃO'} DESTA CONVERSA. Isto não é mensagem da pessoa: é " \
      'o sistema contando o que aconteceu, para você falar com ela agora, na sua voz.',
      "O que aconteceu: #{falha_com_motivo || DESCRICOES.fetch(tipo, tipo)}",
      fatos && (consulta? ? fatos : "Fatos: #{fatos}")
    ].compact.join("\n")
  end

  # A descrição própria da falha da consulta (`FALHAS_DA_CONSULTA`), ou nil.
  def falha_com_motivo
    return nil unless tipo == CONSULTA_FALHOU && run.consulta_http?

    FALHAS_DA_CONSULTA[run.handle.to_h[::Autonomia::Agents::ToolRun::CODIGO_DA_CONSULTA]]
  end
end
