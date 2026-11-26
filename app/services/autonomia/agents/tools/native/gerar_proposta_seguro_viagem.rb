# GERAR PROPOSTA DO SEGURO VIAGEM (#3211): a ferramenta do agente contratado "Seguro Viagem Universal" que cria a
# compra na Universal (`POST /v1/Compras`) com o plano escolhido da ÚLTIMA cotação da conversa e devolve o link de
# pagamento. É o caminho do dinheiro.
#
# PREÇO E PLANO SÓ DA COTAÇÃO GUARDADA (R3). O modelo escolhe o código (`P1`); valor, produto, tarifa, datas e destinos
# saem da cotação (`SeguroViagem::Compra`). Código que a cotação não tem é recusado antes de qualquer chamada. A cotação
# vale no dia em que foi feita, e a idade real de cada viajante (pela data de nascimento, na saída) precisa cair na
# mesma faixa de preço das idades cotadas; senão o modelo cota de novo.
#
# UMA PROPOSTA POR DADO (R3). A chave da proposta cobre TODO o dado de entrada: a cotação, o plano, os viajantes, o
# contato do titular, o endereço como veio (CEP, número, complemento) e o contato de emergência. A chamada idêntica
# devolve a proposta guardada sem segunda compra, e isso é conferido antes da busca do CEP (a repetição sai mesmo com a
# fonte de CEP fora). Sob o lock da cotação a chave é conferida de novo: a outra chamada que correr junto espera o lock
# e cai no mesmo caso; se a espera passar do tempo do banco, ela recusa (`proposta_em_andamento`) sem chamar a
# seguradora. Dado corrigido (outro e-mail, por exemplo) é outra chave e outra proposta.
#
# SEGURO PAGO NÃO SE REFAZ (#3247). Cotação com `pago_em`, ou outra cotação da mesma viagem (destinos, datas e idades)
# nesta conversa com `pago_em`, recusa `proposta_ja_paga` antes de qualquer chamada (`SeguroViagem::PropostaPaga`); a
# conferência se repete sob o lock da cotação.
#
# DADO PESSOAL. CPF, nome, e-mail, telefone e endereço vão só no corpo da compra. A proposta guardada não leva dado
# pessoal (a chave é um HMAC com uma chave derivada do segredo da aplicação, não um hash que se reverte pelos CPFs
# possíveis), e o texto ao modelo leva só o link, o número do carrinho, o nome do plano e o total da cotação.
#
# NUNCA LEVANTA com a seguradora fora: o erro do cliente HTTP e a compra sem link passam por `SeguroViagem::Falhas`.
# Toda outra recusa passa por `recusar`/`error` da `Base`, que registra (R5).
class Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Universal = Autonomia::Seguradoras::Universal

  # O endereço não veio: CEP não achado OU consulta de CEP fora (pronta desligada, sem acesso, limite do dia). As duas
  # dão nil em `EnderecoDoCep.buscar`, então o texto não afirma que o CEP está errado.
  TEXTO_SEM_ENDERECO = 'Não consegui o endereço pelo CEP do titular. Confirme o CEP com o cliente; se estiver certo, ' \
                       'passe a conversa para a equipe.'.freeze
  TEXTO_EM_ANDAMENTO = 'Já tem uma proposta sendo gerada para esta cotação. Espere um pouco e confira de novo.'.freeze
  # #3246b: o turno acionado pelo aviso de pagamento (`Operate::ResponderAoEventoDaViagem`) não vira compra.
  TEXTO_TURNO_DE_EVENTO = 'Este turno é um aviso do sistema, não um pedido do cliente: não gere proposta agora. Se o ' \
                          'cliente quiser uma proposta nova, ele vai pedir na próxima mensagem.'.freeze
  # #3247: o seguro já pago não vira proposta nova. Sem molde: o texto diz o que é verdade e o que cabe a cada caso.
  TEXTO_JA_PAGO = 'O seguro desta viagem já está pago, então não gero outra proposta: ela apagaria o rastro do que foi ' \
                  'pago e o cliente pagaria de novo. Se ele quer o voucher, use segunda_via_do_voucher. Se é outra viagem ' \
                  '(outros destinos, outras datas ou outros viajantes), cote a viagem nova. Troca de plano, de data ' \
                  'ou de viajante num seguro já pago, e cancelamento, são com a equipe: passe a conversa para ela.'.freeze
  # O `SELECT … FOR UPDATE` do lock que passou do `statement_timeout` (ou do `lock_timeout`) do banco.
  ESPERA_DO_LOCK = [ActiveRecord::QueryCanceled, ActiveRecord::LockWaitTimeout].freeze
  # A Universal cancela o link de pagamento 24 h depois da compra (e-mail "Pagamento pedido", 26/11). Uma hora de folga
  # para não devolver um link prestes a vencer; passado isso, a mesma proposta gera carrinho e link novos.
  VALIDADE_DO_LINK = 23.hours
  # `{ "a": 1, "b": 2 }`: cada valor é uma palavra separada por espaço (`resposta`).
  JSON_COM_ESPACO = { space: ' ', object_nl: ' ', array_nl: ' ' }.freeze

  VIAJANTE = [
    { 'name' => 'nome_completo', 'type' => 'string', 'required' => true, 'description' => 'Nome completo.' },
    { 'name' => 'cpf', 'type' => 'string', 'required' => true, 'description' => 'CPF completo.' },
    { 'name' => 'data_nascimento', 'type' => 'string', 'required' => true, 'description' => 'AAAA-MM-DD.' }
  ].freeze

  class << self
    include SeguroViagem::PortaDoContratado

    # ESCREVE: cria a compra na seguradora e grava a proposta na cotação.
    def escreve? = true

    def slug
      'gerar_proposta_seguro_viagem'
    end

    def tool_name
      'Gerar proposta do seguro viagem'
    end

    def description
      'Gera na seguradora a proposta de compra do plano escolhido da última cotação desta conversa e devolve o link ' \
        'de pagamento. Chame só depois de o cliente escolher o plano e confirmar nome completo, CPF e data de ' \
        'nascimento de cada viajante, e e-mail, telefone, CEP e número do endereço do titular. O preço é o da cotação; ' \
        'nunca informe outro.'
    end

    def args_registraveis
      %w[codigo_do_plano]
    end

    def params
      [
        { 'name' => 'codigo_do_plano', 'type' => 'string', 'required' => true,
          'description' => 'Código do plano escolhido, da última cotação desta conversa.' },
        { 'name' => 'titular', 'type' => 'object', 'required' => true, 'properties' => VIAJANTE + [
          { 'name' => 'email', 'type' => 'string', 'required' => true, 'description' => 'E-mail do titular.' },
          { 'name' => 'telefone', 'type' => 'string', 'required' => true, 'description' => 'Telefone com DDD.' },
          { 'name' => 'cep', 'type' => 'string', 'required' => true, 'description' => 'CEP do endereço, 8 dígitos.' },
          { 'name' => 'numero', 'type' => 'string', 'required' => true, 'description' => 'Número do endereço.' },
          { 'name' => 'complemento', 'type' => 'string', 'required' => false, 'description' => 'Complemento; null sem.' }
        ] },
        { 'name' => 'demais_viajantes', 'type' => 'array', 'required' => true, 'items' => { 'properties' => VIAJANTE },
          'description' => 'Os outros viajantes da cotação. Lista vazia quando só o titular viaja.' },
        { 'name' => 'contato_de_emergencia', 'type' => 'object', 'required' => true, 'properties' => [
          { 'name' => 'nome', 'type' => 'string', 'required' => true, 'description' => 'Nome de quem fica no Brasil.' },
          { 'name' => 'telefone', 'type' => 'string', 'required' => true, 'description' => 'Telefone com DDD.' }
        ] }
      ]
    end
  end

  def call
    return error('proposta_sem_conversa') if conversa.nil?

    no_evento = recusa_no_turno_de_evento
    return no_evento if no_evento

    cotacao = Autonomia::Agents::CotacaoDeViagem.ultima_da_conversa(conversa.id, agent.id)
    recusa = recusa_da_cotacao(cotacao)
    return recusa if recusa

    plano = cotacao.plano(codigo)
    # Plano sem preço guardado não vira compra: o preço da compra é sempre o da cotação (R3).
    if plano.nil? || SeguroViagem::Compra.preco(plano).nil?
      return recusar('plano_inexistente', "O plano #{codigo} não está na última cotação com preço. Os códigos são " \
                                          "#{cotacao.planos.pluck('codigo').join(', ')}.", faltando: ['codigo_do_plano'])
    end

    conferir_e_propor(cotacao, plano)
  end

  private

  # Aviso do sistema nunca vira compra (#3246b), como a agenda (`agendar_reuniao`): nada vai à seguradora. nil fora dele.
  def recusa_no_turno_de_evento
    recusar('proposta_turno_de_evento', TEXTO_TURNO_DE_EVENTO) if delivery.try(:turno_de_evento?)
  end

  # O que a cotação sozinha já recusa, na ordem. O pago vem antes de tudo (do dia da cotação, do CEP, da seguradora): o
  # que já foi pago não se refaz (#3247). nil quando nada recusa.
  def recusa_da_cotacao(cotacao)
    return recusar('sem_cotacao', 'Esta conversa ainda não tem cotação. Cote primeiro.') if cotacao.nil?
    return recusar('proposta_ja_paga', TEXTO_JA_PAGO) if SeguroViagem::PropostaPaga.impedindo(cotacao, agent)

    recusar('recotar', 'A cotação desta conversa é de outro dia e o preço pode ter mudado. Cote de novo.') unless cotacao.do_dia?(fuso)
  end

  def conferir_e_propor(cotacao, plano)
    viajantes, contato, falta = conferidos
    return recusar('pedido_invalido', falta.texto, faltando: [falta.campo]) if falta

    if viajantes.size != cotacao.idades.size
      return recusar('quantidade_de_viajantes', "A cotação é para #{cotacao.idades.size} viajante(s) e vieram " \
                                                "#{viajantes.size}. Confirme quem viaja; se mudou, cote de novo.",
                     faltando: ['demais_viajantes'])
    end

    reais = SeguroViagem::Faixas.idades_na_saida(viajantes, cotacao.pedido['data_saida'])
    unless SeguroViagem::Faixas.mesma_faixa?(plano, cotacao.idades, reais)
      return recusar('recotar', 'A idade real pela data de nascimento muda a faixa de preço. Cote de novo com as ' \
                                "idades: [#{reais.join(', ')}]", faltando: ['idades'])
    end

    buscar_endereco_e_propor(cotacao, plano, viajantes, contato)
  end

  # A repetição idêntica devolve a proposta guardada ANTES da busca do CEP: a chave usa o CEP como veio, e a repetição
  # sai mesmo com a fonte de CEP fora.
  def buscar_endereco_e_propor(cotacao, plano, viajantes, contato)
    chave = chave(cotacao, viajantes, contato)
    return resposta(plano, cotacao.proposta) if guardada?(cotacao, chave)

    endereco = SeguroViagem::EnderecoDoCep.buscar(agent: agent, cep: viajantes.first['cep'])
    return recusar('cep_nao_encontrado', TEXTO_SEM_ENDERECO, faltando: ['titular.cep']) if endereco.nil?

    propor(cotacao, plano, SeguroViagem::Compra.montar(cotacao: cotacao, plano: plano, viajantes: viajantes,
                                                       endereco: endereco, contato: contato), chave)
  end

  # -> [viajantes, contato, nil] ou [nil, nil, Falta]
  def conferidos
    viajantes, falta = SeguroViagem::Viajantes.conferir(
      titular: params['titular'], demais: params['demais_viajantes'], telefone_da_conversa: conversa&.contact&.phone_number
    )
    return [nil, nil, falta] if falta

    contato, falta = SeguroViagem::Viajantes.contato(params['contato_de_emergencia'])
    [viajantes, contato, falta]
  end

  # A compra roda sob o lock da cotação; as falhas são tratadas fora dele (a nota e o acesso não entram na transação).
  # Só a espera pelo lock vira `proposta_em_andamento`: o tempo do banco estourado depois de travar (já dentro da
  # compra) sobe como erro, porque aí a seguradora pode ter criado o carrinho.
  def propor(cotacao, plano, pedido, chave)
    proposta = nil
    travada = false
    paga = false
    cotacao.with_lock do
      travada = true
      # `with_lock` relê a cotação: a varredura do pagamento pode ter gravado `pago_em` desde a primeira conferência. As
      # outras cotações (mesma viagem) não são travadas: conferir antes basta, porque só a varredura as altera (#3247).
      paga = SeguroViagem::PropostaPaga.paga?(cotacao)
      proposta = guardada_ou_nova(cotacao, plano, pedido, chave) unless paga
    end
    return recusar('proposta_ja_paga', TEXTO_JA_PAGO) if paga
    return SeguroViagem::Falhas.sem_link(acao: self.class.slug, agent: agent, conversation: conversa) if proposta.nil?

    resposta(plano, proposta)
  rescue *ESPERA_DO_LOCK
    raise if travada

    recusar('proposta_em_andamento', TEXTO_EM_ANDAMENTO)
  rescue Universal::Cliente::Erro => e
    SeguroViagem::Falhas.tratar(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  # -> a proposta da mesma chave já guardada, ou a nova, gravada; nil quando a compra voltou sem link. `with_lock` relê
  # a cotação: a proposta comparada é a que está no banco agora, e a chamada que correr junto espera e cai no primeiro
  # caso.
  def guardada_ou_nova(cotacao, plano, pedido, chave)
    return cotacao.proposta if guardada?(cotacao, chave)

    proposta = proposta_da(cliente.comprar(pedido), plano, chave)
    cotacao.update!(proposta: proposta) if proposta
    proposta
  end

  # O que fica guardado, sem dado pessoal: a chave, o plano, o carrinho, o link e a hora. Compra sem `urlVoucher` de
  # pagamento válido (sem link): nil. O `valorBrutoBrl` da resposta volta 0 (#3244) e não é guardado.
  def proposta_da(compra, plano, chave)
    dados = compra.is_a?(Hash) ? compra : {}
    link = SeguroViagem::Compra.link(dados['urlVoucher'])
    return nil if link.nil?

    { 'chave' => chave, 'codigo_do_plano' => plano['codigo'], 'codigo_carrinho' => dados['codigoCarrinho'],
      'link' => link, 'gerada_em' => Time.current.iso8601 }
  end

  # O JSON SAI COM ESPAÇO depois de `:` e `,` (#3246): o botão de link só reconhece o endereço que é uma palavra
  # separada por espaço (`Interacao::Enderecos.dos_textos`), e no JSON compacto o link grudava no campo seguinte.
  def resposta(plano, proposta)
    JSON.generate({ link_de_pagamento: proposta['link'], numero_do_carrinho: proposta['codigo_carrinho'],
                    plano: plano['nome'], total: SeguroViagem::Dinheiro.brl(plano['preco_total']),
                    **SeguroViagem::Cancelamento.prazos(plano, hoje: fuso.today) }, JSON_COM_ESPACO)
  end

  def guardada?(cotacao, chave)
    proposta = cotacao.proposta.to_h
    proposta['chave'] == chave && link_vigente?(proposta['gerada_em'])
  end

  def link_vigente?(gerada_em)
    momento = Time.zone.parse(gerada_em.to_s)
    momento.present? && momento > VALIDADE_DO_LINK.ago
  rescue ArgumentError
    false
  end

  def chave(cotacao, viajantes, contato)
    SeguroViagem::ChaveDaProposta.de(cotacao: cotacao, codigo: codigo, viajantes: viajantes, contato: contato)
  end

  def codigo
    params['codigo_do_plano'].to_s.strip.upcase
  end

  def conversa
    delivery.try(:conversation)
  end

  def acesso
    agent.acesso_da_seguradora
  end

  def cliente
    Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end

  # O dia de hoje no fuso da conta, como na cotação.
  def fuso
    Crm::Timezone::Resolver.new(account: account).zone_or_default
  end
end
