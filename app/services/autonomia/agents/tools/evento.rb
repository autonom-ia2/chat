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
  # A lista fechada. `falta_dado` e `ramo_desconhecido` são as recusas do envio; `concluida`, `valores_guardados`,
  # `falhou`, `incerta` e `encerrada_por_prazo` são os desfechos que `Tools::Encerramento` escolhe.
  TIPOS = [COMECO, 'falta_dado', 'ramo_desconhecido', 'concluida', 'valores_guardados', 'falhou', 'incerta',
           'encerrada_por_prazo'].freeze

  # O que o modelo lê sobre cada tipo, antes dos fatos da ferramenta. Texto para o MODELO: nenhuma palavra daqui
  # chega ao cliente como está.
  DESCRICOES = {
    COMECO => 'a consulta que a pessoa pediu começou agora, e o turno em que ela pediu terminou sem falar com ela.',
    'falta_dado' => 'a consulta não foi aberta porque falta um dado que a pessoa precisa dar.',
    'ramo_desconhecido' => 'a consulta não foi aberta porque o tipo de seguro pedido não é feito por aqui.',
    'concluida' => 'a consulta terminou, e o resultado acabou de ser enviado nesta conversa.',
    'valores_guardados' => 'a consulta terminou com resultado, mas o arquivo não pôde ser enviado; o resultado está guardado.',
    'falhou' => 'a consulta não pôde ser concluída, e alguém da equipe vai continuar o atendimento.',
    'incerta' => 'não foi possível confirmar se a consulta chegou a ser feita, e alguém da equipe vai conferir.',
    'encerrada_por_prazo' => 'o tempo da consulta acabou depois de a pessoa já ter recebido resultado.'
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
  def fatos
    return @fatos if defined?(@fatos)

    @fatos = ::Autonomia::Agents::Tools::Registry.find(run.slug)&.fatos_do_evento(tipo, run).to_s.strip.presence
  rescue StandardError => e
    Rails.logger.warn("[autonomia][evento] fatos indisponiveis run=#{run.id} tipo=#{tipo} #{e.class}")
    @fatos = nil
  end

  # O que o modelo recebe no lugar da mensagem do cliente: claramente do sistema, com o que aconteceu e os fatos.
  def nota_do_sistema
    [
      'AVISO DO SISTEMA SOBRE A COTAÇÃO DESTA CONVERSA. Isto não é mensagem da pessoa: é o sistema contando o ' \
      'que aconteceu, para você falar com ela agora, na sua voz.',
      "O que aconteceu: #{DESCRICOES.fetch(tipo, tipo)}",
      ("Fatos: #{fatos}" if fatos)
    ].compact.join("\n")
  end
end
