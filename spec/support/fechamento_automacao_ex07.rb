# As receitas do exemplo 7 ("Black Friday para os clientes antigos primeiro"), como a Vanessa montaria pela tela, e os
# modelos aprovados da caixa. O spec (spec/fechamento/automacao/exemplo_07_black_friday_spec.rb) liga as quatro e anda o
# relógio; aqui só fica a montagem, para o spec caber no tamanho de sempre.
module FechamentoAutomacao::Exemplo07
  JA_COMPROU = 'já_comprou'.freeze
  PERGUNTOU = 'perguntou_na_black'.freeze
  NAO_ENVIAR = 'não_enviar_campanha'.freeze
  COMPROU_NA_BLACK = 'comprou_na_black_2026'.freeze
  ETIQUETAS = { JA_COMPROU => 'Já comprou na loja', PERGUNTOU => 'Perguntou na Black', NAO_ENVIAR => 'Não enviar campanha',
                COMPROU_NA_BLACK => 'Comprou na Black 2026' }.freeze
  PECA = %w[peca cor tamanho].freeze
  # Os campos da peça existem no card (onde a vendedora lê) e na conversa (onde o extrair grava).
  MODELOS_DE_ATRIBUTO = %w[card_attribute conversation_attribute].freeze
  MODELOS = { 'pre_black' => 'Oi! A Black começa {{1}}. Quem já comprou com a gente vê antes.',
              'ultimas_horas' => 'Últimas horas da Black! {{1}}' }.freeze

  module_function

  def modelos
    MODELOS.map do |nome, texto|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  def etiqueta_id(account, nome) = account.labels.find_by!(title: nome).id

  # `modelo`: o nome do modelo aprovado e o texto fixo da variável dele.
  def campanha(id, caixa, titulo, modelo, **publico)
    nome, variavel = modelo
    { id: id, tipo: 'campanha', faz: 'disparar', titulo: titulo, caixa_id: caixa.id,
      modelo: { nome: nome, idioma: 'pt_BR', variaveis: [[variavel]] }, **publico }
  end

  # Passos 1 e 2: quinta às 9h a Pré-Black para quem já comprou; 23 horas depois (sexta às 8h), a mesma campanha para
  # todos os outros contatos (G37: todos, menos quem tem a etiqueta "já comprou").
  def pre_black(account, caixa)
    ja_comprou = [etiqueta_id(account, JA_COMPROU)]
    { gatilho: { tipo: 'conta.recorrente', frequencia: 'uma_vez', data: '2026-11-26', hora: 9 }, passos: [
      campanha('ja_compraram', caixa, 'Pré-Black', %w[pre_black amanhã], etiquetas: ja_comprou),
      { id: 'ate_sexta_8h', tipo: 'esperar', duracao: { valor: 23, unidade: 'horas' } },
      campanha('todos_os_outros', caixa, 'Pré-Black', %w[pre_black hoje], publico: 'todos', sem_etiquetas: ja_comprou)
    ] }
  end

  # Passos 3 a 6: cada resposta à Pré-Black (G38) passa pela IA, que decide.
  def resposta(bia)
    filtros = [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' },
               { campo: { '$valor' => 'mensagem.campanha' }, op: 'igual', valor: 'Pré-Black' }]
    { gatilho: { tipo: 'mensagem.criada', filtros: filtros }, passos: [
      { id: 'o_que_quer', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que o cliente respondeu à promoção da Black Friday?',
        caminhos: [
          { nome: 'Quer comprar', chave: 'quer_comprar', descricao: 'quer comprar uma peça', passos: quer_comprar },
          { nome: 'Só dúvida', chave: 'so_duvida', descricao: 'só tem uma dúvida (preço, tamanho, entrega)',
            passos: [etiquetas_no_contato('perguntou', 'Pôr perguntou na Black', [PERGUNTOU]),
                     { id: 'bia', tipo: 'ia_assumir', agente_id: bia.id }] },
          { nome: 'Não quer receber', chave: 'nao_quer_receber', descricao: 'pede para não receber mais promoções',
            passos: nao_quer_receber }
        ],
        nenhum: [] }
    ] }
  end

  # Passo 4: o extrair grava na conversa (o destino que ele aceita), e o "em outro registro" no card aberto do contato (o
  # que a IA de assunto criou) copia campo a campo, lendo a conversa da mãe (G65). Uma ação por campo: valor vazio pula
  # a ação inteira.
  def quer_comprar
    campos = [{ chave: 'peca', descricao: 'a peça que o cliente quer', destino: 'conversa.atributos.peca' },
              { chave: 'cor', descricao: 'a cor da peça', destino: 'conversa.atributos.cor' },
              { chave: 'tamanho', descricao: 'o tamanho da peça', destino: 'conversa.atributos.tamanho' }]
    [{ id: 'peca_cor_tamanho', tipo: 'extrair', le: %w[mensagens_recentes], campos: campos },
     { id: 'no_card', tipo: 'em_outro_registro', registro: { de: 'cards_do_contato', situacao: ['open'], mais_recente: true },
       passos: PECA.map { |chave| para_o_card(chave) } }]
  end

  def para_o_card(chave)
    { id: "#{chave}_no_card", tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: "Gravar #{chave} no card",
      caminho: { id: { '$valor' => 'card.id' } },
      corpo: { card: { custom_attributes: { chave => { '$valor' => "origem.conversa.atributos.#{chave}" } } } } }
  end

  # Passo 6: confirma, põe a etiqueta e marca o contato como "não recebe" (a recusa de todas as campanhas).
  def nao_quer_receber
    [{ id: 'confirma', tipo: 'mensagem', texto: ['Pronto, você não recebe mais promoções'] },
     etiquetas_no_contato('nao_enviar', 'Pôr não enviar campanha', [NAO_ENVIAR]),
     { id: 'sai_das_campanhas', tipo: 'campanha', faz: 'nao_receber' }]
  end

  # Passo 7: domingo às 18h, "Últimas horas" para quem perguntou e não comprou.
  def ultimas_horas(account, caixa)
    { gatilho: { tipo: 'conta.recorrente', frequencia: 'uma_vez', data: '2026-11-29', hora: 18 }, passos: [
      campanha('ultimas_horas', caixa, 'Últimas horas', ['ultimas_horas', 'Corre que acaba hoje.'],
               etiquetas: [etiqueta_id(account, PERGUNTOU)], sem_etiquetas: [etiqueta_id(account, COMPROU_NA_BLACK)])
    ] }
  end

  # Passo 8: card ganho põe "comprou na Black 2026" e "já comprou" no contato.
  def card_ganho(funil)
    { gatilho: { tipo: 'card.ganho', funil_id: funil.id },
      passos: [etiquetas_no_contato('comprou', 'Pôr comprou na Black e já comprou', [COMPROU_NA_BLACK, JA_COMPROU])] }
  end

  def etiquetas_no_contato(id, descricao, nomes)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: descricao,
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: nomes } }
  end
end
