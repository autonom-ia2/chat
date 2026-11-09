# A campanha da vez num gatilho recorrente de card ou contato (#2414 G55, exemplo 16, passo 2: "para cada card perdido"
# põe a etiqueta, e a campanha sai uma vez "para todos com essa etiqueta").
#
# O card.recorrente abre uma execução por card, e a campanha não é do card, é da vez (todo dia 1º, toda segunda). Ela
# sai quando a vez fecha: todos os cards que a vez esperava chegaram ao passo campanha ou saíram por outro caminho
# (parar, um "se" que não passa por ele, erro, a automação impedida), ou nem abriram execução (saíram da seleção entre a
# varredura e o lote, já tinham uma execução aberta). A conta mora no Postgres (Autonomia::Automacao::CampanhaDaVez),
# uma linha por automação, vez e passo, e cada mudança passa pela trava de transação da vez:
#
# - a varredura (TempoDaAutomacaoJob) abre a linha antes dos lotes e grava os esperados (os ids enfileirados) depois;
# - o lote (RecorrenteLoteJob) conta os ids que não abriram execução;
# - o passo campanha conta a chegada; o Executor, ao fechar a execução que não chegou, conta a saída.
#
# Quem completa a conta fecha a vez e cria a campanha pelo caminho do gatilho da conta (PassoDeCampanha com a conta como
# alvo: as mesmas conferências, a Campanha da tela, o job do disparo), que lê o público (as etiquetas) na hora.
#
# Rede de segurança: a vez que não fechar em REDE (um lote que não rodou, uma execução fechada por fora do motor, uma
# espera longa antes do passo) fecha pelo FecharVezJob com quem chegou. O registro diz quantos chegaram, saíram, não
# abriram e ficaram de fora sem contar, com o motivo `campanha_da_vez_saiu_pela_rede`.
#
# O card que chega depois de a vez fechar pula com `campanha_da_vez_ja_saiu`: outra campanha iria de novo para todos
# com a etiqueta.
class Autonomia::Automacao::CampanhaDaOcorrencia
  REDE = 2.hours
  Vez = ::Autonomia::Automacao::CampanhaDaVez
  Gatilhos = ::Autonomia::Automacao::Gatilhos

  class << self
    # A varredura, antes dos lotes: uma linha por passo de disparar da receita. Nada fora do recorrente de card ou
    # contato, ou sem campanha na receita.
    def abrir(definicao, ocorrencia)
      tipo = definicao.versao_ativa.receita.dig('gatilho', 'tipo')
      return [] unless por_alvo?(tipo)

      passos_de_disparar(definicao.versao_ativa.receita).map do |passo_id|
        garantir(definicao, Gatilhos.marca_da_vez(tipo, ocorrencia), passo_id)
      end
    end

    # A varredura, depois de enfileirar os lotes: o total esperado da vez.
    def esperar(linhas, total)
      linhas.each { |linha| mudar(linha.id) { |vez| vez.esperados = total } }
    end

    # O lote: os ids que não abriram execução nesta vez.
    def lote_feito(definicao, tipo, ocorrencia, ids)
      return unless por_alvo?(tipo)

      marcas = ids.map { |id| Gatilhos.marca_do_recorrente(tipo, id, ocorrencia) }
      fora = ids.size - ::Autonomia::Automacao::Execucao.where(automacao_id: definicao.id, evento: marcas).count
      return if fora.zero?

      abertas(definicao.id, Gatilhos.marca_da_vez(tipo, ocorrencia)).each { |id| mudar(id) { |vez| vez.sem_execucao += fora } }
    end

    # O Executor fechou a execução: conta a saída nas vezes em que ela não chegou ao passo.
    def saiu(execucao)
      vez = vez_da(execucao)
      return unless vez

      abertas(execucao.automacao_id, vez).each do |id|
        mudar(id) { |linha| linha.saidas += 1 unless chegou?(execucao, linha) }
      end
    end

    # A chegada ao passo campanha. Devolve [linha, fechada agora?] ou [linha, :ja_saiu].
    def chegar(execucao, passo_id)
      linha = garantir(execucao.automacao, vez_da(execucao), passo_id)
      fechou = nil
      ja_saiu = travado(linha.id) do |vez|
        next true if vez.fechada_em

        vez.chegadas += 1
        vez.primeira_execucao_id ||= execucao.id
        fechou = fechar_se_pronta(vez)
        vez.save!
        false
      end
      [linha.reload, ja_saiu ? :ja_saiu : fechou]
    end

    # O FecharVezJob, depois de REDE: fecha a vez que ainda não fechou, com quem chegou.
    def fechar_pela_rede(id)
      fechou = travado(id) do |vez|
        next false if vez.fechada_em

        vez.update!(fechada_em: Time.current)
        true
      end
      registrar_na_primeira(Vez.find(id), pela_rede: true) if fechou
    end

    # A vez da execução de um recorrente de card ou contato, ou nil.
    def vez_da(execucao)
      Gatilhos.ocorrencia_da_marca(execucao.evento, execucao.alvo_id) if por_alvo?(execucao.chave_gatilho)
    end

    # Cria a campanha da vez fechada, pelo caminho do gatilho da conta, e deixa o registro na primeira execução que
    # chegou. Sem chegada nenhuma, não há campanha. Devolve o Resultado do passo (nil sem chegada).
    def disparar(vez, pela_rede: false)
      execucao = vez.primeira_execucao_id && ::Autonomia::Automacao::Execucao.find_by(id: vez.primeira_execucao_id)
      return log_sem_campanha(vez) unless execucao

      passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(vez.passo)
      resultado = ::Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: passo, alvo: execucao.account).executar
      vez.update!(campanha_display_id: resultado.dados['campanha_id'])
      resumo(vez, resultado, pela_rede)
    end

    private

    def por_alvo?(tipo) = Gatilhos.recorrente?(tipo) && !Gatilhos.da_conta?(tipo)

    def passos_de_disparar(receita, lista = receita['passos'])
      Array(lista).flat_map do |passo|
        proprio = passo['tipo'] == 'campanha' && passo['faz'] == 'disparar' ? [passo['id']] : []
        proprio + ::Autonomia::Automacao::Receita.ramos(passo).flat_map { |ramo| passos_de_disparar(receita, ramo) }
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

    # A execução deixou o registro de chegada (o passo campanha grava `campanha_da_vez` com o id da linha).
    def chegou?(execucao, vez)
      ::Autonomia::Automacao::Registro.where(execucao_id: execucao.id, passo: vez.passo)
                                      .exists?(["dados ->> 'campanha_da_vez' = ?", vez.id.to_s])
    end

    # Muda a linha sob a trava e, se a conta completou, fecha e dispara depois do commit.
    def mudar(id)
      fechou = travado(id) do |vez|
        next false if vez.fechada_em

        yield vez
        pronta = fechar_se_pronta(vez)
        vez.save!
        pronta
      end
      registrar_na_primeira(Vez.find(id)) if fechou
    end

    # Fechada fora do passo campanha (a saída, o lote, a rede): o registro vai para a primeira execução que chegou.
    def registrar_na_primeira(vez, pela_rede: false)
      resultado = disparar(vez, pela_rede: pela_rede)
      return unless resultado

      ::Autonomia::Automacao::Registro.create!(account_id: vez.account_id, automacao_id: vez.automacao_id,
                                               execucao_id: vez.primeira_execucao_id, passo: vez.passo,
                                               resultado: resultado.tipo == :ok ? 'ok' : 'pulado', motivo: resultado.motivo,
                                               dados: resultado.dados)
    end

    def fechar_se_pronta(vez)
      return false unless vez.pronta?

      vez.fechada_em = Time.current
      true
    end

    def travado(id)
      Vez.transaction do
        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "automacao:campanha_da_vez:#{id}"])
        ActiveRecord::Base.connection.execute(sql)
        yield Vez.find(id)
      end
    end

    def contagem(vez)
      { 'campanha_da_vez' => vez.id, 'esperados' => vez.esperados.to_i, 'chegaram' => vez.chegadas, 'sairam' => vez.saidas,
        'sem_execucao' => vez.sem_execucao, 'faltaram' => vez.faltaram, 'horas' => REDE.in_hours.to_i }
    end

    def resumo(vez, resultado, pela_rede)
      motivo = if resultado.tipo == :ok
                 pela_rede ? 'campanha_da_vez_saiu_pela_rede' : 'campanha_da_vez_saiu'
               else
                 resultado.motivo
               end
      ::Autonomia::Automacao::PassoDeAcao::Resultado.new(tipo: resultado.tipo, motivo: motivo,
                                                         dados: resultado.dados.merge(contagem(vez)))
    end

    def log_sem_campanha(vez)
      Rails.logger.info("[automacao][campanha_da_vez] fechou sem chegada automacao=#{vez.automacao_id} vez=#{vez.id} " \
                        "esperados=#{vez.esperados} sairam=#{vez.saidas} sem_execucao=#{vez.sem_execucao}")
      nil
    end
  end
end
