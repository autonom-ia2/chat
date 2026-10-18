# Contato pelo e-mail recebido (#1813): decide se vale chamar a IA e grava o que ela leu.
#
# Só lê o e-mail que saiu de um endereço do próprio contato (Crm::Email::Autoria#do_cliente?): o recebimento grava a
# mensagem em nome do contato da conversa (MailboxSanitizer), então a resposta de quem está em cópia não pode virar
# dado do dono.
#
# A gravação é a do Decisores::Aplicador, sem `trocar`: telefone só quando vazio (no formato +55..., pelo
# Decisores::Telefone, e o de outro contato vai para a biografia), e-mail só quando vazio — o e-mail do contato nunca é
# trocado. O nome, neste caminho, só quando está vazio, é o e-mail inteiro ou é o telefone (#nome_trocavel?): o começo
# do e-mail ("maria" de maria@x.com) pode ter sido digitado pelo atendente.
#
# Formulário de site: o e-mail sai do endereço fixo do site, que é o contato. Só grava quando o e-mail escrito no
# formulário é um endereço do próprio contato; senão juntaria vários clientes num contato só.
#
# A IA só é chamada quando há o que completar, há texto novo, há credencial e os freios deixam (Freios). Sem
# credencial: nada acontece, sem erro. O log leva só chaves e motivos, nunca o nome, o telefone ou o e-mail.
class Autonomia::ContatoPeloEmail::Completar
  Leitor = Autonomia::ContatoPeloEmail::Leitor
  # O Aplicador grava os campos que um Decisor declara. Aqui a lista é fixa e não há Decisor salvo na conta.
  Campos = Struct.new(:id, :account, :campos, keyword_init: true)
  CAMPOS = Leitor::CAMPOS.map { |chave, destino| { 'chave' => chave, 'destino' => destino } }.freeze
  LOG = '[autonomia][contato_pelo_email]'.freeze

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return unless vale_ler?

    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    return if credencial.blank?

    travado(credencial)
  rescue Leitor::Error => e
    # Sem nova tentativa: o próximo e-mail do mesmo contato tenta de novo, e repetir aqui só gastaria mais.
    Rails.logger.warn("#{LOG} message=#{@message.id} leitura falhou: #{e.message}")
  end

  private

  def contato
    @conversation.contact
  end

  # Tudo o que se confere sem gastar: a flag, o From do contato, a pausa, o que falta e o texto novo.
  def vale_ler?
    Autonomia::ContatoPeloEmail.ligado?(@account) && do_contato? && !freios.pausado? && falta_algo? &&
      Leitor.texto(@message).present?
  end

  def do_contato?
    contato.present? && contato == @message.sender && Crm::Email::Autoria.new(@account).do_cliente?(@message)
  end

  def falta_algo?
    nome_trocavel? || contato.phone_number.blank? || contato.email.blank?
  end

  # Mais estrito que o Aplicador (que também troca o nome igual ao começo do e-mail).
  def nome_trocavel?
    nome = contato.name.to_s.strip
    nome.empty? || nome.casecmp?(contato.email.to_s) || nome == contato.phone_number.to_s
  end

  def travado(credencial)
    token = freios.travar
    return motivo('em_andamento') if token.nil?

    begin
      ler_e_gravar(credencial)
    ensure
      freios.soltar(token)
    end
  end

  def ler_e_gravar(credencial)
    return motivo('ja_lido') unless freios.primeira_leitura?(@message.id)
    return motivo('teto_diario', nivel: :warn) unless freios.dentro_do_teto?

    leitura = Leitor.new(account: @account, credencial: credencial).ler(@message)
    return if leitura.nil?
    return automatico if leitura.tipo == Leitor::AUTOMATICO

    freios.zerar_automaticos
    return nada_novo('formulario_de_outro_endereco') if formulario_de_outro_endereco?(leitura)

    gravar(leitura)
  end

  def automatico
    motivo(freios.automatico! ? 'automatico_pausa' : 'automatico')
  end

  def formulario_de_outro_endereco?(leitura)
    leitura.tipo == Leitor::FORMULARIO &&
      !Crm::Email::Autoria.new(@account).endereco_do_cliente?(@message, leitura.valores['email'])
  end

  # A IA leva segundos: a ficha é relida sob trava (with_lock relê o registro) para não gravar por cima de quem a
  # editou nesse meio-tempo.
  def gravar(leitura)
    resultado, ignorados = contato.with_lock do
      fora = leitura.valores.key?('nome') && !nome_trocavel? ? ['nome'] : []
      [aplicador.aplicar(leitura.valores.except(*fora)), fora]
    end
    registrar(leitura.tipo, resultado, ignorados)
    freios.pausar_por_nada_novo if resultado.aplicados.empty?
  end

  def nada_novo(razao)
    motivo(razao)
    freios.pausar_por_nada_novo
  end

  def aplicador
    Autonomia::Decisores::Aplicador.new(decisor: Campos.new(id: 'contato_pelo_email', account: @account, campos: CAMPOS),
                                        conversation: @conversation)
  end

  def freios
    @freios ||= Autonomia::ContatoPeloEmail::Freios.new(account_id: @account.id, contato_id: contato.id)
  end

  def motivo(razao, nivel: :info)
    Rails.logger.public_send(nivel, "#{LOG} message=#{@message.id} contato=#{contato.id} motivo=#{razao}")
  end

  # Só as chaves e os motivos: o valor (nome, telefone, e-mail) não vai para o log.
  def registrar(tipo, resultado, ignorados)
    Rails.logger.info("#{LOG} message=#{@message.id} contato=#{contato.id} tipo=#{tipo} " \
                      "gravados=#{resultado.aplicados.keys.join(',')} " \
                      "recusados=#{(resultado.recusados.keys + ignorados).join(',')}")
  end
end
