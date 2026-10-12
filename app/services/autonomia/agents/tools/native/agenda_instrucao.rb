# A INSTRUÇÃO "# Agenda" do turno (#1196, #1305, #1307): o que a IA lê sobre a agenda, conforme o estado da página
# (`Native::Agenda.estado`). Marcando: como oferecer, com quem marcar, confirmar (`cliente_confirmou`) e mandar o
# link de gestão. Sem marcar (página apagada, pausada, sem quem atenda, agenda de quem atende pausada): não oferecer
# nada e passar para uma pessoa, com o motivo.
#
# PRECEDÊNCIA: a instrução da agenda vale sobre regra anterior do agente que mande só anotar, nunca consultar a
# agenda ou encaminhar à equipe quem quer remarcar ou cancelar (agentes `scheduler` antigos têm essas regras
# gravadas). Remarcar e cancelar é pelo link de gestão.
#
# COM QUEM MARCAR (#1307): a instrução lista as pessoas liberadas pelo nome e manda seguir a instrução do dono; sem
# ela, preferir quem atende a conversa (se estiver liberado); senão, oferecer os horários das liberadas. QUEM DECIDE É
# O MODELO: o código só lista quem pode e confere o `pessoa_id` que o modelo manda.
#
# FUSO (#1362): o fuso é dado das ferramentas (`fuso`, `inicio` com offset); a instrução manda falar o horário sem
# ele, salvo se o cliente perguntar ou estiver em outro fuso. Quem percebe isso é o modelo; aqui nada lê texto.
#
# PRAZO (#1305): com `cancel_until_minutes`, o link de gestão só muda ou cancela até esse prazo (`ManageMeeting`
# devolve `too_late` depois); a instrução diz o prazo.
module Autonomia::Agents::Tools::Native::AgendaInstrucao
  ATIVA = <<~TEXT.strip.freeze
    # Agenda
    Você tem a agenda deste atendimento e PODE oferecer horários e marcar reuniões. Esta seção vale sobre qualquer
    regra anterior que diga para só anotar a preferência, nunca consultar a agenda ou passar para a equipe quem quer
    remarcar ou cancelar: para remarcar ou cancelar, siga o que esta seção diz.
    %<pessoas>s
    - Quando o cliente quiser marcar, chame `horarios_disponiveis` e ofereça 2 ou 3 opções, com dia da semana, hora e
      com quem é.
    - Só ofereça horário que a ferramenta devolveu. NUNCA invente horário nem confirme sem a ferramenta.
    - Os horários estão no fuso desta agenda (o campo `fuso` das ferramentas). Fale o horário sem citar o fuso, salvo
      se o cliente perguntar ou disser que está em outro fuso: aí use o campo `fuso` (e o offset do `inicio`) para
      explicar ou converter.
    - Antes de marcar, repita ao cliente o dia, a hora, o local e com quem é, e pergunte se pode marcar. Só depois que
      ele disser que sim, chame `agendar_reuniao` com o horário exatamente como a ferramenta devolveu, o `pessoa_id`
      desse horário e `cliente_confirmou: true`.
    - Só diga que está marcado quando `agendar_reuniao` confirmar. Na confirmação, mande ao cliente o `link_de_gestao`
      (por ele o cliente confirma, muda ou cancela%<prazo>s) e, se vier, o `link_da_reuniao` ou o `endereco`.
    - Para remarcar ou cancelar, mande o link de gestão que você enviou ao marcar%<prazo>s. Só sem esse link na
      conversa, passe para uma pessoa da equipe. Você não remarca nem cancela.
    - Se a ferramenta recusar, siga o que ela disser: pedir um dado, oferecer as novas opções ou passar para uma pessoa.
  TEXT

  UMA_PESSOA = '- Você marca com %<nome>s (pessoa_id %<id>s).'.freeze
  VARIAS_PESSOAS = <<~TEXT.strip.freeze
    - Pessoas com quem você pode marcar: %<lista>s.
    - Com quem marcar: siga a instrução do dono deste atendimento sobre com quem marcar. Se ela não disser, prefira
      quem atende esta conversa, se essa pessoa estiver na lista (`horarios_disponiveis` diz quem é, em
      `quem_atende_esta_conversa`). Senão, ofereça os horários das pessoas da lista. Se o cliente pedir uma pessoa
      da lista, use os horários dela. Para ver só os de uma pessoa, chame `horarios_disponiveis` com o `pessoa_id`
      dela; sem ele, vêm os de todas, cada horário com a pessoa.
  TEXT

  INDISPONIVEL = <<~TEXT.strip.freeze
    # Agenda
    A agenda deste atendimento está indisponível agora (motivo: %<motivo>s). NÃO ofereça horário, NÃO diga que vai
    marcar e NÃO prometa encaixe. Se o cliente quiser marcar, remarcar ou cancelar, diga com suas palavras que uma
    pessoa da equipe vai cuidar disso e passe a conversa: should_handoff=true, handoff_reason "agendamento indisponível".
    Isto vale sobre qualquer regra anterior que mande oferecer horários.
  TEXT

  MINUTOS_POR_HORA = 60

  # `pessoas`: as liberadas que podem atender (`AgendaPessoas#atendem`), na ordem da página.
  def self.para(estado, pessoas: [], prazo_minutos: nil)
    return format(INDISPONIVEL, motivo: estado) unless estado == ::Autonomia::Agents::Tools::Native::Agenda::ATIVA

    limite = prazo(prazo_minutos)
    format(ATIVA, pessoas: com_quem(pessoas), prazo: limite ? ", só #{limite}" : '')
  end

  def self.com_quem(pessoas)
    nomes = pessoas.map { |pessoa| { nome: pessoa.user.available_name, id: pessoa.user.id } }
    return '' if nomes.empty?
    return format(UMA_PESSOA, nomes.first) if nomes.one?

    format(VARIAS_PESSOAS, lista: nomes.map { |pessoa| "#{pessoa[:nome]} (pessoa_id #{pessoa[:id]})" }.join(', '))
  end

  # "até 24 horas antes do horário" | "até 90 minutos antes do horário" | nil (sem prazo).
  def self.prazo(minutos)
    total = minutos.to_i
    return if total <= 0

    horas, resto = total.divmod(MINUTOS_POR_HORA)
    unidade = horas == 1 ? 'hora' : 'horas'
    quanto = resto.zero? ? "#{horas} #{unidade}" : "#{total} minutos"
    "até #{quanto} antes do horário"
  end
end
