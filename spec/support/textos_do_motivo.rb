# OS TEXTOS REAIS E OS DAS REVISÕES DO MOTIVO DE RECUSA (fatia 2 do #420, sétima rodada: o motivo vira categoria, e
# nenhum texto do portal vai ao modelo). Usados por `motivo_da_recusa_spec`, `resultado_por_seguradora_spec` e
# `insurance_quote_result_spec`.
module TextosDoMotivo
  VEICULO = Autonomia::Insurance::MotivoDaRecusa::VEICULO

  # As 39 mensagens do corpus do conector (`autonomia-adapters`, `origin/main` `ad4372a597`,
  # `test/fixtures/agger/motivos-de-recusa.sanitized.json`): `textoLimpo`, o `kind` e o status que o conector dá a cada
  # uma, e a categoria que sai daqui.
  CORPUS = [
    ['Risco sem aceitação para este cenário nesta seguradora.', 'risco', 'declined', nil],
    ['Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro?', 'risco', 'declined', nil],
    ['Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida', 'risco', 'declined', VEICULO],
    ['Aceitacao Restrita, cobertura auto nao permitida para este modelo.', 'risco', 'declined', VEICULO],
    ['O veículo não possui aceitação para a categoria tarifária informada.', 'risco', 'declined', VEICULO],
    ['Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o ' \
     'risco deste orçamento.', 'risco', 'declined', nil],
    ['O sistema de cálculo está indisponível, tente novamente em alguns instantes.', 'passageiro', 'declined', nil],
    ['Serviço indisponível, tente novamente mais tarde', 'passageiro', 'declined', nil],
    ['Houve uma instabilidade ao realizar o cálculo nesta seguradora, tente novamente em breve.', 'passageiro', 'declined', nil],
    ['Usuário não possui acesso a funcionalidade. Por favor, verifique suas permissões no site da seguradora.', 'credencial',
     'auth_required', nil],
    ['Login ou senha incorreta. Confira suas credenciais de acesso.', 'credencial', 'auth_required', nil],
    ['Erro ao processar o cálculo do prêmio', 'outro', 'declined', nil],
    ['Desmoronamento - Para contratação desta cobertura é necessário enviar para Análise Técnica.', 'outro', 'declined', nil],
    ['O Nome informado não corresponde ao CPF cadastrado. Por favor, verifique e tente novamente.', 'outro', 'declined', nil],
    ['400 - Restrição técnica para o Segurado', 'risco', 'declined', nil],
    ['O valor informado de R$ 10.000,00 para a cobertura Roubo Residencial Condominos, Cobertura é invalido. O mínimo aceito',
     'outro', 'declined', nil],
    ['Corretor não encontrado. Por favor, selecione um corretor válido no cadastro da seguradora.', 'credencial', 'declined', nil],
    ["Necessário contratar primeiro uma das coberturas: '000510026 - Responsabilidade Civil Operacoes', '000510304 - Resp Civ",
     'outro', 'declined', nil],
    ['[165456] - Contratação da Cobertura Desmoronamento para o GRUPO ESCRITORIOS ATIVIDADE DEMAIS ESCRITÓRIOS está fora da p',
     'outro', 'declined', nil],
    ['Para a Cobertura Responsabilidade Civil Empregador, Obrigat ria a contrata o da Cobertura Responsabilidade Civil Est',
     'outro', 'declined', nil],
    ['A cobertura de INCENDIO / QUEDA DE RAIO / EXPLOSAO / IMPLOSAO ACIDENTAL / FUMACA / QUEDA DE AERONAVES não pode ser cont',
     'outro', 'declined', nil],
    ['LMI COB RC OBRIGATORIA PARA DANO MORAL', 'outro', 'declined', nil],
    ['Houve um erro ao realizar este cálculo.', 'outro', 'declined', nil],
    ['Não foi possível recuperar o valor dessa cotação. Por favor, tente novamente mais tarde.', 'passageiro', 'declined', nil],
    ['O valor do capital segurado deve ser entre R$100,00 e R$1.000,00, limitado a 250 vezes o capital segurado da cobertura',
     'outro', 'declined', nil],
    ['Profissão deve ser especificada corretamente para que o cálculo prossiga.', 'outro', 'declined', nil],
    ['Ocorreu uma divergencia entre a comissao informada e a comissao permitida.', 'credencial', 'declined', nil],
    ['Tipo de veículo não aceito.', 'risco', 'declined', VEICULO],
    ['Nenhum produto com seguro disponível para exibição.', 'outro', 'declined', nil],
    ['Só é permitida a contratação de [Faróis, Lanternas e Retrovisor] para veículos até 20 anos.', 'outro', 'declined', nil],
    ['[2005] - -Contratação não permitida - Ano Modelo do Veículo', 'risco', 'declined', VEICULO],
    ['Moto de ano/modelo sem aceitação - RP', 'risco', 'declined', VEICULO],
    ['[2159] - -Contratação não permitida - Categoria do Veículo', 'risco', 'declined', VEICULO],
    ['UC00 - Risco fora das políticas de aceitação As Necessidades do Cliente, não foram salvas com sucesso, selecione nov',
     'risco', 'declined', nil],
    ['Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP', 'risco', 'declined', nil],
    ['A cobertura "Impacto Veículos" não está disponível para esta cotação.', 'outro', 'declined', nil],
    ['Ocorreu um erro ao calcular. Revise o formulario de calculo e tente novamente.', 'outro', 'declined', nil],
    ['Origem da viagem deve ser especificada corretamente', 'outro', 'declined', nil],
    ['Cálculo sem prêmio.', 'outro', 'declined', nil]
  ].freeze

  # Os 28 textos de conta da corretora da quinta revisão, escritos só com palavras comuns: todos saem `risco` do
  # classificador real do conector, e metade nomeia o veículo.
  CONTA = [
    'Risco sem aceitação: cotação não é mais permitida nesta seguradora.',
    'Restrição técnica: cálculo de seguro auto não é mais permitido nesta seguradora.',
    'Veículo sem aceitação: contratação não é permitida nesta seguradora.', 'Veículo sem aceitação: cotação está restrita nesta seguradora.',
    'Cotação do veículo não permitida: dados internos com restrição nesta seguradora. Declinando cálculo.',
    'Aceitação restrita: dados não são aceitos para cotação de seguro auto.',
    'Nova análise dos dados obrigatória para cotação do veículo. Declinando cálculo.',
    'Seguro auto com restrição para o tipo de contratação. Declinando cálculo.',
    'Veículo sem aceitação: seguro auto não está disponível nesta seguradora.', 'Seguro auto não disponível nesta seguradora. Declinando cálculo.',
    'Nova cotação não permitida para este veículo. Declinando cálculo.',
    'Cálculo já realizado para este veículo nesta seguradora. Declinando cálculo.',
    'Seguradora com restrição interna para cotação de seguro auto. Declinando cálculo.',
    'Dados internos não informados para cotação de seguro auto. Declinando cálculo.',
    'Risco sem aceitação: dados informados com restrição na seguradora.', 'Risco sem aceitação: cotação proibida por política interna.',
    'Risco sem aceitação: cotação recusada por critério interno da seguradora.',
    'Veículo sem aceitação: dados obrigatórios da seguradora não informados.',
    'Cotação de frota não permitida nesta seguradora. Declinando cálculo.', 'Seguro auto não permitido nesta seguradora. Declinando cálculo.',
    'Veículo sem aceitação: nova cotação apenas após análise interna.', 'Risco sem aceitação: cálculo não pode ser realizado nesta seguradora.',
    'Aceitação restrita: cotação de seguro auto somente com análise interna.',
    'Risco sem aceitação: seguradora não possui cotação disponível para este tipo.',
    'Recusa dos dados informados: declinando cálculo do seguro auto.', 'Veículo sem aceitação: dados da cotação recusados pela seguradora.',
    'Veículo sem aceitação: sua cotação não é mais permitida.', 'Limite de cotação atingido para o veículo. Declinando cálculo.'
  ].freeze

  # Os 6 textos com dado da pessoa da quinta revisão: pode ser restrição financeira de quem não conversa.
  PESSOA = [
    'Segurado com restrição. Declinando cálculo.', 'Condutor principal com restrição. Declinando cálculo.',
    'Segurada com restrição nesta seguradora. Declinando cálculo.', 'Risco sem aceitação: dados do segurado com restrição.',
    'Risco sem aceitação: segurado com sinistro de roubo.', 'Risco sem aceitação: condutor principal com restrição de dados.'
  ].freeze

  # Os da revisão do conector e das revisões anteriores da fatia 2, que saem `risco` do classificador real falando da
  # conta da corretora, de dado pessoal ou de valor, e os de letra que não se translitera.
  REVISOES = [
    'Senha expirou. Declinando cálculo.', 'Usuário fulano@corretora.com.br bloqueado.',
    'Sistema indisponível: sessão expirada, faça login novamente.', 'Produtor não credenciado para este produto. Declinando cálculo.',
    'Não autorizado a calcular este produto. Declinando cálculo.', 'Código SUSEP inválido. Declinando cálculo.',
    'Sistema deslogado. Declinando cálculo.', 'Corretagem acima do limite do produto. Declinando cálculo.',
    'Descredenciado para este produto. Declinando cálculo.', 'Conta suspensa nesta seguradora. Declinando cálculo.',
    'Entre novamente no portal da seguradora. Declinando cálculo.', 'Contato do suporte: <REDACTED>. Declinando cálculo.',
    'Risco fora das políticas de aceitação Licença do multicálculo vencida.', 'Veículo sem aceitação por conta inativa nesta seguradora.',
    'Veículo sem aceitação: access denied.', 'Veículo sem aceitação: operador joao.silva.',
    'Veículo sem aceitação: CPF do operador divergente.', 'Categoria do veículo sem aceitação para o parceiro.',
    'Tarifa do veículo sem aceitação no seu perfil comercial.', 'Modelo de contrato do parceiro não assinado. Declinando cálculo.',
    'Veículo sem aceitação: proprietário anterior com restrição.', 'Limite máximo de cotação de seguro auto nesta seguradora. Declinando cálculo.',
    'Veículo sem aceitação: sua tabela não é mais aceita.', 'Veículo sem aceitação: ꜱᴇɴʜᴀ ᴇˣᴘɪʀᴏᴜ.', 'Veículo sem aceitação: ＳＥＮＨＡ ＥＸＰＩＲＯＵ.'
  ].freeze
end
