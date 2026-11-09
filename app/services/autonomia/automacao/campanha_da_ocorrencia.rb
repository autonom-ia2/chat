# A campanha da vez num gatilho recorrente de card ou contato (#2414 G55, exemplo 16, passo 2: "para cada card perdido"
# põe a etiqueta, e a campanha sai uma vez "para todos com essa etiqueta").
#
# O card.recorrente abre uma execução por card, e a campanha não é do card, é da vez (todo dia 1º, toda segunda). A vez
# fecha pelo ESTADO do banco, nunca por soma: a varredura enfileirou todos os lotes, todos rodaram, e nenhuma execução
# desta vez está aberta antes do passo campanha (aberta e sem o registro dele). Quem passou pelo passo, quem fechou por
# outro caminho (parar, um "se", erro, desligar, a varredura das travadas) e quem nem abriu execução não seguram a vez.
# O cálculo é o mesmo a cada conferência, sob a trava da vez: repetir não muda nada, e uma pane no meio (a execução que
# morreu entre o passo e o registro) só segura a vez, nunca a fecha antes da hora.
#
# Quem confere: o Executor depois de gravar o registro do passo campanha e ao fechar uma execução; o desligar e a
# varredura das travadas, que fecham em lote; a varredura do recorrente e cada lote; e a rede de segurança.
#
# Ao fechar com pelo menos uma chegada, confere de novo se pode mandar (motor e mensagens ligados, automação ligada,
# gatilho disponível, quem ligou pode enviar campanha). Pode: monta a campanha pelo caminho do gatilho da conta
# (PassoDeCampanha#montar, as mesmas conferências e a Campanha da tela) e fecha a vez na mesma transação; o disparo vai
# para a fila depois do commit (e o agendador das campanhas pega a campanha ativa e vencida mesmo sem ele). Não pode:
# nada sai, e o registro diz por quê. Erro no meio: a transação volta, a vez continua aberta, o erro fica no registro, e
# a conferência roda de novo em TENTAR_DE_NOVO. O registro da vez vai para a primeira execução que chegou.
#
# Vez sem chegada nenhuma não fecha e não manda: não houve quem chegasse ao passo.
#
# Rede de segurança (FecharVezJob, a cada REDE enquanto a vez está aberta): a execução TRAVADA (aberta, sem espera e
# sem andar há mais de REDE) e o lote que não rodou em REDE contam como fora, e o registro diz quantos. A execução que
# espera ("esperar" antes da campanha) segura a vez pelo tempo que for.
class Autonomia::Automacao::CampanhaDaOcorrencia
  REDE = 2.hours
  TENTAR_DE_NOVO = 5.minutes
  Vez = ::Autonomia::Automacao::CampanhaDaVez
  Gatilhos = ::Autonomia::Automacao::Gatilhos
  Execucao = ::Autonomia::Automacao::Execucao
  Registro = ::Autonomia::Automacao::Registro
  AGUARDANDO = 'campanha_da_vez_aguardando'.freeze

  class << self
    # A varredura, antes dos lotes: uma linha por passo de disparar da receita. Nada fora do recorrente de card ou
    # contato, ou sem campanha na receita.
    def abrir(definicao, ocorrencia)
      tipo = definicao.versao_ativa.receita.dig('gatilho', 'tipo')
      return [] unless por_alvo?(tipo)

      passos_de_disparar(definicao.versao_ativa.receita['passos']).map do |passo_id|
        garantir(definicao, Gatilhos.marca_da_vez(tipo, ocorrencia), passo_id)
      end
    end

    # A varredura, depois de enfileirar: quantos lotes a vez espera.
    def lotes(linhas, total)
      linhas.each do |linha|
        travado(linha.id) { |vez| vez.update!(lotes: total) }
        conferir(linha.id)
      end
    end

    # O lote `indice` rodou (o repetido marca o mesmo índice).
    def lote_feito(definicao, tipo, ocorrencia, indice)
      return if indice.nil? || !por_alvo?(tipo)

      abertas(definicao.id, Gatilhos.marca_da_vez(tipo, ocorrencia)).each do |id|
        travado(id) { |vez| vez.update!(lotes_feitos: (vez.lotes_feitos | [indice])) }
        conferir(id)
      end
    end

    # A linha da vez em que a execução chega ao passo campanha.
    def chegada(execucao, passo_id) = garantir(execucao.automacao, vez_da(execucao), passo_id)

    # Confere as vezes abertas da execução (depois do registro do passo campanha, ou ao fechá-la).
    def conferir_execucao(execucao)
      vez = vez_da(execucao)
      abertas(execucao.automacao_id, vez).each { |id| conferir(id) } if vez
    end

    # Confere as vezes abertas da automação (o desligar fecha as execuções em lote).
    def conferir_automacao(definicao)
      Vez.where(automacao_id: definicao.id, fechada_em: nil).ids.each { |id| conferir(id) }
    end

    # Fecha a vez quando o estado deixa. Devolve :fechada, :aberta (ainda há quem segure) ou :sem_chegada.
    def conferir(id, rede: false)
      situacao, posterior = travado(id) { |vez| fechar_se_puder(vez, rede) }
      posterior&.call
      situacao
    rescue StandardError => e
      falhou(id, e)
      :aberta
    end

    # A vez da execução de um recorrente de card ou contato, ou nil.
    def vez_da(execucao)
      Gatilhos.ocorrencia_da_marca(execucao.evento, execucao.alvo_id) if por_alvo?(execucao.chave_gatilho)
    end

    private

    def por_alvo?(tipo) = Gatilhos.recorrente?(tipo) && !Gatilhos.da_conta?(tipo)

    def passos_de_disparar(lista)
      Array(lista).flat_map do |passo|
        proprio = passo['tipo'] == 'campanha' && passo['faz'] == 'disparar' ? [passo['id']] : []
        proprio + ::Autonomia::Automacao::Receita.ramos(passo).flat_map { |ramo| passos_de_disparar(ramo) }
      end
    end

    # A linha da vez; a que nasce agora ganha a rede de segurança.
    def garantir(definicao, ocorrencia, passo_id)
      linha = Vez.create_or_find_by!(automacao_id: definicao.id, ocorrencia: ocorrencia, passo: passo_id) do |nova|
        nova.account_id = definicao.account_id
      end
      ::Autonomia::Automacao::FecharVezJob.set(wait: REDE).perform_later(linha.id) if linha.previously_new_record?
      linha
    end

    def abertas(automacao_id, ocorrencia) = Vez.where(automacao_id: automacao_id, ocorrencia: ocorrencia, fechada_em: nil).ids

    def travado(id)
      Vez.transaction do
        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "automacao:campanha_da_vez:#{id}"])
        ActiveRecord::Base.connection.execute(sql)
        yield Vez.find(id)
      end
    end

    # [situação, o que fazer depois do commit]
    def fechar_se_puder(vez, rede)
      return [:fechada, nil] if vez.fechada_em

      estado = ::Autonomia::Automacao::EstadoDaVez.new(vez, rede: rede)
      return [:aberta, nil] unless estado.pronta?
      return [:sem_chegada, nil] unless estado.primeira

      fechar(vez, estado)
    end

    def fechar(vez, estado)
      execucao = estado.primeira
      impedimento = impedimento(execucao)
      return nao_saiu(vez, estado, impedimento) if impedimento

      passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(vez.passo)
      resultado, campanha = ::Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: passo, alvo: execucao.account).montar
      return nao_saiu(vez, estado, resultado.motivo) unless campanha

      # O display_id vem do banco (o callback da Campanha só relê depois do commit): relido aqui, dentro da transação.
      display_id = campanha.reload.display_id
      vez.update!(fechada_em: Time.current, campanha_display_id: display_id)
      registrar(vez, estado, 'ok', estado.motivo_da_saida, resultado.dados.merge('campanha_id' => display_id))
      [:fechada, -> { ::Campaigns::TriggerOneoffCampaignJob.perform_later(campanha) }]
    end

    # Não pode mandar agora: a vez fecha sem campanha, com o motivo no registro e no log.
    def nao_saiu(vez, estado, motivo)
      vez.update!(fechada_em: Time.current)
      registrar(vez, estado, 'pulado', 'campanha_da_vez_nao_saiu', 'por' => motivo)
      Rails.logger.info("[automacao][campanha_da_vez] não saiu automacao=#{vez.automacao_id} vez=#{vez.id} motivo=#{motivo}")
      [:fechada, nil]
    end

    # O que impede de mandar agora, como no Executor e na Partida (a chave do motivo), ou nil.
    def impedimento(execucao)
      definicao = execucao.automacao
      conta = execucao.account
      return 'motor_desligado' unless ::Autonomia::Automacao::Motor.ligado?(conta)
      return 'mensagens_desligadas' unless ::Autonomia::Automacao::Motor.mensagens?(conta)
      return 'desligada' unless definicao.ativa
      return 'gatilho_desligado' unless Gatilhos.disponivel?(execucao.chave_gatilho, conta)

      'quem_ligou_sem_permissao_campanha' unless ::Autonomia::Automacao::PassoDeCampanha.pode_disparar?(definicao.ligada_por, conta)
    end

    def registrar(vez, estado, resultado, motivo, dados)
      Registro.create!(account_id: vez.account_id, automacao_id: vez.automacao_id, execucao: estado.primeira, passo: vez.passo,
                       resultado: resultado, motivo: motivo, dados: dados.merge(estado.contagem, 'campanha_da_vez' => vez.id))
    end

    # O erro fica no log e no registro da primeira execução que chegou; a conferência roda de novo em TENTAR_DE_NOVO.
    def falhou(id, erro)
      Rails.logger.error("[automacao][campanha_da_vez] falhou vez=#{id} #{erro.class} em #{erro.backtrace&.first}")
      vez = Vez.find_by(id: id)
      primeira = vez && ::Autonomia::Automacao::EstadoDaVez.new(vez).primeira
      if primeira
        Registro.create!(account_id: vez.account_id, automacao_id: vez.automacao_id, execucao: primeira, passo: vez.passo,
                         resultado: 'falhou', motivo: 'campanha_da_vez_falhou', dados: { 'campanha_da_vez' => vez.id, 'erro' => erro.class.name })
      end
      ::Autonomia::Automacao::FecharVezJob.set(wait: TENTAR_DE_NOVO).perform_later(id) if vez
    end
  end
end
