require 'rails_helper'

# Fechamento do épico #2414 (F9.6): os exemplos dos termos de aceite que ainda não rodam na main. Cada um fica pendente
# com as lacunas que o seguram (códigos G* de docs/automacao/F9-fechamento-20-exemplos.md, seção 5). Quando as lacunas
# de um exemplo fecham, ele ganha o arquivo próprio, como o exemplo 10, e sai daqui. O épico só fecha com os 20
# passando (F9.8).
RSpec.describe 'Fechamento #2414 · exemplos que ainda não rodam', type: :model do
  pendentes = {
    # O 2 saiu com o #2762 (G29), depois do #2773 (G30) e do #2800 (G32); o spec de ponta a ponta dele é o #2856.
    # O 4 tem spec próprio à risca (exemplo_04_aluno_que_falta_spec.rb); esperam a G50 (a segunda falta com a primeira
    # ainda esperando), a G44 (passos 6 e 8, link de uma página escolhida) e a G18 (passo 10, fechar o card de retenção).
    4 => ['Aluno que começa a faltar', 'G50 (reentrada no mesmo card), G44, G18, G5, G1, G3, G4, G12, G15, G25, G28'],
    # O 5 saiu com a G47 (#2766): o spec próprio (exemplo_05_revisao_do_carro_spec.rb) roda à risca, passos 1 a 8.
    # Numa automação só (no contato, pelo aniversário), os passos 2, 3, 7 a 9 e o aviso do 6 rodam
    # (g59_reuniao_atendida_na_espera_spec.rb: G56, G59, G60, G61); a G47 não segura o passo 8, porque a espera lê a
    # reunião de qualquer card do contato. Faltam a G49 (gravar no card que a automação criou, passos 5 e 6) e a G25
    # (fechar o card, passo 10).
    6 => ['Aniversário que vira horário marcado', 'G49 (gravar no card criado), G25, G1, G4, G6, G12, G14, G16, G33, G56, G59, G60, G61'],
    7 => ['Black Friday para os clientes antigos primeiro', 'G37 (público com exclusão), G38, G39, G5, G7, G14, G15'],
    # O 8 tem spec próprio dos passos 1 a 5 (exemplo_08_funcionario_novo_spec.rb, G24 #2771); faltam os passos 6 a 9.
    8 => ['Funcionário novo no plano da empresa',
          'G31 (passos 6 e 7: voltar a esperar a cada documento na 2ª automação), G27 (passo 8: card completo), G13, ' \
          'G22 (passo 9: avisar o RH toda sexta), G7, G24'],
    # O 9 saiu com a G58 (#2784) sobre a G21 (#2706): exemplo_09_prospeccao_semanal_spec.rb roda à risca, com a campanha
    # só às empresas que a busca criou nesta execução (o registro real da busca grava os card_ids).
    # O 10 saiu com o lote 4 (#2682, G40) depois da G41 (#2759): o spec dele roda à risca, com a espera só pela Fernanda.
    # O 13 saiu com o lote 2 (#2679): o spec dele roda à risca, com o card ganho e a IA lendo o card.
    # O 11 saiu com a G49: o spec dele roda à risca (exemplo_11_indicacao_spec.rb).
    # O 12 tem spec próprio à risca (exemplo_12_visita_feita_spec.rb); a espera do passo 3 está provada à risca
    # (g48_campo_do_card_spec.rb, passos 1 a 4 e 8); falta a G25 (passo 7).
    12 => ['Visita que aconteceu decide o próximo passo', 'G48 (o campo do card acorda a espera), G5, G2, G3, G11, G14, G25, G35'],
    # O 15 saiu com o G27 (#2661) sobre o lote 4 (#2687, G40): exemplo_15_cliente_grande_spec.rb roda à risca.
    # Os passos 1 a 6 têm spec próprio à risca, numa automação só (G46): exemplo_14_documentacao_spec.rb.
    14 => ['Documentação completa para emitir', 'G13 (passos 7 e 8: mandar à seguradora e gravar a proposta; a recusa avisa a Dona Cida)'],
    # #2675 (09/11): o "Começa quando" monta (card.recorrente com fechado_entre_dias e o "Só se" no card.motivo_da_perda).
    # Para no passo 2: a campanha só sai do conta.recorrente, e o gatilho do 16 roda em cada card; e no 3, a resposta à campanha.
    16 => ['Reconquistar quem foi para o concorrente',
           'G55 (passo 2: disparar a campanha da etiqueta num gatilho de card), G38 (passo 3: cada resposta à campanha), ' \
           'G3, G4, G7, G12, G14, G16, G18'],
    # O 17 saiu com a G66 (#2843), a G67 (#2844) e a decisão 18: exemplo_17_ferias_spec.rb roda à risca numa automação
    # só, inteiro, sem pendente (a agente de IA cobre a Renata pela opção do passo, e a conversa volta quando ela escreve).
    # O 18 tem spec próprio à risca (exemplo_18_selecao_de_candidatos_spec.rb); esperam a G45 (gatilho), a G18 (passos
    # 4 e 6, no card da seleção) e a G32 (passo 8, antes da reunião).
    18 => ['Seleção de candidatos sem planilha', 'G45 (mensagem com anexo), G18, G32, G4, G20, G1, G5, G6, G12, G15, G25'],
    # O 19 fica até a G68 (#2864): no passo 3 o extrair não lê a resposta que chegou por e-mail. Por partes:
    # g53_conteudo_da_falha_spec.rb (passos 1 e 2) e g43_numero_novo_spec.rb (4 e 7).
    19 => ['Cliente que sumiu do WhatsApp',
           'G68 (passo 3: o extrair lê a resposta do e-mail), ' \
           'G34 (passo 3: a resposta na conversa do e-mail), G28 (passo 3: extrair o número novo), G19 (passo 5: nota no contato), ' \
           'G3 (passo 6: retorno), G11 (passo 6: sem resposta em 3 dias), G53, G43, G8, G1, G2'],
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
