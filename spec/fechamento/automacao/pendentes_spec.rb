require 'rails_helper'

# Fechamento do épico #2414 (F9.6): os exemplos dos termos de aceite que ainda não rodam na main. Cada um fica pendente
# com as lacunas que o seguram (códigos G* de docs/automacao/F9-fechamento-20-exemplos.md, seção 5). Quando as lacunas
# de um exemplo fecham, ele ganha o arquivo próprio, como o exemplo 10, e sai daqui. O épico só fecha com os 20
# passando (F9.8).
RSpec.describe 'Fechamento #2414 · exemplos que ainda não rodam', type: :model do
  pendentes = {
    # O 2 saiu com o #2762 (G29), depois do #2773 (G30) e do #2800 (G32); o spec de ponta a ponta dele (#2856) é
    # exemplo_02_lead_do_anuncio_spec.rb, passos 1 a 10, no lote 3 do #2414.
    # O 4 saiu com a G50 (#2682, a segunda falta com a primeira ainda esperando): exemplo_04_aluno_que_falta_spec.rb roda
    # à risca, passos 1 a 10, com as páginas escolhidas dos passos 6 e 8 (G44) e o card de retenção criado no passo 2
    # fechado no 10 (G49).
    # O 5 saiu com a G47 (#2766): o spec próprio (exemplo_05_revisao_do_carro_spec.rb) roda à risca, passos 1 a 8.
    # O 6 saiu na integração 2 do #2414: exemplo_06_aniversario_spec.rb roda à risca, passos 1 a 10, com o link da página
    # de reserva (G60), o card criado no passo 3 (G49), a reunião marcada (G32, G61) e a atendida (G56, G59).
    # O 7 saiu no lote 3 do #2414, com as sondas da G37 e da G38 ligadas: exemplo_07_black_friday_spec.rb roda à risca,
    # passos 1 a 8.
    # O 8 saiu na integração 2 do #2414: exemplo_08_funcionario_novo_spec.rb roda à risca, passos 1 a 9, com o laço dos
    # documentos na 2ª automação (G46), a operadora pelo "webhook" (G13) e o aviso de sexta ao RH (G22, o solicitante
    # gravado pelo "para cada item").
    # O 9 saiu com a G58 (#2784) sobre a G21 (#2706): exemplo_09_prospeccao_semanal_spec.rb roda à risca, com a campanha
    # só às empresas que a busca criou nesta execução (o registro real da busca grava os card_ids).
    # O 10 saiu com o lote 4 (#2682, G40) depois da G41 (#2759): o spec dele roda à risca, com a espera só pela Fernanda.
    # O 13 saiu com o lote 2 (#2679): o spec dele roda à risca, com o card ganho e a IA lendo o card.
    # O 11 saiu com a G49: o spec dele roda à risca (exemplo_11_indicacao_spec.rb).
    # O 12 saiu na integração 2 do #2414, com a G25 (#2654) sobre a G48 da main: exemplo_12_visita_feita_spec.rb roda à
    # risca, passos 1 a 8.
    # O 15 saiu com o G27 (#2661) sobre o lote 4 (#2687, G40): exemplo_15_cliente_grande_spec.rb roda à risca.
    # O 14 saiu com a G13 (#2676) na integração 2 do #2414: exemplo_14_documentacao_spec.rb roda à risca, passos 1 a 8, numa
    # automação só (G46), com a seguradora pelo passo "webhook".
    # O 16 saiu no lote 3 do #2414, com a G55 (#2823, a campanha da vez num gatilho de card) e a G38:
    # exemplo_16_reconquista_spec.rb roda à risca, passos 1 a 8.
    # O 17 saiu com a G66 (#2843), a G67 (#2844) e a decisão 18: exemplo_17_ferias_spec.rb roda à risca numa automação
    # só, inteiro, sem pendente (a agente de IA cobre a Renata pela opção do passo, e a conversa volta quando ela escreve).
    # O 18 saiu na integração 2 do #2414: exemplo_18_selecao_de_candidatos_spec.rb roda à risca, passos 1 a 9, com o
    # currículo no filtro da mensagem (G45), o link da página "Entrevistas" (G44) e o card criado no passo 2 fechado no 6 (G49).
    # O 19 saiu com a G68 (#2864) na integração 2 do #2414: exemplo_19_cliente_sumiu_spec.rb roda à risca, passos 1 a 7
    # (por partes também em g53_conteudo_da_falha_spec.rb e g43_numero_novo_spec.rb).
    20 => ['Venda fechada já entra no sistema da empresa', 'G5 (card ganho), G1, G2, G7, G11, G12, G13, G44 (duas agendas), G52 (campanha de e-mail)']
  }

  it 'sonda quebrada é erro, nunca pendente' do
    stub_const('FechamentoAutomacao::Lacunas::SONDAS', { 'GX' => -> { raise NameError, 'classe renomeada' } })

    expect { FechamentoAutomacao::Lacunas.abertas(%w[GX]) }.to raise_error(NameError)
  end

  # As sondas do 17 rodam o código de verdade; com o exemplo fora da lista, a prova delas fica aqui.
  it 'exemplo 17: as lacunas fechadas por comportamento continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G63 G64 G66 G67])).to be_empty
  end

  # Com o 19 fora da lista, a prova das sondas dele fica aqui: a G42 leva ao resumo os envios falhos do modelo e do
  # e-mail, a G43 manda ao número novo e a G68 lê a resposta do e-mail.
  it 'exemplo 19: as lacunas fechadas por comportamento continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G42 G43 G68])).to be_empty
  end

  # Os exemplos 6, 8, 14 e 18 saíram da lista na integração 2 do #2414: a prova das sondas que os seguravam fica aqui.
  it 'exemplos 6, 8, 14 e 18: as lacunas fechadas continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G13 G22 G24 G25 G27 G31 G32 G44 G45 G46 G49 G56 G59 G60 G61])).to be_empty
  end

  # Com o 4 fora da lista, a prova das sondas que o seguravam fica aqui.
  it 'exemplo 4: as lacunas fechadas continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G1 G3 G4 G5 G12 G15 G18 G25 G28 G44 G50])).to be_empty
  end

  # Os exemplos 7 e 16 saíram da lista no lote 3 do #2414: a prova das sondas que os seguravam fica aqui. A G70 (#2880,
  # decisão 20) é o "grava no card" direto dos exemplos 2 (passo 9) e 7 (passo 4), sem a cópia pela conversa.
  it 'exemplos 2, 7 e 16: as lacunas fechadas continuam fechadas' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G3 G4 G5 G7 G12 G14 G15 G16 G18 G37 G38 G39 G55 G69 G70])).to be_empty
  end

  # G21 (#2706) não segura nenhum pendente: a sonda roda aqui para que a prova de comportamento dela não fique sem dono.
  it 'G21 fechada: o passo prospecção busca e cria o card' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G21])).to be_empty
  end

  # G57 (#2769) e G58 (#2779) também não seguram pendente: as sondas rodam o motor e a busca de verdade aqui.
  it 'G57 e G58 fechadas: a hora de hoje que passou vence em seguida; o público da execução é só o que ela criou' do
    expect(FechamentoAutomacao::Lacunas.abertas(%w[G57 G58])).to be_empty
  end

  pendentes.each do |numero, (nome, lacunas)|
    it "exemplo #{numero}: #{nome}" do
      # Fora do `pending`: sonda quebrada (classe renomeada) é erro vermelho, não "falha esperada".
      abertas = FechamentoAutomacao::Lacunas.abertas(lacunas.split(', ').map { |lacuna| lacuna.split.first })
      pending "lacunas #{lacunas}. #{FechamentoAutomacao::Lacunas::SE_PASSOU % numero}"
      expect(abertas).to be_empty
    end
  end
end
