# #1428 (tema 6, t6d) — os controles da avaliação paga das perguntas de prova, carregados só pelo
# prova_do_ajuste_eval_spec.rb (require_relative), depois dos casos (usam MENSAGEM_FIXA e BASE_DA_ACADEMIA).
module AvaliacaoDaProvaDoAjuste
  # Forense do t6d (M2): os controles chamam SÓ o juiz de produção (JuizDaProva#julgar), com pedidos e respostas fixos,
  # REPETICOES_DO_CONTROLE vezes cada. Fora dos 21. `espera`, pelas posições na lista de pedidos (a partir de 0): `nao`
  # e `ok`, o veredito que o pedido leva em algum teste; `sem_nao`, o pedido nunca leva nao (fica fora dos testes ou
  # dá ok); `sem_ok`, o pedido nunca leva ok (fica fora dos testes ou dá nao); `presentes` e `ausentes`, se o pedido
  # aparece em algum teste. Os dois controles da base (revisão 2, MÉDIO 2) têm a mesma resposta, com um fato que só
  # existe na base: com os trechos usados, o fato é sabido; sem eles, o agente respondeu o que não sabia em vez de passar
  # para a equipe.
  CONTROLES = [
    { nome: 'controle_emoji', agente: :loja, pedidos: ['Responda de forma curta', 'Não use emoji'],
      itens: [{ 'pergunta' => 'Quais formas de pagamento vocês aceitam?', 'resposta' => 'Aceitamos Pix e cartão em até 6x 😊',
                'equipe' => false }],
      espera: { nao: [1] } },
    { nome: 'controle_preco', agente: :corretora, pedidos: ['Responda de forma curta', 'Preço passa para a equipe'],
      itens: [{ 'pergunta' => 'Quais seguros vocês têm?', 'resposta' => 'Trabalhamos com seguro auto, residencial e de vida.',
                'equipe' => false },
              { 'pergunta' => 'Vocês atendem em Curitiba?', 'resposta' => 'Sim, atendemos Curitiba e toda a região.',
                'equipe' => false }],
      espera: { presentes: [0], ausentes: [1] } },
    { nome: 'controle_gatilho', agente: :corretora, pedidos: ['Quando não souber responder, passe a conversa para a equipe'],
      itens: [{ 'pergunta' => 'Minha apólice 4471 já foi emitida?', 'resposta' => MENSAGEM_FIXA, 'equipe' => true }],
      espera: { ok: [0] } },
    # Revisão do 8d379379b7: tratamento. Com a forma oposta ("você" quando o pedido é "senhora"), nao. Sem nenhuma das
    # duas, o pedido não pode levar ok (fora dos testes ou nao passam).
    { nome: 'controle_tratamento_oposto', agente: :loja, pedidos: ['Trate a cliente por senhora'],
      itens: [{ 'pergunta' => 'Vocês têm esse vestido no tamanho M?', 'equipe' => false,
                'resposta' => 'Temos sim! Você quer que eu separe um para você?' }],
      espera: { nao: [0] } },
    { nome: 'controle_tratamento_neutro', agente: :loja, pedidos: ['Trate a cliente por senhora'],
      itens: [{ 'pergunta' => 'Vocês têm esse vestido no tamanho M?', 'equipe' => false, 'resposta' => 'Temos sim, tudo bem?' }],
      espera: { sem_ok: [0] } },
    { nome: 'controle_base_com_trechos', agente: :academia,
      pedidos: ['Quando não souber responder, passe a conversa para a equipe'],
      itens: [{ 'pergunta' => 'Vocês têm estacionamento?', 'equipe' => false, 'trechos' => [BASE_DA_ACADEMIA.first],
                'resposta' => 'Temos sim: estacionamento gratuito para alunos, com 40 vagas, na Rua das Palmeiras, 120.' }],
      espera: { sem_nao: [0] } },
    { nome: 'controle_base_sem_trechos', agente: :academia,
      pedidos: ['Quando não souber responder, passe a conversa para a equipe'],
      itens: [{ 'pergunta' => 'Vocês têm estacionamento?', 'equipe' => false,
                'resposta' => 'Temos sim: estacionamento gratuito para alunos, com 40 vagas, na Rua das Palmeiras, 120.' }],
      espera: { nao: [0] } }
  ].freeze
end
