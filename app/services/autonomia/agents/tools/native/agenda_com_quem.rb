# COM QUEM MARCAR, no lado das ferramentas da agenda (#1307), incluído pela `Native::Agenda`.
#
# As pessoas que o dono liberou nesta página (`AgendaPessoas`), a conferência do `pessoa_id` que o modelo mandou
# (só entre as liberadas; id forjado, de outra página ou de outra conta não está lá; agenda pausada não recebe) e o
# que o modelo recebe sobre elas: `pessoas_liberadas` nas recusas e `quem_atende_esta_conversa` como DADO, nunca regra.
# Quem decide com quem marcar é o modelo; aqui nada lê texto.
module Autonomia::Agents::Tools::Native::AgendaComQuem
  PESSOA_NAO_LIBERADA = 'Essa pessoa não está liberada para esta agenda e nada foi feito. Use só um pessoa_id de ' \
                        'pessoas_liberadas, ou mande sem pessoa_id para ver os horários de todas.'.freeze
  PESSOA_PAUSADA = 'Essa pessoa pausou a própria agenda e não recebe reunião agora. Ofereça os horários de outra das ' \
                   'pessoas_liberadas, ou mande sem pessoa_id.'.freeze
  PESSOA_OBRIGATORIA = 'Mais de uma pessoa pode receber esta reunião e nada foi marcado. Chame de novo com o ' \
                       'pessoa_id do horário que o cliente escolheu (está em horarios_disponiveis).'.freeze

  private

  def pessoas
    @pessoas ||= ::Autonomia::Agents::Tools::Native::AgendaPessoas.new(agent: agent, pagina: pagina, paginas: paginas)
  end

  # Quem recebe a reunião: a liberada pedida (já conferida) ou a única que pode atender.
  def pessoa
    @pessoa ||= params['pessoa_id'].nil? ? pessoas.atendem.first : pessoas.liberada(params['pessoa_id'])
  end

  # O link dela no modo por pessoa; nil no responsável fixo.
  def link
    pessoa&.link
  end

  # nil quando serve ou quando o modelo não pediu ninguém; senão a recusa, com a lista de quem pode.
  def recusa_da_pessoa
    return if params['pessoa_id'].nil?

    pessoa = pessoas.liberada(params['pessoa_id'])
    return recusar('agenda_pessoa_nao_liberada', recusa_de_pessoa('pessoa_nao_liberada', PESSOA_NAO_LIBERADA)) if pessoa.nil?
    return recusar('agenda_pessoa_pausada', recusa_de_pessoa('pessoa_pausada', PESSOA_PAUSADA)) if pessoa.paused?

    nil
  end

  # Sem `pessoa_id`, só marca quando uma pessoa só pode atender. Com mais de uma, quem escolhe é o modelo.
  def recusa_pessoa_obrigatoria
    return unless params['pessoa_id'].nil? && pessoas.atendem.size > 1

    recusar('agenda_pessoa_obrigatoria', recusa_de_pessoa('pessoa_obrigatoria', PESSOA_OBRIGATORIA))
  end

  def recusa_de_pessoa(motivo, instrucao)
    recusa_em_campos(motivo, instrucao, pessoas_liberadas: liberadas_em_campos)
  end

  # Quem atende esta conversa, se estiver liberado e com a agenda aberta.
  def quem_atende_esta_conversa
    pessoa = pessoas.liberada(conversa&.assignee_id)
    pessoa_em_campos(pessoa) if pessoa && !pessoa.paused?
  end

  def liberadas_em_campos
    pessoas.atendem.map { |pessoa| pessoa_em_campos(pessoa) }
  end

  def pessoa_em_campos(pessoa)
    { pessoa_id: pessoa.user.id, pessoa_nome: pessoa.user.available_name }
  end

  # { inicio: "2026-10-20T10:00:00-03:00", quando: "terça-feira, 20/10, 10:00", pessoa_id:, pessoa_nome: }.
  def opcao_em_campos(opcao)
    hora = Time.iso8601(opcao[:inicio]).in_time_zone(fuso)
    dia = ::Autonomia::Agents::Tools::Native::Agenda::DIAS_DA_SEMANA[hora.wday]
    { inicio: opcao[:inicio], quando: "#{dia}, #{hora.strftime('%d/%m, %H:%M')}" }
      .merge(pessoa_em_campos(opcao[:pessoa]))
  end
end
