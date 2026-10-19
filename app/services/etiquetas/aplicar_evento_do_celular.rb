# Aplica na plataforma um evento de etiqueta do app WhatsApp Business do celular (#1823, F1b). Contrato do evento no
# WhatsappLabels::AplicarEvento. Regras (decisões do Rodrigo):
# - Sem a flag `etiquetas_do_celular` na conta da caixa: descarta.
# - criada / renomeada: grava a correspondência (Etiquetas::DoCelular) com o nome e a cor do celular. Sem correspondência,
#   cria o `Label` com o título técnico derivado do nome ("Novo cliente 🔥" vira `novo_cliente`) ou reaproveita o que já
#   tem esse título. Renomear não muda o título nem o nome livre daqui: só o nome do celular. Nome vazio não apaga o
#   nome guardado.
# - apagada: a correspondência deixa de valer (fica a marca `apagada_em`); o `Label` fica, com tudo em que já está.
# - vinculada / desvinculada: põe ou tira a etiqueta do contato e da conversa não resolvida mais recente dele na caixa
#   (Etiquetas::EtiquetaNoContato). Nunca mudam o nome nem a cor de uma correspondência que já existe. Vinculada sem
#   correspondência cria como em criada; desvinculada sem correspondência, e as duas com a etiqueta apagada no celular,
#   só deixam log.
# Ordem: os eventos de uma etiqueta do celular passam um de cada vez (trava na linha da correspondência) e o `at` decide,
# em dois relógios separados: criada/renomeada/apagada contra o último evento da etiqueta (`evento_em`), e
# vinculada/desvinculada contra o último do mesmo contato (Etiquetas::DoCelularNoContato). Evento mais velho que o do seu
# relógio é descartado com log. Repetir o evento não duplica nada.
# Travas, sempre nesta ordem: correspondência → contato → conversa. A nota de atividade na conversa só é enfileirada
# depois do commit. Erro não é engolido: sobe para o job; evento malformado (EventoInvalido) o job descarta com log.
class Etiquetas::AplicarEventoDoCelular
  # Evento que nunca vai dar certo (ação desconhecida, `at` inválido): o job descarta em vez de tentar de novo.
  class EventoInvalido < ArgumentError; end

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
    palavras = palavras_por_espaco(nome.to_s.unicode_normalize(:nfc).downcase)
    titulo = palavras.map { |palavra| palavra.each_char.select { |ch| caractere_aceito?(ch) }.join }
                     .compact_blank.join(SEPARADOR)
    titulo = titulo[1..] while titulo.start_with?(SEPARADOR, '-')
    titulo
  end

  # Como o `split(' ')` do JS: só o espaço separa (tab e quebra de linha caem no filtro de caracteres). O `split(' ')` do
  # Ruby separaria por qualquer espaço em branco.
  def self.palavras_por_espaco(texto)
    texto.each_char.chunk { |ch| ch == ' ' ? :_separator : true }.map { |_, letras| letras.join }
  end

  def self.caractere_aceito?(caractere)
    caractere.downcase != caractere.upcase || ACEITOS_ALEM_DE_LETRA.include?(caractere)
  end

  def initialize(evento)
    @evento = evento.to_h.with_indifferent_access
    @notas = []
  end

  def perform
    acao = @evento[:acao].to_s
    raise EventoInvalido, "#{LOG} ação desconhecida: #{acao.inspect}" unless ACOES.include?(acao)

    @at = momento_do_evento
    @inbox = Inbox.find_by(id: @evento[:inbox_id])
    return descartar('caixa não existe mais') if @inbox.nil?
    return descartar('flag desligada na conta') unless conta.feature_enabled?(FLAG)

    ActiveRecord::Base.transaction { aplicar(acao) }
    @notas.each(&:enfileirar)
    nil
  end

  private

  def aplicar(acao)
    case acao
    when 'criada', 'renomeada' then registrar_etiqueta
    when 'apagada' then apagar
    when 'vinculada' then vincular
    when 'desvinculada' then desvincular
    end
  end

  def momento_do_evento
    Time.iso8601(@evento[:at].to_s)
  rescue ArgumentError
    raise EventoInvalido, "#{LOG} at inválido: #{@evento[:at].inspect}"
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

  # criada / renomeada: a correspondência com o nome e a cor deste evento, se ele não for mais velho que o último evento
  # da etiqueta. Nome vazio não apaga o guardado.
  def registrar_etiqueta
    registro = correspondencia_travada || criar_correspondencia
    return if registro.previously_new_record?
    return unless evento_novo_para?(registro)

    atributos = { color_index: @evento[:color_index], evento_em: @at, apagada_em: nil }
    atributos[:nome] = @evento[:nome] if @evento[:nome].present?
    registro.update!(**atributos, **etiqueta_se_faltar(registro))
  end

  # vinculada: a correspondência como está (cria se não houver, como em criada). Nome, cor e o relógio da etiqueta não
  # mudam; a ordem do vínculo é a do contato.
  def vincular
    registro = correspondencia_travada || criar_correspondencia
    return descartar("vinculada de etiqueta apagada no celular label_wa_id=#{label_wa_id}") if registro.apagada?

    trocar_no_contato(:adicionar, registro)
  end

  def evento_novo_para?(registro)
    return true if @at >= registro.evento_em

    descartar("mais velho que o último aplicado (#{registro.evento_em.iso8601}) label_wa_id=#{label_wa_id}")
    false
  end

  # A marca de apagada que chegou antes da criação não tem `Label`: ganha um agora (com a mesma proteção de corrida).
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
  rescue ActiveRecord::RecordNotUnique
    raise unless tentar_de_novo

    correspondencia_travada || criar_correspondencia(tentar_de_novo: false)
  end

  # Só a corrida conta: índice único, ou o título do `Label` que outro evento acabou de gravar. Qualquer outro motivo sobe.
  def corrida?(erro)
    return true if erro.is_a?(ActiveRecord::RecordNotUnique)

    erro.record.is_a?(Label) && erro.record.errors.of_kind?(:title, :taken)
  end

  # O `Label` com o título técnico do nome: o que já existe na conta ou um novo. Devolve [label, criada_agora]. Outro evento
  # criando o mesmo título ao mesmo tempo: desfaz só esta tentativa (savepoint) e reaproveita o dele.
  def etiqueta_para_o_nome(tentar_de_novo: true)
    titulo = titulo_do_evento
    existente = conta.labels.find_by(title: titulo)
    return [existente, false] if existente

    [Label.transaction(requires_new: true) { conta.labels.create!(title: titulo) }, true]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    raise unless tentar_de_novo && corrida?(e)

    etiqueta_para_o_nome(tentar_de_novo: false)
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
    no_contato = Etiquetas::EtiquetaNoContato.new(registro: registro, evento: @evento, at: @at)
    resultado = no_contato.aplicar(operacao)
    return descartar("#{resultado} label_wa_id=#{label_wa_id}") unless resultado == :aplicado

    @notas << no_contato.nota if no_contato.nota
  end

  def descartar(motivo)
    Rails.logger.info("#{LOG} evento descartado: #{motivo} inbox=#{@evento[:inbox_id]} acao=#{@evento[:acao]}")
    nil
  end
end
