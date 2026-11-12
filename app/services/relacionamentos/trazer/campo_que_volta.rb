# "Trazer minha lista" (#2896): um campo que a lista preencheu (Relacionamentos::CampoPreenchido), diante da pessoa ou
# da empresa como estão hoje. Diz se o campo volta (`volta?`, que a prévia conta) e o devolve (`devolver!`, do Desfazer).
#
# O campo só volta quando o valor de hoje ainda é o que a lista pôs: quem mudou o valor depois fica com o que escreveu.
# Voltar é esvaziar, porque a lista só preenche o que estava vazio. A pessoa (ou a empresa) que não existe mais, apagada
# ou mesclada em outra, é pulada.
#
# "Cliente" tem três condições a mais, combinadas com Multifunnel: a pessoa continua cliente; a data de cliente é a que
# a lista gravou; e nenhum card dela foi ganho desde que a lista existe (`desde`, a criação da importação). O ganho
# chama Contact#become_customer!, que não mexe em quem já é cliente: sem a terceira condição, quem comprou de verdade
# voltaria a lead. Conta-se da criação da importação, e não do instante em que a linha foi gravada, porque o ganho que
# acontece enquanto o bloco da linha é gravado espera a trava da pessoa e fica com a hora de antes da anotação. Quem
# ganhou um card nesse intervalo antes de a lista chegar à linha já era cliente, e a lista nem a anotou. A pessoa volta
# ao tipo que tinha antes (Contact#revert_customer!), não sempre a lead.
#
# `devolver!` roda sob a trava do registro e confere tudo de novo com ele relido; o ganho é consultado ali, na hora. A
# gravação pula as validações, como a marca de cliente e a recusa (ContactCustomer, ContactOptOut): esvaziar um campo
# não cria dado fora do formato, e o dado antigo fora do formato não pode impedir o Desfazer.
class Relacionamentos::Trazer::CampoQueVolta
  Campo = Relacionamentos::CampoPreenchido
  CIDADE = ContactImports::Trazer::DestinosDaLinha::CIDADE
  TELEFONE = ContactImports::Trazer::DestinosDaLinha::TELEFONE_DA_EMPRESA

  # alvo: a pessoa de hoje, ou a empresa da linha quando o campo é o telefone da empresa; nil quando não existe mais.
  # desde: a criação da importação. ganhou: a pessoa tem card ganho de lá para cá (só importa para "cliente").
  def initialize(registro, alvo:, desde:, ganhou: false)
    @registro = registro
    @alvo = alvo
    @desde = desde
    @ganhou = ganhou
  end

  # A pessoa a quem o campo volta; nil quando o campo é da empresa.
  def pessoa_id
    @registro.contact_id unless @registro.da_empresa?
  end

  def volta?
    return false if @alvo.nil? || !@registro.mesmo_valor?(atual)

    !cliente? || (@alvo.customer? && !@ganhou)
  end

  # Devolve se o campo voltou.
  def devolver!
    return false if @alvo.nil?

    @alvo.with_lock do
      @ganhou = @alvo.crm_cards.won.exists?(closed_at: @desde..) if cliente?
      next false unless volta? && esvaziar

      @registro.update!(devolvido_em: Time.current)
      true
    end
  end

  private

  def cliente?
    @registro.campo == Campo::CLIENTE
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

  def esvaziar
    return @alvo.revert_customer!(to: Contact.contact_types.key(@registro.tipo_anterior)) { volta? } if cliente?

    @alvo.assign_attributes(vazio)
    @alvo.save!(validate: false)
  end

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
end
