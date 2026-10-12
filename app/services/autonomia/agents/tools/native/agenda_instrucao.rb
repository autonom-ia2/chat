# A INSTRUÇÃO "# Agenda" do turno (#1196, #1305): o que a IA lê sobre a agenda, conforme o estado da página
# (`Native::Agenda.estado`). Marcando: como oferecer, confirmar (`cliente_confirmou`) e mandar o link de gestão.
# Sem marcar (página apagada, pausada, sem quem atenda, agenda de quem atende pausada): não oferecer nada e passar
# para uma pessoa, com o motivo.
module Autonomia::Agents::Tools::Native::AgendaInstrucao
  ATIVA = <<~TEXT.strip.freeze
    # Agenda
    Você tem a agenda deste atendimento e PODE oferecer horários e marcar reuniões. Isto vale sobre qualquer regra
    anterior que diga para só anotar a preferência ou nunca consultar a agenda.
    - Quando o cliente quiser marcar, chame `horarios_disponiveis` e ofereça 2 ou 3 opções, com dia da semana e hora.
    - Só ofereça horário que a ferramenta devolveu. NUNCA invente horário nem confirme sem a ferramenta.
    - Antes de marcar, repita ao cliente o dia, a hora e o local e pergunte se pode marcar. Só depois que ele disser
      que sim, chame `agendar_reuniao` com o horário exatamente como a ferramenta devolveu e `cliente_confirmou: true`.
    - Só diga que está marcado quando `agendar_reuniao` confirmar. Na confirmação, mande ao cliente o `link_de_gestao`
      (por ele o cliente confirma, muda ou cancela) e, se vier, o `link_da_reuniao` ou o `endereco`.
    - Para remarcar ou cancelar, mande o link de gestão que você enviou ao marcar. Sem esse link na conversa, passe
      para uma pessoa da equipe. Você não remarca nem cancela.
    - Se a ferramenta recusar, siga o que ela disser: pedir um dado, oferecer as novas opções ou passar para uma pessoa.
  TEXT

  INDISPONIVEL = <<~TEXT.strip.freeze
    # Agenda
    A agenda deste atendimento está indisponível agora (motivo: %<motivo>s). NÃO ofereça horário, NÃO diga que vai
    marcar e NÃO prometa encaixe. Se o cliente quiser marcar, remarcar ou cancelar, diga com suas palavras que uma
    pessoa da equipe vai cuidar disso e passe a conversa: should_handoff=true, handoff_reason "agendamento indisponível".
    Isto vale sobre qualquer regra anterior que mande oferecer horários.
  TEXT

  def self.para(estado)
    estado == ::Autonomia::Agents::Tools::Native::Agenda::ATIVA ? ATIVA : format(INDISPONIVEL, motivo: estado)
  end
end
