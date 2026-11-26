# O AVISO DO PAGAMENTO DO SEGURO VIAGEM (#3246b): o evento que faz a Bia falar sem o cliente ter escrito. É o par do
# `Tools::Evento` da Lia, e não o reaproveita: aquele nasce de uma execução (`ToolRun`) e tem o slot dela; este nasce da
# proposta guardada na cotação (`CotacaoDeViagem#proposta`), que a conferência automática
# (`Contratados::ConferirPagamentoJob`) lê na Universal. A Lia fica como estava.
#
# O EVENTO É a cotação, o TIPO (lista fechada, `TIPOS`) e o `gerada_em` da proposta (em segundos) do momento em que ele
# foi disparado. Proposta trocada depois (outro carrinho, outro link) mata o evento: ele falaria do carrinho errado.
#
# A MARCA (`marca`, gravada em `CHAVE` na fala e na nota) é a idempotência: o retry do job e o evento repetido encontram a
# mensagem e não falam de novo. É também o `turno` do contexto de entrega (`Delivery#marca_do_evento`): o token do cartão
# do voucher fica igual entre as tentativas do mesmo evento.
#
# OS FATOS vão ao MODELO, nunca ao cliente como estão: nome do plano, data do pagamento e, no lembrete, até quando o link
# vale e o próprio link (para o botão). Nunca CPF, nome, e-mail: a proposta guardada nem os tem.
class Autonomia::Agents::Tools::EventoDaViagem
  CHAVE = 'autonomia_evento_da_viagem'.freeze
  PAGAMENTO_CONFIRMADO = 'pagamento_confirmado'.freeze
  LEMBRETE = 'lembrete_de_pagamento'.freeze
  TIPOS = [PAGAMENTO_CONFIRMADO, LEMBRETE].freeze
  CANCELADO = 'cancelado'.freeze
  # Até quando o link vale, para o cliente: a mesma folga de uma hora da proposta reaproveitada (a Universal cancela o
  # link 24 h depois da compra; `GerarPropostaSeguroViagem::VALIDADE_DO_LINK`).
  VALIDADE_DO_LINK = Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem::VALIDADE_DO_LINK
  VOUCHER = Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher
  HoraDoLembrete = Autonomia::Agents::Tools::Native::SeguroViagem::HoraDoLembrete

  DESCRICOES = {
    PAGAMENTO_CONFIRMADO => 'a conferência automática viu agora o pagamento da proposta desta conversa como pago. ' \
                            'Confirme com situacao_do_pagamento antes de falar; com "pago", o voucher em PDF sai logo ' \
                            'abaixo da sua mensagem.',
    LEMBRETE => 'a proposta desta conversa ainda não foi paga, e o link de pagamento vence em breve. É um lembrete; a ' \
                'pessoa não pediu nada agora.'
  }.freeze

  attr_reader :cotacao, :tipo, :gerada_em_i

  # O `gerada_em` da proposta como Time, ou nil quando falta ou não é ISO 8601. Sem regex: quem decide é o parser.
  def self.gerada_em(proposta)
    texto = proposta.to_h['gerada_em'].to_s
    return nil if texto.empty?

    Time.zone.iso8601(texto)
  rescue ArgumentError
    nil
  end

  # O `gerada_em` em segundos (o que o evento e a conferência carregam), ou nil.
  def self.gerada_em_i(proposta)
    gerada_em(proposta)&.to_i
  end

  def initialize(cotacao:, tipo:, gerada_em_i:)
    @cotacao = cotacao
    @tipo = tipo.to_s
    @gerada_em_i = gerada_em_i.to_i
  end

  def valido?
    TIPOS.include?(tipo)
  end

  def pagamento_confirmado?
    tipo == PAGAMENTO_CONFIRMADO
  end

  # A cotação existe e a proposta é a mesma de quando o evento nasceu.
  def vivo?
    cotacao.present? && self.class.gerada_em_i(proposta) == gerada_em_i
  end

  def proposta
    cotacao&.proposta.to_h
  end

  def conversation
    cotacao&.conversation
  end

  def marca
    "viagem:#{cotacao&.id}:#{gerada_em_i}:#{tipo}"
  end

  # -> por que o evento não tem mais o que dizer, ou nil. O voucher que já saiu ou que o turno do cliente já marcou (a
  # pessoa perguntou e a ferramenta cuidou); no lembrete, também o pagamento que chegou ou foi cancelado depois da
  # conferência, e a hora que passou (`SeguroViagem::HoraDoLembrete`: o evento pode ter esperado o turno do cliente, a
  # nova tentativa da IA ou a fila).
  def motivo_para_calar
    return 'voucher_ja_enviado' if proposta['voucher_enviado_em'].present?
    return motivo_do_pagamento if pagamento_confirmado?
    return 'ja_pago' if proposta['pago_em'].present?
    return 'cancelado' if proposta['situacao'] == CANCELADO

    HoraDoLembrete.motivo(cotacao, self.class.gerada_em(proposta))
  end

  # Na hora de postar, sob o lock da conversa (`ResponderAoEventoDaViagem#already_replied?`), com a proposta RELIDA do
  # banco: o voucher deste pagamento já saiu ou outro turno (o do cliente que perguntou "caiu?") já o marcou? O modelo
  # demora: o turno do cliente pode ter conferido o pagamento enquanto o aviso esperava a IA.
  def voucher_coberto_agora?
    return false unless pagamento_confirmado?

    voucher_de_outro_turno?(Autonomia::Agents::CotacaoDeViagem.where(id: cotacao&.id).pick(:proposta).to_h)
  end

  # -> a mensagem desta conversa (pública ou nota) que já carrega a marca, ou nil. O `LIKE` é a peneira; quem decide é o
  # atributo, como em `Tools::Evento#mensagem`.
  # `com_marca`: outra marca deste evento (a nota do voucher que não foi, `AvisoDaViagem#notar_sem_voucher`).
  def mensagem(conversa = conversation, com_marca: marca)
    return nil if conversa.blank?

    conversa.messages.where('content_attributes::text LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(com_marca)}%")
            .detect { |message| message.content_attributes.to_h[CHAVE].to_s == com_marca }
  end

  def publicado?(conversa = conversation)
    mensagem(conversa).present?
  end

  # A `ancora` grava o cartão do voucher desta cotação (`CartoesDoTurno.da_ancora`)?
  def voucher_na_ancora?(ancora)
    ::Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(ancora)
                                                .any? { |cartao| VOUCHER.cartao?(cartao) && cartao['chave'].to_s == cotacao.id.to_s }
  end

  # O que o modelo recebe no lugar da mensagem do cliente.
  def nota_do_sistema
    [
      'AVISO DO SISTEMA SOBRE O PAGAMENTO DO SEGURO VIAGEM DESTA CONVERSA. Isto não é mensagem da pessoa: é o sistema ' \
      'contando o que aconteceu, para você falar com ela agora, na sua voz.',
      "O que aconteceu: #{DESCRICOES.fetch(tipo, tipo)}",
      "Fatos: #{fatos}"
    ].join("\n")
  end

  # Os fatos, para o modelo e para a nota da equipe. `com_link`: o link de pagamento entra (o botão do lembrete).
  def fatos(com_link: true)
    partes = ["plano #{nome_do_plano || proposta['codigo_do_plano']}"]
    partes += pagamento_confirmado? ? do_pagamento : do_link(com_link)
    "#{partes.join('; ')}."
  end

  private

  def motivo_do_pagamento
    'voucher_marcado_por_outro_turno' if voucher_de_outro_turno?(proposta)
  end

  # O voucher já saiu, ou o cartão dele foi marcado por um turno do cliente que não é este evento
  # (`EntregaDoVoucher.marcar`) E esse turno postou a âncora pública com o cartão do voucher desta cotação. A marca do
  # próprio evento (o modelo chamou `situacao_do_pagamento` no turno do aviso) não cala. A marca sem âncora (a IA falhou,
  # o turno foi superado, o cartão foi descartado, ou o turno ainda não postou) também não: o aviso fala e manda o
  # voucher, e o `saiu_depois?` barra o segundo PDF de quem postar depois.
  def voucher_de_outro_turno?(atual)
    return true if atual['voucher_enviado_em'].present?

    marcado = atual[VOUCHER::MARCADO_NO_TURNO].to_s
    marcado.present? && marcado != marca && ancora_com_o_voucher?(atual[VOUCHER::MARCADO_NA_MENSAGEM])
  end

  # A âncora pública do turno aberto pela mensagem `mensagem_id` leva o cartão do voucher desta cotação, ainda a enviar?
  def ancora_com_o_voucher?(mensagem_id)
    return false if mensagem_id.blank? || conversation.blank?

    ancora = ::Autonomia::Agents::Operate::CartoesDoTurno.ancora_do_turno(conversation, mensagem_id)
    return false unless ancora_a_enviar?(ancora)

    voucher_na_ancora?(ancora)
  end

  # Pública e sem a desistência gravada (`CartoesDoTurno#encerrar!`): a âncora encerrada não manda mais o cartão.
  def ancora_a_enviar?(ancora)
    ancora.present? && !ancora.private &&
      ancora.content_attributes.to_h[::Autonomia::Agents::Operate::CartoesDoTurno::ENCERRADOS].blank?
  end

  def do_pagamento
    data = data_curta(proposta['pago_em'])
    data ? ["pago em #{data}"] : []
  end

  def do_link(com_link)
    link = proposta['link'].presence if com_link
    ["o link de pagamento vale até #{vence_em}", (link && "link de pagamento: #{link}")].compact
  end

  def nome_do_plano
    cotacao&.plano(proposta['codigo_do_plano'])&.dig('nome').presence
  end

  # dd/mm. A `dataPagamento` da Universal vem sem fuso: vale como está. A hora que nós gravamos (com fuso) vai para o fuso
  # da conta. Sem regex: as partes vêm do parser ISO 8601 do Ruby.
  def data_curta(texto)
    partes = Date._iso8601(texto.to_s)
    return nil unless partes[:year] && partes[:mon] && partes[:mday]
    return Time.zone.iso8601(texto).in_time_zone(fuso).strftime('%d/%m') if partes.key?(:offset)

    format('%<dia>02d/%<mes>02d', dia: partes[:mday], mes: partes[:mon])
  rescue ArgumentError
    nil
  end

  # "dd/mm às HH:MM (no fuso da conta)".
  def vence_em
    momento = (Time.zone.at(gerada_em_i) + VALIDADE_DO_LINK).in_time_zone(fuso)
    "#{momento.strftime('%d/%m às %H:%M')} (no fuso da conta)"
  end

  def fuso
    @fuso ||= Crm::Timezone::Resolver.new(account: cotacao.account).zone_or_default
  end
end
