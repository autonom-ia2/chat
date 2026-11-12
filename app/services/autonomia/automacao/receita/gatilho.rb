# O gatilho ao salvar (#2608, saiu da Receita), na ordem em que as frases aparecem: o de card e o de tempo, a conversa
# nova, a agenda de reserva e o "Só se".
class Autonomia::Automacao::Receita::Gatilho
  # `travessia`: a Receita, que anda por todos os passos (Receita#passos). `contexto`: Receita::Contexto. `condicoes`:
  # Receita::Condicoes, para o "Só se".
  def initialize(travessia, contexto, condicoes)
    @travessia = travessia
    @receita = contexto.receita
    @conta = contexto.conta
    @account_user = contexto.account_user
    @condicoes = condicoes
  end

  def problemas = [*gatilho_novo, *conversa_nova, *agenda_de_reserva, *filtros_do_gatilho]

  private

  def passos = @travessia.passos

  # O gatilho de card e o de tempo (#2499): a flag, a etapa, o funil e o campo de data são da conta; no da conta (G7),
  # os passos que ele aceita.
  def gatilho_novo
    ::Autonomia::Automacao::ProblemasDoGatilho.new(@receita['gatilho'].to_h, @conta, passos: passos, account_user: @account_user).problemas
  end

  # A caixa por onde abrir a conversa de quem não tem (#2680): da conta, e quem salva pode começar conversa nela. O ramo
  # do "em outro registro" no card ou contato que um passo criou também não tem conversa (G49).
  def conversa_nova
    ramos = ::Autonomia::Automacao::EmOutroRegistro.alvos_dos_criados(passos, @receita)
    ::Autonomia::Automacao::ConversaNova.problemas_ao_salvar(@conta, @receita['gatilho'].to_h, @account_user, ramos: ramos)
  end

  # G60: a página de agenda de reserva é da conta, e quem salva lê as páginas.
  def agenda_de_reserva = ::Autonomia::Automacao::AgendaDeReserva.problemas_ao_salvar(@conta, @receita['gatilho'].to_h, @account_user)

  def filtros_do_gatilho
    Array(@receita.dig('gatilho', 'filtros')).flat_map { |condicao| @condicoes.problemas('gatilho', condicao, no_gatilho: true) }
  end
end
