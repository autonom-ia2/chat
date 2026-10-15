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
# Cada finalidade mora no seu arquivo em `finalidades/` (a cobrança em `finalidades/cobranca.rb`), com a constante
# `FINALIDADES`; o `CATALOGO` junta todas. Finalidade nova = arquivo novo, sem tocar aqui.
module Whatsapp::Templates::Finalidades
  # Finalidade ou variante que não existe: erro de quem chama.
  class Desconhecida < ArgumentError; end
  # Botão com a base do ambiente e a base vazia (FRONTEND_URL sem valor): configuração, não catálogo.
  class SemBase < StandardError; end

  Pronto = Data.define(:finalidade, :nome, :nome_amigavel, :dono, :idioma, :texto, :campos, :botoes) do
    # O pedido de criação no formato da Meta (o mesmo que a tela de Modelos manda ao `MetaClient`).
    def corpo
      exemplos = campos.values.map { |campo| Whatsapp::Templates::Finalidades.exemplo(campo) }
      components = [{ type: 'BODY', text: texto, example: { body_text: [exemplos] } }]
      components << { type: 'BUTTONS', buttons: botoes_da_meta } if botoes.any?
      { name: nome, language: idioma, category: Whatsapp::Templates::Finalidades::CATEGORIA, components: components }
    end

    # Os botões no formato da Meta, com a URL na base deste ambiente: o que vai na criação e o que o aprovado precisa ter.
    def botoes_da_meta
      botoes.map { |botao| botao_da_meta(botao) }
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

      endereco = Whatsapp::Templates::Finalidades.url_de(botao[:url])
      url = { type: 'URL', text: botao[:texto], url: endereco }
      return url unless botao[:campo]

      exemplo = botao[:exemplo] || Whatsapp::Templates::Finalidades.exemplo(botao[:campo])
      url.merge(example: [endereco.split('{{').first + exemplo])
    end
  end

  IDIOMA = 'pt_BR'.freeze
  CATEGORIA = 'UTILITY'.freeze
  # A base de cada link que muda por ambiente (Hub2You, Autonom.ia): no catálogo, `url: { base: :booking_invite,
  # caminho: '/b/{{1}}' }`, nunca o endereço escrito. Resolvida na hora (`url_de`).
  BASES_DE_URL = { booking_invite: -> { Crm::BookingInvite.base_url } }.freeze
  # Um exemplo por campo, que a Meta pede para cada variável (e para o fim variável da URL). Link: base + caminho.
  EXEMPLOS = {
    'cliente.primeiro_nome' => 'Ana', 'negocio.valor' => 'R$ 150,00', 'negocio.titulo' => 'Mensalidade de outubro',
    'negocio.prazo' => '20/10/2026',
    'horario.data_hora' => '14/10 às 15:00', 'horario.data' => '14/10/2026', 'horario.hora' => '15:00',
    'horario.link_gestao' => { base: :booking_invite, caminho: '/b/AB3K9QXZ' }, 'horario.link_codigo' => 'AB3K9QXZ'
  }.freeze

  # finalidade => { dono:, opcoes: [chaves da variante],
  #                 variantes: { [valores das opções] => { nome:, amigavel:, texto:, campos:, botoes: [] } } }
  # Junta o `FINALIDADES` de cada arquivo de `finalidades/`. A mesma finalidade em dois arquivos para a carga.
  CATALOGO = Dir[File.join(__dir__, 'finalidades', '*.rb')].reduce({}) do |catalogo, arquivo|
    proprias = const_get(File.basename(arquivo, '.rb').camelize, false)::FINALIDADES
    repetidas = catalogo.keys & proprias.keys
    raise ArgumentError, "finalidade repetida: #{repetidas.join(', ')}" if repetidas.any?

    catalogo.merge(proprias)
  end.freeze

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

  # O endereço de um botão URL: o texto como está, ou `{ base:, caminho: }` com a base deste ambiente.
  def url_de(url)
    return url unless url.is_a?(Hash)

    base = BASES_DE_URL[url[:base]] || raise(Desconhecida, "base de URL #{url[:base]}")
    endereco = base.call.presence || raise(SemBase, "base de URL #{url[:base]} vazia")
    "#{endereco}#{url[:caminho]}"
  end

  def exemplo(campo)
    url_de(EXEMPLOS.fetch(campo))
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
