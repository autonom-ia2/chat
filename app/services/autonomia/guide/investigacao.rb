# Para o time investigar um relato sobre o Guia (#861), pelo caminho de
# produção que já existe (SSM → docker exec → rails runner). Só leitura.
#
#   Autonomia::Guide::Investigacao.new(pedido_id: '...').relatorio
#   Autonomia::Guide::Investigacao.new(account_id: 18, user_id: 7, desde: 2.days.ago).relatorio
#   Autonomia::Guide::Investigacao.new(pedido_id: '...').cenario
#
# `relatorio` é a linha do tempo de cada turno: a pergunta, o que o Guia chamou,
# o que decidiu, quanto custou e o que respondeu. `cenario` transforma o caso
# real num esqueleto de exemplo para a bateria (`bateria_admin_eval_spec.rb`):
# o caso vira teste, nunca um `if` no código.
#
# Como usar, com exemplos: docs/guia-operante/INVESTIGAR.md.
class Autonomia::Guide::Investigacao
  LIMITE = 50
  MAX_RESPOSTA = 600

  def initialize(pedido_id: nil, account_id: nil, user_id: nil, desde: 2.days.ago)
    @pedido_id = pedido_id
    @account_id = account_id
    @user_id = user_id
    @desde = desde
  end

  def turnos
    @turnos ||= begin
      escopo = ::Autonomia::Guide::Turno.includes(:conversa).order(:created_at, :id)
      escopo = filtrar(escopo)
      escopo.last(LIMITE)
    end
  end

  def relatorio
    return 'Nenhum pedido encontrado com esses filtros.' if turnos.empty?

    turnos.map { |turno| bloco(turno) }.join("\n\n")
  end

  # O esqueleto de um exemplo da bateria paga, com as perguntas reais em ordem.
  # Nomes, telefones e números do cliente saem À MÃO antes do commit: trocar
  # dado pessoal por padrão de texto deixaria passar o que o padrão não previu.
  def cenario
    return '# Nenhum pedido encontrado com esses filtros.' if turnos_do_cenario.empty?

    linhas = ['# Gerado por Autonomia::Guide::Investigacao#cenario.',
              '# ANTES DO COMMIT: troque à mão nomes, telefones, e-mails e números do cliente.',
              "it 'CXX — #{turnos_do_cenario.first.pergunta.to_s.squish.truncate(60).tr("'", ' ')}' do",
              '  # Recursos que o Guia leu no caso real (monte o estado com conta_corretora!):',
              *recursos_lidos.map { |recurso| "  #   #{recurso}" }]
    linhas.concat(perguntas)
    linhas.push('  # TODO: o estado final esperado no banco', 'end')
    linhas.join("\n")
  end

  private

  # Com um pedido, o caso é a conversa dele até ali: as perguntas anteriores são
  # o contexto que o Guia tinha. Com filtro de conta e pessoa, os turnos achados.
  def turnos_do_cenario
    @turnos_do_cenario ||= if @pedido_id.present? && turnos.any?
                             alvo = turnos.last
                             alvo.conversa.turnos.where(created_at: ..alvo.created_at).to_a
                           else
                             turnos
                           end
  end

  def filtrar(escopo)
    return escopo.where(pedido_id: @pedido_id) if @pedido_id.present?

    escopo = escopo.where(account_id: @account_id) if @account_id.present?
    escopo = escopo.where(user_id: @user_id) if @user_id.present?
    escopo.where(created_at: @desde..)
  end

  def bloco(turno)
    diagnostico = turno.diagnostico.to_h
    [cabecalho(turno), "  pergunta: #{turno.pergunta}", anexos(turno),
     *diagnostico.fetch('chamadas', []).map { |chamada| "  chamou: #{chamada_em_texto(chamada)}" },
     decisoes(diagnostico), custo(diagnostico), resposta(turno, diagnostico), acao(turno), feito(turno)].compact.join("\n")
  end

  def cabecalho(turno)
    "== pedido #{turno.pedido_id} | #{turno.created_at.iso8601} | conta #{turno.account_id} | usuário #{turno.user_id} | " \
      "conversa #{turno.conversation_id} | tela #{turno.tela || '-'} | #{turno.status}"
  end

  def anexos(turno)
    return nil if turno.anexos.blank?

    "  anexos: #{turno.anexos.map { |anexo| "#{anexo['nome']} (#{anexo['tipo']})" }.join(', ')}"
  end

  def chamada_em_texto(chamada)
    partes = [chamada['ferramenta'], chamada['args'].to_h.to_json, "#{chamada['ms']}ms", "#{chamada['saida_chars']} caracteres"]
    partes << "sem valor: #{chamada['omitidos'].join(', ')}" if chamada['omitidos'].present?
    partes << "recusa: #{chamada['recusa']}" if chamada['recusa'].present?
    partes.join(' | ')
  end

  def decisoes(diagnostico)
    fluxos = Array(diagnostico['fluxos']).map { |fluxo| "##{fluxo['id']} #{fluxo['titulo']}" }.join('; ')
    "  decidiu: fluxos [#{fluxos}] | check #{diagnostico['check'] || '-'} | confiança #{diagnostico['confianca'] || '-'} | " \
      "ancorada #{diagnostico['grounded']} | escalou #{diagnostico['escalate']} | retida #{diagnostico['retido']} | " \
      "telas #{Array(diagnostico['telas']).join(', ')} | artigos #{Array(diagnostico['artigos']).join(', ')}" \
      "#{" | erro #{diagnostico['erro']}" if diagnostico['erro'].present?}"
  end

  def custo(diagnostico)
    tokens = diagnostico['tokens'].to_h
    "  custo: US$ #{diagnostico['custo_usd'] || 0} | #{diagnostico['rodadas'] || 0} idas ao modelo #{diagnostico['modelo']} " \
      "(#{diagnostico['effort'] || '-'}) | tokens in #{tokens['in']} cached #{tokens['cached']} out #{tokens['out']} | " \
      "#{diagnostico['ms'] || '-'}ms"
  end

  def resposta(turno, diagnostico)
    texto = turno.resposta.presence || diagnostico['resposta_retida'].presence
    rotulo = turno.resposta.present? ? 'respondeu' : 'retida'
    texto ? "  #{rotulo}: #{texto.to_s.squish.truncate(MAX_RESPOSTA)}" : nil
  end

  def acao(turno)
    return nil if turno.acao.blank?

    "  propôs: #{turno.acao['nome']} → #{turno.acao_estado || 'aguardando'} #{turno.acao_resultado}".rstrip
  end

  def feito(turno)
    return nil if turno.passos.blank?

    "  fez: #{turno.passos.map { |passo| "#{passo['frase']} (#{passo['ok'] ? 'ok' : 'falhou'})" }.join('; ')}"
  end

  # Os recursos que o Guia leu, para montar o estado da conta no exemplo.
  def recursos_lidos
    turnos_do_cenario.flat_map { |turno| Array(turno.diagnostico.to_h['chamadas']) }
                     .select { |chamada| chamada['ferramenta'] == 'ler_da_conta' }
                     .filter_map { |chamada| chamada.dig('args', 'recurso') }.uniq
  end

  # As perguntas na ordem, cada uma levando o histórico das anteriores — o
  # padrão `perguntar(..., historico: turno(...))` da bateria.
  def perguntas
    lista = turnos_do_cenario
    lista.each_with_index.flat_map do |turno, indice|
      texto = turno.pergunta.to_s.inspect
      if indice.zero?
        ["  r0 = perguntar(#{texto})", '  respondeu!(r0)']
      else
        anteriores = (0...indice).map { |anterior| "turno(#{lista[anterior].pergunta.to_s.inspect}, r#{anterior})" }.join(' + ')
        ["  r#{indice} = perguntar(#{texto}, historico: #{anteriores})", "  respondeu!(r#{indice})"]
      end
    end
  end
end
