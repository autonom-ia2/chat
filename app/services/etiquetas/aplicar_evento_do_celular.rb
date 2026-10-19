# Aplica na plataforma um evento de etiqueta do app WhatsApp Business do celular (#1823, F1b). Contrato do evento no
# WhatsappLabels::AplicarEvento. Regras (decisões do Rodrigo):
# - Sem a flag `etiquetas_do_celular` na conta da caixa: descarta.
# - criada / renomeada: grava a correspondência (Etiquetas::DoCelular) com o nome e a cor do celular. Sem correspondência,
#   cria o `Label` com o título técnico derivado do nome ("Novo cliente 🔥" vira `novo_cliente`) ou reaproveita o que já
#   tem esse título. Renomear não muda o título nem o nome livre daqui: só o nome do celular.
# - apagada: a correspondência deixa de valer (fica a marca `apagada_em`); o `Label` fica, com tudo em que já está.
# - vinculada / desvinculada: põe ou tira a etiqueta do contato e da conversa não resolvida mais recente dele na caixa
#   (Etiquetas::EtiquetaNoContato). Vinculada sem correspondência cria como em criada; desvinculada sem correspondência
#   (ou com a etiqueta apagada no celular) só deixa log.
# Ordem: os eventos de uma etiqueta do celular passam um de cada vez (trava na linha da correspondência) e o `at` decide.
# Evento mais velho que o último aplicado na etiqueta (criada/renomeada/apagada) ou no contato (vinculada/desvinculada)
# é descartado com log. Repetir o evento não duplica nada. Erro não é engolido: sobe para o job (e a fila tenta de novo).
class Etiquetas::AplicarEventoDoCelular
  ACOES = %w[criada renomeada apagada vinculada desvinculada].freeze
  FLAG = 'etiquetas_do_celular'.freeze
  LOG = '[etiquetas_do_celular]'.freeze
  SEPARADOR = '_'.freeze
  ACEITOS_ALEM_DE_LETRA = (('0'..'9').to_a + [SEPARADOR, '-']).freeze
  TAMANHO_MINIMO_DO_TITULO = 2 # a validação do Label pede ao menos dois caracteres
  PREFIXO_SEM_TITULO = 'whatsapp'.freeze

  # Título técnico de um nome do celular, pelas mesmas regras do formulário (`tituloTecnicoDoNome` no painel), sem regex:
  # minúsculo, palavras unidas por "_", só letra (de qualquer alfabeto com maiúscula e minúscula), dígito, "_" e "-",
  # e sem separador no começo.
  def self.titulo_tecnico(nome)
    palavras = nome.to_s.unicode_normalize(:nfc).downcase.split
    titulo = palavras.map { |palavra| palavra.each_char.select { |ch| caractere_aceito?(ch) }.join }
                     .compact_blank.join(SEPARADOR)
    titulo = titulo[1..] while titulo.start_with?(SEPARADOR, '-')
    titulo
  end

  def self.caractere_aceito?(caractere)
    caractere.downcase != caractere.upcase || ACEITOS_ALEM_DE_LETRA.include?(caractere)
  end

  def initialize(evento)
    @evento = evento.to_h.with_indifferent_access
  end

  def perform
    acao = @evento[:acao].to_s
    raise ArgumentError, "#{LOG} ação desconhecida: #{acao.inspect}" unless ACOES.include?(acao)

    @at = momento_do_evento
    @inbox = Inbox.find_by(id: @evento[:inbox_id])
    return descartar('caixa não existe mais') if @inbox.nil?
    return descartar('flag desligada na conta') unless conta.feature_enabled?(FLAG)

    ActiveRecord::Base.transaction { aplicar(acao) }
  end

  private

  def aplicar(acao)
    case acao
    when 'criada', 'renomeada' then registrar_etiqueta
    when 'apagada' then apagar
    when 'vinculada' then trocar_no_contato(:adicionar, registrar_etiqueta)
    when 'desvinculada' then desvincular
    end
  end

  def momento_do_evento
    Time.iso8601(@evento[:at].to_s)
  rescue ArgumentError
    raise ArgumentError, "#{LOG} at inválido: #{@evento[:at].inspect}"
  end

  def conta
    @inbox.account
  end

  def label_wa_id
    @evento[:label_wa_id].to_s
  end

  # A correspondência travada até o fim da transação: os eventos da mesma etiqueta do celular passam um de cada vez.
  def correspondencia_travada
    Etiquetas::DoCelular.lock.find_by(inbox: @inbox, label_wa_id: label_wa_id)
  end

  # criada / renomeada / vinculada: a correspondência com o nome e a cor deste evento, se ele não for mais velho que o
  # último aplicado. Devolve a correspondência (nil só quando ela está apagada no celular depois deste evento).
  def registrar_etiqueta
    registro = correspondencia_travada || criar_correspondencia
    return registro if registro.previously_new_record?
    return registro unless evento_novo_para?(registro)

    registro.update!(nome: @evento[:nome], color_index: @evento[:color_index], evento_em: @at, apagada_em: nil,
                     **etiqueta_se_faltar(registro))
    registro
  end

  def evento_novo_para?(registro)
    return true if @at >= registro.evento_em

    descartar("mais velho que o último aplicado (#{registro.evento_em.iso8601}) label_wa_id=#{label_wa_id}")
    false
  end

  # A marca de apagada que chegou antes da criação não tem `Label`: ganha um agora.
  def etiqueta_se_faltar(registro)
    return {} if registro.label

    label, criada = etiqueta_para_o_nome
    { label: label, criada_pelo_celular: criada }
  end

  # Cria o `Label` (se preciso) e a correspondência juntos: se a correspondência não grava, o `Label` também não fica.
  # Outro evento da mesma etiqueta criando ao mesmo tempo bate no índice único; aí este espera a trava dele e segue com
  # o que ele gravou.
  def criar_correspondencia(tentar_de_novo: true)
    Etiquetas::DoCelular.transaction(requires_new: true) do
      label, criada = etiqueta_para_o_nome
      Etiquetas::DoCelular.create!(account: conta, inbox: @inbox, label: label, label_wa_id: label_wa_id, evento_em: @at,
                                   nome: @evento[:nome], color_index: @evento[:color_index], criada_pelo_celular: criada)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    raise unless tentar_de_novo && corrida?(e)

    correspondencia_travada || criar_correspondencia(tentar_de_novo: false)
  end

  # Só a corrida conta: índice único, ou o título do `Label` que outro evento acabou de gravar. Qualquer outro motivo sobe.
  def corrida?(erro)
    return true if erro.is_a?(ActiveRecord::RecordNotUnique)

    erro.record.is_a?(Label) && erro.record.errors.of_kind?(:title, :taken)
  end

  # O `Label` com o título técnico do nome: o que já existe na conta ou um novo. Devolve [label, criada_agora]. Corrida
  # pelo mesmo título cai no rescue de criar_correspondencia, que tenta de novo e acha o que o outro criou.
  def etiqueta_para_o_nome
    titulo = titulo_do_evento
    existente = conta.labels.find_by(title: titulo)
    return [existente, false] if existente

    [conta.labels.create!(title: titulo), true]
  end

  # Nome sem letra nem dígito aproveitável ("🔥", "A", vazio): o título vira `whatsapp_<id da etiqueta no celular>`.
  def titulo_do_evento
    titulo = self.class.titulo_tecnico(@evento[:nome])
    return titulo if titulo.length >= TAMANHO_MINIMO_DO_TITULO

    [PREFIXO_SEM_TITULO, self.class.titulo_tecnico(label_wa_id)].compact_blank.join(SEPARADOR)
  end

  # Apagada antes de criada (fora de ordem) deixa só a marca, sem `Label`, para o "criada" mais velho ser descartado.
  def apagar
    registro = correspondencia_travada
    if registro.nil?
      return Etiquetas::DoCelular.create!(account: conta, inbox: @inbox, label_wa_id: label_wa_id, evento_em: @at,
                                          apagada_em: @at, nome: @evento[:nome], color_index: @evento[:color_index])
    end
    return unless evento_novo_para?(registro)

    registro.update!(evento_em: @at, apagada_em: @at)
  end

  def desvincular
    registro = correspondencia_travada
    return descartar("#{self.class.name}: desvinculada sem correspondência label_wa_id=#{label_wa_id}") if registro&.label.nil?
    return descartar("#{self.class.name}: desvinculada de etiqueta apagada label_wa_id=#{label_wa_id}") if registro.apagada?

    trocar_no_contato(:remover, registro)
  end

  def trocar_no_contato(operacao, registro)
    return if registro.apagada?

    resultado = Etiquetas::EtiquetaNoContato.new(registro: registro, evento: @evento, at: @at).aplicar(operacao)
    descartar("#{resultado} label_wa_id=#{label_wa_id}") unless resultado == :aplicado
  end

  def descartar(motivo)
    Rails.logger.info("#{LOG} evento descartado: #{motivo} inbox=#{@evento[:inbox_id]} acao=#{@evento[:acao]}")
    nil
  end
end
