# O USO DAS FERRAMENTAS PRONTAS DE UMA CONTA (#2858, F0: a API interna que a tela da F2 e a equipe vão ler). Sempre da
# conta pedida: a conta A nunca vê o uso da conta B. Só contagens e motivos; nada do que foi consultado.
module Autonomia::FerramentasProntas::RelatorioDeUso
  CAMPOS = %w[dia fonte consultas do_cache pela_reserva nao_encontradas sem_resposta recusadas motivos].freeze
  DIAS = 7

  module_function

  # -> [{ 'dia' =>, 'fonte' =>, 'consultas' =>, …, 'limite_do_dia' =>, 'cortada' => }], do dia mais novo ao mais antigo.
  def da_conta(account, dias: DIAS)
    acessos = Autonomia::FerramentasProntas::Acesso.da_conta(account).index_by(&:fonte)
    Autonomia::FerramentasProntas::Uso.da_conta(account).where(dia: (dias - 1).days.ago.to_date..)
                                      .order(dia: :desc, fonte: :asc).map do |uso|
      acesso = acessos[uso.fonte]
      uso.attributes.slice(*CAMPOS).merge('limite_do_dia' => acesso&.limite_do_dia, 'cortada' => acesso&.cortada? || false)
    end
  end
end
