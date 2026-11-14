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
# a lista gravou; e nenhum card dela foi ganho desde que a lista existe (a criação da importação), nem que
# tenha sido arquivado depois de ganho (Crm::Card.com_desfecho, o filtro dos números e das metas). O ganho
# chama Contact#become_customer!, que não mexe em quem já é cliente: sem a terceira condição, quem comprou de verdade
# voltaria a lead. Conta-se da criação da importação, e não do instante em que a linha foi gravada, porque o ganho que
# acontece enquanto o bloco da linha é gravado espera a trava da pessoa e fica com a hora de antes da anotação. Quem
# ganhou um card nesse intervalo antes de a lista chegar à linha já era cliente, e a lista nem a anotou. A pessoa volta
# ao tipo que tinha antes (Contact#revert_customer!), não sempre a lead. Sem o tipo de antes anotado (ou com um tipo
# para o qual não se volta), a marca não volta e a prévia não a conta: não há para onde voltar.
#
# `devolver!` recebe os campos de uma mesma pessoa (ou empresa) e os devolve juntos, sob uma trava só: os campos comuns
# numa gravação, a marca de cliente na gravação dela (Contact#revert_customer!; são duas gravações quando a pessoa tem
# os dois) e uma marca de "devolvido" para todos, em vez de uma por campo. Nenhuma dessas gravações avisa "contato
# mudou": o Desfazer as faz com os avisos suprimidos (Relacionamentos::Trazer::Desfazer). Roda sob a trava do registro
# e confere de novo, com ele relido, o que só ele sabe: o valor de hoje e se a pessoa continua cliente. A procura é a
# do bloco (Relacionamentos::Trazer::CamposDaLista a lê uma vez por bloco, logo antes de entregar): não é consultada de
# novo por pessoa. O ganho do bloco tira da fila quem já tinha ganho; para quem vai deixar de ser cliente, ele é
# consultado de novo sob a trava da pessoa (parecer de Multifunnel): o card ganho depois de o bloco ser lido não mexe
# em quem já é cliente, e sem a consulta quem comprou no meio do Desfazer voltaria a lead. É uma consulta a mais por
# pessoa, só na marca de cliente. A gravação pula as validações, como a marca de cliente e a recusa
# (ContactCustomer, ContactOptOut): esvaziar um campo não cria dado fora do formato, e o dado antigo fora do formato
# não pode impedir o Desfazer.
#
# O campo que nunca vai voltar sai da fila já na primeira passada, marcado como os devolvidos: o de quem não existe mais
# e a marca de cliente sem tipo de antes. Sem isso a linha ficaria pendente para sempre.
class Relacionamentos::Trazer::CampoQueVolta
  Campo = Relacionamentos::CampoPreenchido
  CIDADE = ContactImports::Trazer::DestinosDaLinha::CIDADE
  TELEFONE = ContactImports::Trazer::DestinosDaLinha::TELEFONE_DA_EMPRESA
  TIPOS_DE_ANTES = ContactCustomer::TYPES_BEFORE_CUSTOMER

  attr_reader :alvo

  # campos: os de um mesmo alvo, todos com o mesmo objeto (Relacionamentos::Trazer::CamposDaLista monta assim).
  # Devolve quantos voltaram.
  def self.devolver!(campos)
    alvo = campos.first.alvo
    if alvo.nil?
      marcar(campos)
      return 0
    end

    alvo.with_lock do
      de_cliente, comuns = campos.select(&:volta?).partition(&:cliente?)
      esvaziar(alvo, comuns)
      voltaram = comuns + de_cliente.select(&:desmarcar_cliente)
      marcar(voltaram + campos.select(&:sem_tipo_de_antes?))
      voltaram.size
    end
  end

  # Uma escrita para todos os campos do alvo.
  def self.marcar(campos)
    return if campos.empty?

    agora = Time.current
    Campo.where(id: campos.map(&:registro_id)).update_all(devolvido_em: agora, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
  end

  def self.esvaziar(alvo, campos)
    return if campos.empty?

    campos.each { |campo| alvo.assign_attributes(campo.vazio) }
    alvo.save!(validate: false)
  end

  # alvo: a pessoa de hoje, ou a empresa da linha quando o campo é o telefone da empresa; nil quando não existe mais.
  # desde: a criação da importação, de onde se conta o card ganho. ganhou: a pessoa tem card ganho de lá para cá (só
  # importa para "cliente"). procurada: a conta a procurou de lá para cá (só importa para telefone e e-mail). Os dois
  # últimos vêm do bloco (Relacionamentos::Trazer::CamposDaLista).
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
    return @alvo.customer? && !@ganhou && tipo_de_antes.present? if cliente?

    !(@registro.de_contato? && @procurada)
  end

  def cliente?
    @registro.campo == Campo::CLIENTE
  end

  # Daqui para baixo, o que `devolver!` usa, sempre sob a trava do alvo.

  def registro_id
    @registro.id
  end

  # A marca de cliente que não tem para onde voltar: a anotação não diz o tipo de antes (ou diz um para o qual não se volta).
  def sem_tipo_de_antes?
    cliente? && tipo_de_antes.nil?
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
    @alvo.revert_customer!(to: tipo_de_antes) { volta? && !ganhou_desde_o_bloco? }
  end

  private

  # O card ganho entre a leitura do bloco e a trava da pessoa, arquivado depois ou não: a mesma conta do bloco
  # (Relacionamentos::Trazer::CamposDaLista#quem_ganhou), feita de novo com a pessoa travada.
  def ganhou_desde_o_bloco?
    Crm::Card.com_desfecho(:won).exists?(account_id: @alvo.account_id, contact_id: @alvo.id, closed_at: @desde..)
  end

  # 'visitor' ou 'lead'; nil quando a anotação não tem o tipo de antes ou tem um para o qual não se volta.
  def tipo_de_antes
    tipo = Contact.contact_types.key(@registro.tipo_anterior)
    tipo if TIPOS_DE_ANTES.include?(tipo)
  end

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
