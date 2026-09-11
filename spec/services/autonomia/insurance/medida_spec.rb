require 'rails_helper'

# A MEDIDA DA COTAÇÃO (entrega 7): quantas cotações e quantas SEGURADORAS foram acionadas, por
# corretora e por período.
#
# O que estes exemplos travam é o que a medida NÃO pode fazer: contar execução sem contar seguradora
# (uma cotação aciona dezessete — o teto de "8 por hora" eram até 136 consultas, e o número 8 não
# dizia nada sobre dinheiro), e mostrar um total que parece completo quando não é.
RSpec.describe Autonomia::Insurance::Medida do
  let(:account) { create(:account) }
  let(:outra_conta) { create(:account) }
  let(:agent) { agente_de(account) }
  let(:slug) { Autonomia::Agents::Tools::Native::InsuranceQuote.slug }
  # As dezessete seguradoras que o portal acionou nas TRÊS cotações reais da conta de teste, lidas
  # em 11/09/2026 por `agger quote result`: os mesmos códigos na renovação, na moto e no caminhão.
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  def agente_de(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: "Mia #{conta.id}", agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Cote.')
  end

  def conversa_de(conta)
    create(:conversation, account: conta, inbox: create(:inbox, account: conta))
  end

  def run!(handle:, conta: account, criada_em: Time.current, agente: nil)
    agente ||= conta == account ? agent : agente_de(conta)
    Autonomia::Agents::ToolRun.create!(
      account: conta, agent: agente, conversation_id: conversa_de(conta).id, slug: slug,
      status: 'done', execution_key: SecureRandom.uuid, handle: handle, created_at: criada_em
    )
  end

  def medida(conta: account, inicio: nil, fim: nil)
    described_class.new(conta: conta, inicio: inicio, fim: fim).call
  end

  describe 'os dois números' do
    # TERMO 2 — o número bate com um caso conhecido: se uma cotação acionou dezessete seguradoras, a
    # consulta diz dezessete. Não é número escolhido; é o que as três cotações reais devolveram.
    it 'conta dezessete seguradoras quando a execução acionou dezessete' do
      # Arrange
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     'entregues' => %w[1 3 4 5 7 8 11 12 19 20 26] })

      # Act
      resultado = medida

      # Assert — uma cotação, dezessete seguradoras. Os dois números, nunca um só.
      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
      expect(resultado[:seguradoras_com_preco]).to eq(11)
    end

    it 'soma as seguradoras de todas as cotações do período' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(2)
      expect(resultado[:seguradoras_acionadas]).to eq(34)
    end

    # A execução que o modelo abriu e o `start` recusou NÃO é cotação: não existe no portal e ninguém
    # paga por ela. Contá-la seria cobrar por trabalho que não houve.
    #
    # A LINHA É A REAL, a que o job grava depois da recusa: intenção anotada E `autonomia_submitted`
    # (o retorno do `start` foi registrado), sem `quote_id`. Um fixture sem a marca passava com
    # "cotação = quote_id OU submitted" — e essa versão cobra a recusa (rodada 3, MV1b).
    it 'nao conta execução que nunca virou cotação no portal' do
      run!(handle: { 'pedido' => 'faltam dados', 'motivo' => 'faltam_dados', 'faltando' => ['vehicle.plate'],
                     Autonomia::Agents::ToolRun::SUBMITTED_KEY => true, Autonomia::Agents::ToolRun::INTENCOES => 1 })

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:seguradoras_acionadas]).to be_zero
      expect(resultado[:cotacoes_sem_confirmacao]).to be_zero
    end

    # POR FERRAMENTA. Outra ferramenta assíncrona da mesma conta pode gravar `quote_id` e até uma lista
    # com o mesmo nome no handle dela: não é cotação de seguro, e somá-la cobraria a corretora por
    # outra coisa. O escopo lê o slug da ferramenta, e sem ele esta linha entraria na fatura.
    it 'nao conta execução de outra ferramenta, mesmo com quote_id e seguradoras no handle' do
      Autonomia::Agents::ToolRun.create!(
        account: account, agent: agent, conversation_id: conversa_de(account).id, slug: 'outra_ferramenta',
        status: 'done', execution_key: SecureRandom.uuid,
        handle: { 'quote_id' => 'x', 'seguradoras_acionadas' => dezessete }
      )

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:seguradoras_acionadas]).to be_zero
    end
  end

  describe 'isolamento e janela' do
    it 'nao mistura corretoras' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

      expect(medida[:cotacoes]).to eq(1)
      expect(medida[:seguradoras_acionadas]).to eq(17)
    end

    it 'respeita o periodo pedido' do
      run!(handle: { 'quote_id' => 'velha', 'seguradoras_acionadas' => dezessete }, criada_em: 40.days.ago)
      run!(handle: { 'quote_id' => 'nova', 'seguradoras_acionadas' => dezessete })

      expect(medida[:cotacoes]).to eq(1)
      expect(medida(inicio: 60.days.ago.to_date.to_s, fim: Time.zone.today.to_s)[:cotacoes]).to eq(2)
    end

    # A JANELA TEM DUAS BORDAS, e a de cima é a que vira dinheiro cobrado a mais. Setembro que a
    # operação pede termina em 30/09: a cotação de 01/10 é da fatura de outubro. Um `fim` ignorado
    # não deixa a conta vazia — ela fica MAIOR, e um número inflado numa fatura ninguém questiona.
    it 'nao conta cotação feita depois do fim da janela' do
      # Arrange — uma dentro de setembro, uma no primeiro dia de outubro.
      run!(handle: { 'quote_id' => 'setembro', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-09-15 10:00'))
      run!(handle: { 'quote_id' => 'outubro', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-10-01 09:00'))

      # Act
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      # Assert — a de outubro ficou de fora: uma cotação, dezessete seguradoras.
      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
    end

    # O PERÍODO QUE A CONSULTA USOU VOLTA NA RESPOSTA. Sem isso, quem cobra não sabe de que janela é
    # o número que está lendo — e "os últimos 30 dias" muda de significado a cada dia.
    it 'devolve os instantes exatos da janela' do
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      expect(resultado[:inicio]).to eq(Time.zone.parse('2026-09-01').beginning_of_day)
      expect(resultado[:fim]).to eq(Time.zone.parse('2026-09-30').end_of_day)
      expect(resultado[:fuso]).to eq(Time.zone.name)
    end

    # O FUSO É O DA CORRETORA. "Setembro" dela termina às 23h59 dela: sem isto, toda cotação feita
    # depois das 21h de 30/09 em São Paulo cairia na fatura de outubro — o nosso valor no lugar do
    # dela, numa conta de dinheiro. O resultado diz qual fuso usou, para ninguém adivinhar.
    it 'le as datas no fuso de relatorio da corretora' do
      # Arrange
      account.update!(reporting_timezone: 'America/Sao_Paulo')

      # Act
      resultado = medida(inicio: '2026-09-01', fim: '2026-09-30')

      # Assert
      expect(resultado[:fuso]).to eq('America/Sao_Paulo')
      expect(resultado[:fim]).to eq(ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-30').end_of_day)
    end

    it 'cai no fuso da instalação quando a corretora nao configurou' do
      expect(medida[:fuso]).to eq(Time.zone.name)
    end

    # NENHUM VALOR NOSSO NO LUGAR DO VALOR DE QUEM PERGUNTA. Data que não se lê vira recusa dita, e
    # nunca "então são os últimos 30 dias" em silêncio — um número de cobrança de uma janela que o
    # operador não pediu é pior do que erro nenhum.
    it 'recusa data ilegivel em vez de escolher uma janela por conta propria' do
      expect { medida(inicio: 'ontem', fim: nil) }.to raise_error(described_class::PeriodoInvalido)
    end

    it 'recusa janela invertida' do
      expect { medida(inicio: '2026-09-30', fim: '2026-09-01') }.to raise_error(described_class::PeriodoInvalido)
    end

    # SÓ O INÍCIO, E NO FUTURO: a recusa culpa a data que foi escrita. "A data inicial é posterior à
    # final" (rodada 4) acusava uma final que ninguém mandou — o fim em aberto é "agora".
    it 'recusa data inicial no futuro dizendo que ela esta no futuro' do
      expect { medida(inicio: (Time.zone.today + 1).to_s, fim: nil) }
        .to raise_error(described_class::PeriodoInvalido, /futuro/)
    end

    # "OS ÚLTIMOS TRINTA DIAS" SÃO TRINTA DATAS, contando hoje: de 13/08 a 11/09. `agora - 30 dias`
    # (rodadas 4 e 5) começava em 12/08 — trinta e uma datas com o nome de trinta, numa janela que
    # vira fatura (rodada 6). A cotação das 23h de 12/08 fica de fora; a das 00h30 de 13/08 entra.
    it 'usa os ultimos trinta dias quando ninguem pede janela' do
      # Arrange
      travel_to Time.zone.parse('2026-09-11 12:00') do
        run!(handle: { 'quote_id' => 'vespera', 'seguradoras_acionadas' => dezessete },
             criada_em: Time.zone.parse('2026-08-12 23:00'))
        run!(handle: { 'quote_id' => 'primeiro-dia', 'seguradoras_acionadas' => dezessete },
             criada_em: Time.zone.parse('2026-08-13 00:30'))

        # Act
        resultado = medida

        # Assert — a janela começa à meia-noite de 13/08 e termina agora; só a de 13/08 entra.
        expect(resultado[:fim]).to eq(Time.current)
        expect(resultado[:inicio]).to eq(Time.zone.parse('2026-08-13').beginning_of_day)
        expect(resultado[:cotacoes]).to eq(1)
      end
    end

    # SÓ O FIM: a janela padrão TERMINA nele. Ancorar o início em hoje quando só o fim foi pedido
    # (rodada 4) recusava `fim=2026-06-30` como "data inicial posterior à final" — culpando um dado
    # que o operador não escreveu, com o nosso valor no lugar do dele.
    #
    # E SÃO TRINTA DATAS CONTANDO O FIM: `fim=30/06` começa em 01/06. `fim - 30 dias` (rodadas 4 e 5)
    # começava em 31/05 — e a cotação das 23h de 31/05, que é de maio, entrava na fatura de junho.
    it 'so fim: a janela padrao termina nele' do
      # Arrange — uma às 23h de 31/05 (fora), uma às 00h30 de 01/06 (dentro).
      run!(handle: { 'quote_id' => 'maio', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-05-31 23:00'))
      run!(handle: { 'quote_id' => 'junho', 'seguradoras_acionadas' => dezessete },
           criada_em: Time.zone.parse('2026-06-01 00:30'))

      # Act
      resultado = medida(fim: '2026-06-30')

      # Assert
      expect(resultado[:fim]).to eq(Time.zone.parse('2026-06-30').end_of_day)
      expect(resultado[:inicio]).to eq(Time.zone.parse('2026-06-01').beginning_of_day)
      expect(resultado[:cotacoes]).to eq(1)
    end

    # SÓ DATA. `Date.iso8601` aceitava data-hora e descartava a hora: quem pedia "a partir das 10h"
    # recebia a partir da meia-noite sem aviso (rodada 4). Precisão a mais é recusada como a data
    # ilegível — dita, nunca truncada em silêncio.
    it 'recusa data com hora em vez de descartar a hora em silencio' do
      expect { medida(inicio: '2026-09-01T10:00:00', fim: '2026-09-30') }.to raise_error(described_class::PeriodoInvalido)
    end
  end

  describe 'o que a medida NAO sabe, ela diz' do
    # A cotação existe no portal e o número de seguradoras nunca foi lido (a execução morreu antes da
    # primeira consulta, ou é anterior a esta entrega). Somar zero aqui faria o total parecer
    # completo — e o total serve para cobrar.
    it 'separa a cotação aberta cujo numero de seguradoras nao foi lido' do
      run!(handle: { 'quote_id' => 'q1' })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(2)
      expect(resultado[:seguradoras_acionadas]).to eq(17)
      expect(resultado[:cotacoes_sem_medida]).to eq(1)
    end

    # Intenção anotada e número ausente: a cotação PODE existir no portal e não temos o id. Não entra
    # em `cotacoes` (afirmaria o que não se sabe) nem some (sumir é a mesma mentira ao contrário).
    it 'separa o envio sem confirmação' do
      run!(handle: { Autonomia::Agents::ToolRun::INTENCOES => 1 })

      resultado = medida

      expect(resultado[:cotacoes]).to be_zero
      expect(resultado[:cotacoes_sem_confirmacao]).to eq(1)
    end

    it 'separa a que pode ter cotado duas vezes no portal' do
      run!(handle: { 'quote_id' => 'q1', Autonomia::Agents::ToolRun::INTENCOES => 2,
                     Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA => true,
                     'seguradoras_acionadas' => dezessete })

      resultado = medida

      expect(resultado[:cotacoes]).to eq(1)
      expect(resultado[:cotacoes_possivelmente_duplicadas]).to eq(1)
    end

    # `handle` é jsonb livre. Uma linha com forma inesperada não pode derrubar a consulta nem ser
    # contada como medida: ela é exatamente uma cotação SEM medida.
    it 'nao quebra com handle de forma inesperada' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => 'dezessete', 'entregues' => 3 })

      resultado = medida

      expect(resultado[:seguradoras_acionadas]).to be_zero
      expect(resultado[:cotacoes_sem_medida]).to eq(1)
    end
  end

  # TERMO 3 — quantas COTAÇÕES viraram proposta individual. A ferramenta é a entrega 8; os contadores
  # já existem, leem o handle e contam de verdade. Hoje são zero porque ninguém escreve a chave.
  describe 'propostas individuais (entrega 8)' do
    it 'conta zero enquanto nenhuma execução registra proposta' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })

      expect(medida[:cotacoes_com_proposta]).to be_zero
      expect(medida[:propostas_emitidas]).to be_zero
    end

    # OS CONTADORES ESTÃO LIGADOS, e não são zero escrito à mão: quando a entrega 8 gravar a chave no
    # handle (`InsuranceQuote::PROPOSTAS_KEY`, os códigos das seguradoras cuja proposta saiu), a
    # medida já conta sem mudar uma linha.
    #
    # A LINHA DA FATURA É `cotacoes_com_proposta` (o termo diz COTAÇÕES): uma cotação com duas
    # propostas é UMA cotação que virou proposta. A soma dos códigos vem em separado — somá-los na
    # coluna do termo diria "duas cotações viraram proposta" onde houve uma (rodada 3).
    it 'conta uma cotação com proposta, e duas propostas emitidas, quando saíram duas' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => %w[8 3] })

      expect(medida[:cotacoes_com_proposta]).to eq(1)
      expect(medida[:propostas_emitidas]).to eq(2)
    end

    # Lista vazia é "ainda nenhuma proposta", não "virou proposta".
    it 'nao conta cotação com lista de propostas vazia' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                     Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => [] })

      expect(medida[:cotacoes_com_proposta]).to be_zero
    end
  end

  describe '#por_conta' do
    # CADA CORRETORA NO FUSO DELA. A cotação das 23h de 30/09 em São Paulo é 02h de 01/10 em UTC (o
    # fuso da instalação): a lista cross-conta lida no nosso fuso a jogava para outubro, enquanto
    # `call` da mesma conta a mantinha em setembro (rodada 4, P2). As duas superfícies leem a mesma
    # linha, ou a fatura e a tela da corretora divergem no último dia de todo mês.
    it 'le cada corretora no fuso dela, igual a medida da conta' do
      # Arrange — São Paulo com a cotação das 23h; a outra conta, sem fuso, com uma às 02h UTC de 01/10.
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      run!(handle: { 'quote_id' => 'sp', 'seguradoras_acionadas' => dezessete },
           criada_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-09-30 23:00'))
      run!(handle: { 'quote_id' => 'utc', 'seguradoras_acionadas' => dezessete }, conta: outra_conta,
           criada_em: Time.zone.parse('2026-10-01 02:00'))

      # Act
      linhas = described_class.new(inicio: '2026-09-01', fim: '2026-09-30').por_conta

      # Assert — só São Paulo aparece em setembro, com o fuso dela e o mesmo número de `call`.
      expect(linhas.map { |linha| linha.values_at(:conta_id, :fuso, :cotacoes, :seguradoras_acionadas) })
        .to eq([[account.id, 'America/Sao_Paulo', 1, 17]])
      expect(linhas.first.slice(:cotacoes, :seguradoras_acionadas, :inicio, :fim))
        .to eq(medida(inicio: '2026-09-01', fim: '2026-09-30').slice(:cotacoes, :seguradoras_acionadas, :inicio, :fim))
    end

    # A FOLGA DA ENUMERAÇÃO TEM MAGNITUDE, não só existência. `FOLGA_DE_FUSO = 0` já reprovava (MX2);
    # `3.hours` passava por 53 exemplos, porque todos usavam São Paulo (3 h de UTC). Com folga menor
    # do que a distância entre os fusos extremos, a corretora em UTC+14 com cotação na primeira hora
    # do mês (ainda 31/08 em UTC) e a em UTC-12 com cotação na última (já 01/10 em UTC) somem da
    # FATURA em silêncio, enquanto a API de cada uma responde 1/17 — a divergência que o P2 da rodada 4
    # fechou, reaberta por um "ajuste" da constante (rodada 5).
    it 'enumera a corretora em qualquer fuso, e a linha e a mesma da medida da conta' do
      # Arrange — Kiritimati (UTC+14) às 00:30 de 01/09; Etc/GMT+12 (UTC-12) às 23:30 de 30/09.
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      outra_conta.update!(reporting_timezone: 'Etc/GMT+12')
      run!(handle: { 'quote_id' => 'leste', 'seguradoras_acionadas' => dezessete },
           criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-01 00:30'))
      run!(handle: { 'quote_id' => 'oeste', 'seguradoras_acionadas' => dezessete }, conta: outra_conta,
           criada_em: ActiveSupport::TimeZone['Etc/GMT+12'].parse('2026-09-30 23:30'))
      janela = { inicio: '2026-09-01', fim: '2026-09-30' }

      # Act
      linhas = described_class.new(**janela).por_conta

      # Assert — as duas na lista, cada uma igual à medida da própria conta: uma cotação, dezessete.
      expect(linhas.map { |linha| linha.values_at(:conta_id, :fuso, :cotacoes, :seguradoras_acionadas) })
        .to eq([[account.id, 'Pacific/Kiritimati', 1, 17], [outra_conta.id, 'Etc/GMT+12', 1, 17]])
      expect(linhas).to eq([medida(conta: account, **janela), medida(conta: outra_conta, **janela)])
    end

    # A CORRETORA CUJO DIA AINDA NÃO COMEÇOU É PULADA, não derruba a lista. `from=hoje` sem `to` à
    # 01h UTC: para a instalação (UTC) o dia começou; para São Paulo (UTC-3) ainda são 22h de ontem e
    # a janela dela começa depois de terminar. Isso não é pedido inválido — é "nenhuma execução" para
    # ela. Até a rodada 4, a `Medida.new(conta:)` dela levantava `PeriodoInvalido` e a página inteira
    # respondia "a data inicial é posterior à final", sem linha para NENHUMA corretora (rodada 5).
    it 'pula a corretora cujo dia ainda nao comecou, em vez de derrubar a lista inteira' do
      # Arrange — São Paulo com cotação às 23h UTC de ontem; a outra conta (UTC) com uma às 00h30 de hoje.
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      travel_to Time.utc(2026, 9, 11, 1, 0) do
        run!(handle: { 'quote_id' => 'sp', 'seguradoras_acionadas' => dezessete }, criada_em: Time.utc(2026, 9, 10, 23, 0))
        run!(handle: { 'quote_id' => 'utc', 'seguradoras_acionadas' => dezessete }, conta: outra_conta,
             criada_em: Time.utc(2026, 9, 11, 0, 30))

        # Act
        linhas = described_class.new(inicio: '2026-09-11', fim: nil).por_conta

        # Assert — só a corretora cujo dia começou; e a medida da conta de São Paulo, pedida
        # diretamente, recusa dizendo o que é: a data inicial ainda não chegou no fuso dela.
        expect(linhas.map { |linha| linha.values_at(:conta_id, :cotacoes, :seguradoras_acionadas) })
          .to eq([[outra_conta.id, 1, 17]])
        expect { medida(conta: account, inicio: '2026-09-11', fim: nil) }
          .to raise_error(described_class::PeriodoInvalido, /futuro/)
      end
    end

    # O RELÓGIO DA INSTALAÇÃO NÃO DECIDE O DIA DE NINGUÉM. Meio-dia UTC de 11/09; em Kiritimati
    # (UTC+14) já são 02h de 12/09, e a corretora de lá cotou à 01h. `from=2026-09-12` sem `to`: a
    # API da conta dela responde 1/17. Até a rodada 5 a lista recusava ANTES de olhar qualquer
    # corretora, porque para o nosso relógio 12/09 "ainda não chegou" — e a fatura escondia a linha
    # dela atrás de "a data inicial está no futuro" (rodada 6, P2 do Codex).
    it 'le a corretora cujo dia ja comecou no fuso dela, mesmo que ainda nao tenha comecado no da instalacao' do
      # Arrange
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      travel_to Time.utc(2026, 9, 11, 12, 0) do
        run!(handle: { 'quote_id' => 'kiritimati', 'seguradoras_acionadas' => dezessete },
             criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-12 01:00'))
        janela = { inicio: '2026-09-12', fim: nil }

        # Act
        linhas = described_class.new(**janela).por_conta

        # Assert — a linha dela está na lista, e é a medida da própria conta.
        expect(linhas.map { |linha| linha.values_at(:conta_id, :fuso, :cotacoes, :seguradoras_acionadas) })
          .to eq([[account.id, 'Pacific/Kiritimati', 1, 17]])
        expect(linhas).to eq([medida(conta: account, **janela)])
      end
    end

    # Quando o dia não começou para NENHUMA corretora, a lista é vazia — não é recusa. "Nenhuma
    # cotação no período" é a verdade; "a data inicial está no futuro" seria o nosso relógio falando
    # por todas.
    it 'devolve lista vazia, sem recusar, quando o dia nao comecou para nenhuma corretora' do
      account.update!(reporting_timezone: 'Pacific/Kiritimati')
      travel_to Time.utc(2026, 9, 11, 12, 0) do
        run!(handle: { 'quote_id' => 'kiritimati', 'seguradoras_acionadas' => dezessete },
             criada_em: ActiveSupport::TimeZone['Pacific/Kiritimati'].parse('2026-09-12 01:00'))

        expect(described_class.new(inicio: '2026-09-13', fim: nil).por_conta).to be_empty
      end
    end

    it 'devolve uma linha por corretora, da que mais acionou para a que menos' do
      # Arrange
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete.first(3) })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

      # Act
      linhas = described_class.new(inicio: nil, fim: nil).por_conta

      # Assert
      expect(linhas.map { |linha| linha[:conta_id] }).to eq([outra_conta.id, account.id])
      expect(linhas.map { |linha| linha[:seguradoras_acionadas] }).to eq([17, 3])
    end

    it 'nao inventa linha para corretora sem execução' do
      expect(described_class.new(inicio: nil, fim: nil).por_conta).to be_empty
    end

    # Com a conta, a lista é só a linha DELA: a enumeração de corretoras não vaza para fora do escopo
    # que a instância recebeu.
    it 'com a conta, so tem a linha dela' do
      run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })
      run!(handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

      expect(described_class.new(conta: account, inicio: nil, fim: nil).por_conta.map { |l| l[:conta_id] }).to eq([account.id])
    end
  end

  # A conta que nunca cotou lê zero, e zero aqui é verdade — não é "não sei".
  it 'devolve zeros para a conta sem nenhuma execução' do
    expect(medida[:cotacoes]).to be_zero
    expect(medida[:conta_id]).to eq(account.id)
  end

  # A MEDIDA DE UMA CORRETORA EXIGE A CORRETORA. Sem a guarda, `call` sem conta devolve a PRIMEIRA
  # linha de `por_conta` — o número de outra corretora com o nome desta, numa conta de dinheiro.
  # Recusa dita, nunca a linha de quem passou na frente.
  it 'recusa medir uma conta sem saber qual é' do
    run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

    expect { described_class.new(inicio: nil, fim: nil).call }.to raise_error(ArgumentError)
  end

  # A LINHA DE UMA CONTA NÃO SE PEDE POR FORA DE `call`. `linha_da_conta` ficou pública na rodada 4
  # para `por_conta` chamá-la em outra instância; sem conta, o escopo é a instalação inteira e `take`
  # devolvia a linha de uma corretora qualquer — a mesma classe do achado acima, por outra porta
  # (rodada 5). Protegida, `por_conta` continua a chamá-la (instância da MESMA classe) e de fora não
  # existe.
  it 'nao entrega a linha de uma conta por fora de call' do
    run!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete }, conta: outra_conta)

    expect { described_class.new(inicio: nil, fim: nil).linha_da_conta }.to raise_error(NoMethodError, /protected/)
  end

  # A medida lê a ferramenta pelo SLUG DELA. Digitá-lo aqui faria a consulta devolver zero em
  # silêncio no dia em que a ferramenta fosse renomeada — e zero é o número que ninguém questiona.
  it 'le o slug da propria ferramenta' do
    expect(described_class.slug).to eq(Autonomia::Agents::Tools::Native::InsuranceQuote.slug)
  end
end
