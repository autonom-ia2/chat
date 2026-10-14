# Os modelos prontos que a plataforma cria sozinha quando precisa mandar um aviso fora da janela de 24 h (#1518). Cada
# finalidade tem uma ou mais variantes; cada variante é UM modelo, com nome estável (o mesmo em toda caixa: é ele que
# torna a criação idempotente e que acha o modelo na lista da caixa), categoria UTILITY e pt_BR.
#
# Escritos para a Meta aprovar como serviço: falam de algo que a pessoa já tem com a empresa, sem oferta; variável nunca
# no começo nem no fim do corpo; variáveis numeradas na ordem do texto; um exemplo para cada uma. `campos` diz de onde
# vem cada variável do corpo (chaves do catálogo de campos, `TemplateFields::Catalog`), e é por ele que quem envia preenche.
#
# Botões (opcionais, para o lembrete do agendamento, #1524): `url` (endereço fixo ou com {{1}} no fim, preenchido pelo
# `campo`, com exemplo) e `quick_reply` (texto fixo; o `payload` vai no envio, não no modelo). Quick replies juntos, como a
# Meta pede (`SubmitFormat`). O que o envio precisa saber deles está em `Pronto#botoes_do_envio`.
#
# Cobrança (`cobranca_vencimento`, #1498): um modelo por momento (antes, no dia, depois do vencimento) e por valor (com
# ou sem). O momento é texto fixo, não variável: é o texto fixo que a Meta aprova. Sem "negócio" nem "compra" no texto.
module Whatsapp::Templates::Finalidades
  # Finalidade ou variante que não existe: erro de quem chama.
  class Desconhecida < ArgumentError; end

  Pronto = Data.define(:finalidade, :nome, :nome_amigavel, :dono, :idioma, :texto, :campos, :botoes) do
    # O pedido de criação no formato da Meta (o mesmo que a tela de Modelos manda ao `MetaClient`).
    def corpo
      exemplos = campos.values.map { |campo| Whatsapp::Templates::Finalidades::EXEMPLOS.fetch(campo) }
      components = [{ type: 'BODY', text: texto, example: { body_text: [exemplos] } }]
      components << { type: 'BUTTONS', buttons: botoes.map { |botao| botao_da_meta(botao) } } if botoes.any?
      { name: nome, language: idioma, category: Whatsapp::Templates::Finalidades::CATEGORIA, components: components }
    end

    # [{ 'indice' => 0, 'tipo' => 'url', 'campo' => 'horario.link_codigo' }, { 'indice' => 1, 'tipo' => 'quick_reply',
    # 'payload' => 'stop_notices' }]: a posição de cada botão no modelo, para quem envia montar os `buttons` alinhados.
    # `campo` só no URL com variável; `payload` só no quick_reply que leva um.
    def botoes_do_envio
      botoes.each_with_index.map do |botao, indice|
        { 'indice' => indice, 'tipo' => botao[:tipo], 'campo' => botao[:campo], 'payload' => botao[:payload] }.compact
      end
    end

    private

    def botao_da_meta(botao)
      return { type: 'QUICK_REPLY', text: botao[:texto] } if botao[:tipo] == 'quick_reply'

      url = { type: 'URL', text: botao[:texto], url: botao[:url] }
      botao[:campo] ? url.merge(example: [botao[:url].split('{{').first + botao[:exemplo]]) : url
    end
  end

  IDIOMA = 'pt_BR'.freeze
  CATEGORIA = 'UTILITY'.freeze
  EXEMPLOS = {
    'cliente.primeiro_nome' => 'Ana', 'negocio.valor' => 'R$ 150,00', 'negocio.titulo' => 'Mensalidade de outubro',
    'negocio.vencimento' => '20/10/2026'
  }.freeze
  COBRANCA_FIM = 'Se o pagamento já foi feito, por favor desconsidere esta mensagem.'.freeze
  COBRANCA_DEPOIS_FIM = "Se precisar de ajuda com o pagamento, é só responder esta mensagem. #{COBRANCA_FIM}".freeze
  COM_VALOR = %w[cliente.primeiro_nome negocio.valor negocio.titulo negocio.vencimento].freeze
  SEM_VALOR = %w[cliente.primeiro_nome negocio.titulo negocio.vencimento].freeze

  # finalidade => { dono:, opcoes: [chaves da variante],
  #                 variantes: { [valores das opções] => { nome:, amigavel:, texto:, campos:, botoes: [] } } }
  CATALOGO = {
    'cobranca_vencimento' => {
      dono: 'cobranca',
      opcoes: %i[momento com_valor],
      variantes: {
        ['antes', true] => { nome: 'cobranca_antes_vencimento_com_valor_v1', amigavel: 'Cobrança: antes do vencimento (com valor)',
                             campos: COM_VALOR,
                             texto: 'Olá, {{1}}! Passando para lembrar que o seu pagamento de {{2}} referente a {{3}} vence em ' \
                                    "{{4}}. #{COBRANCA_FIM}" },
        ['antes', false] => { nome: 'cobranca_antes_vencimento_sem_valor_v1', amigavel: 'Cobrança: antes do vencimento',
                              campos: SEM_VALOR,
                              texto: 'Olá, {{1}}! Passando para lembrar que o seu pagamento referente a {{2}} vence em {{3}}. ' \
                                     "#{COBRANCA_FIM}" },
        ['no_dia', true] => { nome: 'cobranca_dia_vencimento_com_valor_v1', amigavel: 'Cobrança: no dia do vencimento (com valor)',
                              campos: COM_VALOR,
                              texto: "Olá, {{1}}! O seu pagamento de {{2}} referente a {{3}} vence hoje, {{4}}. #{COBRANCA_FIM}" },
        ['no_dia', false] => { nome: 'cobranca_dia_vencimento_sem_valor_v1', amigavel: 'Cobrança: no dia do vencimento',
                               campos: SEM_VALOR,
                               texto: "Olá, {{1}}! O seu pagamento referente a {{2}} vence hoje, {{3}}. #{COBRANCA_FIM}" },
        ['depois', true] => { nome: 'cobranca_apos_vencimento_com_valor_v1', amigavel: 'Cobrança: depois do vencimento (com valor)',
                              campos: COM_VALOR,
                              texto: 'Olá, {{1}}! O seu pagamento de {{2}} referente a {{3}} venceu em {{4}} e ainda não consta ' \
                                     "como pago. #{COBRANCA_DEPOIS_FIM}" },
        ['depois', false] => { nome: 'cobranca_apos_vencimento_sem_valor_v1', amigavel: 'Cobrança: depois do vencimento',
                               campos: SEM_VALOR,
                               texto: 'Olá, {{1}}! O seu pagamento referente a {{2}} venceu em {{3}} e ainda não consta como ' \
                                      "pago. #{COBRANCA_DEPOIS_FIM}" }
      }
    }
  }.freeze

  module_function

  # O pronto de uma finalidade para as opções dadas (`momento:`, `com_valor:` na cobrança). Opção a mais, a menos ou
  # desconhecida é `Desconhecida`.
  def pronto(finalidade, **opcoes)
    definicao = CATALOGO[finalidade.to_s] || raise(Desconhecida, "finalidade #{finalidade}")
    raise Desconhecida, "opções #{opcoes.keys.sort}" unless opcoes.keys.sort == definicao[:opcoes].sort

    chave = definicao[:opcoes].map { |opcao| normalizar(opcoes[opcao]) }
    variante = definicao[:variantes][chave] || raise(Desconhecida, "variante #{chave}")
    montar(finalidade.to_s, definicao[:dono], variante)
  end

  def prontos
    CATALOGO.flat_map do |finalidade, definicao|
      definicao[:variantes].values.map { |variante| montar(finalidade, definicao[:dono], variante) }
    end
  end

  # O dono (selo "Usado pelo sistema" da tela de Modelos) de um nome de pronto, ou nil.
  def dono_de(nome)
    prontos.find { |pronto| pronto.nome == nome.to_s }&.dono
  end

  def normalizar(valor)
    valor.is_a?(Symbol) ? valor.to_s : valor
  end

  def montar(finalidade, dono, variante)
    campos = variante[:campos].each_with_index.to_h { |campo, index| [(index + 1).to_s, campo] }
    Pronto.new(finalidade: finalidade, nome: variante[:nome], nome_amigavel: variante[:amigavel], dono: dono, idioma: IDIOMA,
               texto: variante[:texto], campos: campos, botoes: variante.fetch(:botoes, []))
  end
end
