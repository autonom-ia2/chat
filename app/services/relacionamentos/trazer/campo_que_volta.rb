# "Trazer minha lista" (#2896): um campo que a lista preencheu (Relacionamentos::CampoPreenchido), diante da pessoa ou
# da empresa como estão hoje. Diz se o campo volta (`volta?`, que a prévia conta) e o devolve (`devolver!`, do Desfazer).
#
# O campo só volta quando o valor de hoje ainda é o que a lista pôs: quem mudou o valor depois fica com o que escreveu.
# Voltar é esvaziar, porque a lista só preenche o que estava vazio. A pessoa (ou a empresa) que não existe mais, apagada
# ou mesclada em outra, é pulada.
#
# O telefone e o e-mail têm uma condição a mais: não voltam em quem a conta já procurou desde a lista (conversa ou
# campanha de lá para cá, Relacionamentos::Trazer::QuemFoiProcurado). A conta já falou com a pessoa por ali.
#
# "Cliente" tem três condições a mais, combinadas com Multifunnel: a pessoa continua cliente; a data de cliente é a que
# a lista gravou; e nenhum card dela foi ganho desde que a lista existe (`desde`, a criação da importação). O ganho
# chama Contact#become_customer!, que não mexe em quem já é cliente: sem a terceira condição, quem comprou de verdade
# voltaria a lead. Conta-se da criação da importação, e não do instante em que a linha foi gravada, porque o ganho que
# acontece enquanto o bloco da linha é gravado espera a trava da pessoa e fica com a hora de antes da anotação. Quem
# ganhou um card nesse intervalo antes de a lista chegar à linha já era cliente, e a lista nem a anotou. A pessoa volta
# ao tipo que tinha antes (Contact#revert_customer!), não sempre a lead.
#
# `devolver!` recebe os campos de uma mesma pessoa (ou empresa) e os devolve juntos: uma trava, uma gravação e um aviso
# de "contato mudou", em vez de um por campo. Roda sob a trava do registro e confere tudo de novo com ele relido; o
# ganho e a procura são consultados ali, na hora. A marca de cliente tem a gravação dela (Contact#revert_customer!). A
# gravação pula as validações, como a marca de cliente e a recusa (ContactCustomer, ContactOptOut): esvaziar um campo
# não cria dado fora do formato, e o dado antigo fora do formato não pode impedir o Desfazer.
class Relacionamentos::Trazer::CampoQueVolta
  Campo = Relacionamentos::CampoPreenchido
  CIDADE = ContactImports::Trazer::DestinosDaLinha::CIDADE
  TELEFONE = ContactImports::Trazer::DestinosDaLinha::TELEFONE_DA_EMPRESA

  attr_reader :alvo

  # campos: os de um mesmo alvo, todos com o mesmo objeto (Relacionamentos::Trazer::CamposDaLista monta assim).
  # Devolve quantos voltaram.
  def self.devolver!(campos)
    alvo = campos.first.alvo
    return 0 if alvo.nil?

    alvo.with_lock do
      de_cliente, comuns = campos.select(&:volta_agora?).partition(&:cliente?)
      esvaziar(alvo, comuns)
      voltaram = comuns + de_cliente.select(&:desmarcar_cliente)
      voltaram.each(&:marcar_devolvido)
      voltaram.size
    end
  end

  def self.esvaziar(alvo, campos)
    return if campos.empty?

    campos.each { |campo| alvo.assign_attributes(campo.vazio) }
    alvo.save!(validate: false)
  end

  # alvo: a pessoa de hoje, ou a empresa da linha quando o campo é o telefone da empresa; nil quando não existe mais.
  # desde: a criação da importação. ganhou: a pessoa tem card ganho de lá para cá (só importa para "cliente").
  # procurada: a conta a procurou de lá para cá (só importa para telefone e e-mail).
  def initialize(registro, alvo:, desde:, ganhou: false, procurada: false)
    @registro = registro
    @alvo = alvo
    @desde = desde
    @ganhou = ganhou
    @procurada = procurada
  end

  # A pessoa a quem o campo volta; nil quando o campo é da empresa.
  def pessoa_id
    @registro.contact_id unless @registro.da_empresa?
  end

  def volta?
    return false if @alvo.nil? || !@registro.mesmo_valor?(atual)
    return @alvo.customer? && !@ganhou if cliente?

    !(@registro.de_contato? && @procurada)
  end

  # Daqui para baixo, o que `devolver!` usa, sempre sob a trava do alvo.

  # Com o ganho e a procura consultados na hora.
  def volta_agora?
    @ganhou = @alvo.crm_cards.won.exists?(closed_at: @desde..) if cliente?
    @procurada = Relacionamentos::Trazer::QuemFoiProcurado.new(@alvo.account_id, desde: @desde).procurada?(@alvo.id) if @registro.de_contato?
    volta?
  end

  def cliente?
    @registro.campo == Campo::CLIENTE
  end

  # O que gravar no alvo para o campo ficar vazio. Lê o alvo como está agora, já com os campos anteriores esvaziados.
  def vazio
    case @registro.campo
    when *Campo::DA_FICHA.keys
      atributo = Campo::DA_FICHA.fetch(@registro.campo)
      { atributo => @alvo.class.column_defaults[atributo] }
    when Campo::CIDADE then { additional_attributes: @alvo.additional_attributes.to_h.except(CIDADE) }
    when Campo::TELEFONE_DA_EMPRESA then { additional_attributes: @alvo.additional_attributes.to_h.except(TELEFONE) }
    when Campo::EMPRESA then { company_id: nil }
    else { custom_attributes: @alvo.custom_attributes.to_h.except(@registro.informacao) }
    end
  end

  def desmarcar_cliente
    @alvo.revert_customer!(to: Contact.contact_types.key(@registro.tipo_anterior)) { volta? }
  end

  def marcar_devolvido
    @registro.update!(devolvido_em: Time.current)
  end

  private

  def atual
    case @registro.campo
    when *Campo::DA_FICHA.keys then @alvo[Campo::DA_FICHA.fetch(@registro.campo)]
    when Campo::CIDADE then @alvo.additional_attributes.to_h[CIDADE]
    when Campo::TELEFONE_DA_EMPRESA then @alvo.additional_attributes.to_h[TELEFONE]
    when Campo::EMPRESA then @alvo.company_id
    when Campo::CLIENTE then Campo.instante(@alvo.customer_since)
    else @alvo.custom_attributes.to_h[@registro.informacao]
    end
  end
end
