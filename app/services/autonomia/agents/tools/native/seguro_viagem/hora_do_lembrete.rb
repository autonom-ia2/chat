# A HORA DO LEMBRETE DE PAGAMENTO DO SEGURO VIAGEM (#3246b). Conferida duas vezes, com a mesma régua: quando a
# conferência automática decide lembrar (`Contratados::ConferirPagamentoJob`) e de novo quando a Bia vai falar
# (`Tools::EventoDaViagem#motivo_para_calar`), porque entre uma e outra o evento pode ter esperado o turno do cliente, a
# nova tentativa da IA ou a fila.
#
#   - entre 12 h e 23 h depois da proposta: o link vence em 24 h, e a proposta é reaproveitada até 23 h;
#   - a hora local da conta entre 8 h e antes das 21 h;
#   - a cotação é a mais nova com proposta da conversa (de qualquer agente): a mais velha não lembra de um link que a
#     pessoa já trocou.
class Autonomia::Agents::Tools::Native::SeguroViagem::HoraDoLembrete
  A_PARTIR_DE = 12.hours
  ATE = 23.hours
  # A hora local da conta em que o lembrete pode sair: das 8 h até antes das 21 h.
  HORARIO = (8...21)

  # -> por que não é hora de lembrar (rótulo de lista fechada), ou nil. `gerada_em`: a hora da proposta (Time).
  def self.motivo(cotacao, gerada_em, agora: Time.current)
    idade = agora - gerada_em
    return 'fora_do_prazo' unless idade >= A_PARTIR_DE && idade < ATE
    return 'fora_do_horario' unless HORARIO.cover?(agora.in_time_zone(fuso(cotacao)).hour)

    'proposta_mais_velha' unless mais_nova_com_proposta?(cotacao)
  end

  def self.mais_nova_com_proposta?(cotacao)
    ::Autonomia::Agents::CotacaoDeViagem.where(conversation_id: cotacao.conversation_id)
                                        .where("proposta->>'codigo_carrinho' IS NOT NULL").maximum(:id) == cotacao.id
  end

  def self.fuso(cotacao)
    Crm::Timezone::Resolver.new(account: cotacao.account).zone_or_default
  end
end
