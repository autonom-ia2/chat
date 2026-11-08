# #1428 (tema 6, t6d) — os 21 casos da avaliação paga das perguntas de prova, carregados só pelo
# prova_do_ajuste_eval_spec.rb (require_relative): 10 ramos de negócio, cada um com um agente fictício (sem dado de cliente), e em cada
# caso o pedido de mudança do dono e o CRITÉRIO de "a prova obedece": o que as mensagens de cliente escritas pelo
# Construtor precisam provocar para mostrar a mudança. Quem lê o critério é o juiz do eval (um modelo), nunca uma lista
# de palavras.
module AvaliacaoDaProvaDoAjuste
  # O que todo agente do eval tem igual (o resto vem de AGENTES).
  TOM = 'cordial e breve'.freeze
  MENSAGEM_FIXA = 'Vou confirmar com a equipe e te retorno.'.freeze
  REGRA_DE_PASSAGEM = 'Passe para a equipe quando o cliente pedir.'.freeze

  # A base da academia: fatos que estão SÓ nela, em nenhum campo do agente (revisão 2 do t6d, MÉDIO 2).
  BASE_DA_ACADEMIA = ['A Academia Ritmo tem estacionamento gratuito para alunos, com 40 vagas, na Rua das Palmeiras, 120.',
                      'Aos sábados às 9h tem aulão de spinning aberto a alunos de qualquer plano.'].freeze

  # Um agente por ramo: o que o Construtor recebe como o agente de hoje.
  AGENTES = {
    corretora: {
      name: 'Hubber', instruction: 'Você é o Hubber, assistente da Hub2You, uma corretora de seguros. Atenda pelo WhatsApp com ' \
                                   'cordialidade e seja breve. Explique os tipos de seguro (auto, residencial e vida) e colete ' \
                                   'nome, cidade e o seguro de interesse. Quando o cliente pedir para falar com uma pessoa, ' \
                                   'passe para a equipe. Nunca invente valores, coberturas ou prazos.',
      greeting: 'Oi! Aqui é o Hubber, da Hub2You.', guardrails: ['Nunca invente valores, coberturas ou prazos.']
    },
    clinica: {
      name: 'Clara', instruction: 'Você é a Clara, da Clínica Sorriso Pleno, uma clínica odontológica. Tire dúvidas sobre os ' \
                                  'tratamentos (limpeza, clareamento, canal, implante e aparelho), informe que a avaliação ' \
                                  'inicial é presencial e ajude o paciente a pedir um horário, coletando nome e o melhor período.',
      greeting: 'Olá! Sou a Clara, da Clínica Sorriso Pleno.', guardrails: ['Não informe valores de tratamento.']
    },
    loja: {
      name: 'Lu', instruction: 'Você é a Lu, da Vila Moda, uma loja de roupas femininas que vende pelo site e pelo WhatsApp. ' \
                               'Ajude com tamanhos, cores, prazos de entrega e formas de pagamento (Pix, cartão em até 6x). ' \
                               'Use uma linguagem leve e simpática, com emojis.',
      greeting: 'Oi, tudo bem? 💕 Aqui é a Lu, da Vila Moda!', guardrails: ['Não prometa prazo de entrega exato.']
    },
    imobiliaria: {
      name: 'Teo', instruction: 'Você é o Teo, da Casa Certa Imóveis. Atenda quem quer comprar ou alugar casas e apartamentos ' \
                                'na cidade. Tire dúvidas sobre os imóveis anunciados, documentação e como funciona a visita, ' \
                                'e ajude a marcar uma visita com um corretor.',
      greeting: 'Olá! Aqui é o Teo, da Casa Certa Imóveis.', guardrails: ['Não garanta aprovação de financiamento.']
    },
    restaurante: {
      name: 'Nina', instruction: 'Você é a Nina, do Cantina da Praça, um restaurante italiano com delivery. Mostre o cardápio ' \
                                 '(massas, pizzas e sobremesas), ajude a montar o pedido e informe a taxa de entrega por bairro ' \
                                 'quando o cliente perguntar.',
      greeting: 'Buona sera! Aqui é a Nina, do Cantina da Praça.', guardrails: ['Não invente pratos que não estão no cardápio.']
    },
    academia: {
      name: 'Max', instruction: 'Você é o Max, da Academia Ritmo. Explique as modalidades (musculação, funcional, spinning e ' \
                                'pilates), os horários de funcionamento (segunda a sexta das 6h às 22h, sábado das 8h às 14h) ' \
                                'e os planos mensal, trimestral e anual. Colete nome e objetivo de quem quer se matricular.',
      greeting: 'Fala! Aqui é o Max, da Academia Ritmo.', guardrails: ['Não passe orientação de dieta ou de suplemento.']
    },
    escola: {
      name: 'Bia', instruction: 'Você é a Bia, da Fala Mundo Idiomas, uma escola de inglês e espanhol. Explique as turmas ' \
                                '(presencial e online), os níveis, a duração dos cursos e como funciona o teste de nivelamento. ' \
                                'Trate o aluno com cordialidade e formalidade.',
      greeting: 'Olá, seja bem-vindo à Fala Mundo Idiomas.', guardrails: ['Não informe preços de mensalidade.']
    },
    oficina: {
      name: 'Zeca', instruction: 'Você é o Zeca, da Auto Center Boa Viagem, uma oficina mecânica. Tire dúvidas sobre revisão, ' \
                                 'freios, suspensão, troca de óleo e alinhamento, e ajude o cliente a agendar um horário, ' \
                                 'coletando modelo e ano do carro.',
      greeting: 'Opa! Aqui é o Zeca, da Auto Center Boa Viagem.', guardrails: ['Não diagnostique defeito sem ver o carro.']
    },
    pet: {
      name: 'Mel', instruction: 'Você é a Mel, do Pet Amigo, um pet shop com clínica veterinária. Ajude a agendar banho e tosa, ' \
                                'consultas e vacinas, e tire dúvidas sobre os serviços e os horários (segunda a sábado, das 8h ' \
                                'às 19h).',
      greeting: 'Oi! Aqui é a Mel, do Pet Amigo. 🐾', guardrails: ['Não indique remédio para o animal.']
    },
    salao: {
      name: 'Duda', instruction: 'Você é a Duda, do Studio Bella, um salão de beleza. Explique os serviços (corte, coloração, ' \
                                 'escova, manicure e design de sobrancelha) e ajude a cliente a marcar um horário com a ' \
                                 'profissional disponível.',
      greeting: 'Oi, linda! Aqui é a Duda, do Studio Bella.', guardrails: ['Não informe preço sem saber o tamanho do cabelo.']
    }
  }.freeze

  # `obedece`: o critério da cena para as mensagens de cliente. `extra`: uma pergunta fora da mudança acrescentada à prova
  # (não pode virar ✓ no placar). `base` (revisão do t6d, ALTO 1): o agente tem base de conhecimento ligada, com estes
  # trechos (embedding de verdade); a prova busca nela e o juiz recebe os trechos que a resposta usou. Forense do t6d
  # (M3): tom e tratamento pedem mensagem que não traga a forma pronta, e pedido de tamanho pede uma mensagem que
  # puxaria resposta longa. `forma_pode_nao_aparecer` (série 3 anulada, decisão do Rodrigo de 22/10): o caso aprova
  # quando alguma resposta mostra a forma e o juiz dá ✓, ou quando nenhuma mostra, nada é testado e toda mensagem
  # declarou um pedido da lista; reprova quando o juiz dá ✓ numa resposta que não mostra a forma (o juiz do eval
  # confere cada teste pela régua de produção). O critério das mensagens (`obedece`) é sempre exigido.
  CASOS = [
    { nome: 'prova_duas_frases_e_preco', agente: :corretora,
      fala: 'Responda em no máximo 2 frases e preço passa para a equipe.',
      obedece: 'Ao menos uma mensagem pede preço ou valor de um seguro; ao menos uma pede algo que puxaria uma resposta ' \
               'longa; as mensagens, juntas, deixam ver se o agente responde em no máximo 2 frases.' },
    { nome: 'prova_tom_formal', agente: :corretora, fala: 'Deixe o tom mais formal, trate o cliente por senhor ou senhora.',
      obedece: 'Mensagens comuns de cliente que façam o agente responder com frases dirigidas ao cliente, onde se veja o ' \
               'tratamento por senhor ou senhora; a mensagem do cliente não traz o tratamento pronto (não se apresenta ' \
               'como senhor ou senhora).' },
    { nome: 'prova_sem_seguro_viagem', agente: :corretora,
      fala: 'Quando perguntarem de seguro viagem, diga que a Hub2You não trabalha com esse tipo e ofereça os que temos.',
      obedece: 'Ao menos uma mensagem pergunta sobre seguro viagem.' },
    { nome: 'prova_pergunta_fora_da_mudanca', agente: :corretora, fala: 'Quando perguntarem preço, passe para a equipe.',
      extra: 'Vocês atendem em Curitiba?', obedece: 'Ao menos uma mensagem pergunta preço ou valor de um seguro.' },
    { nome: 'clinica_dor_forte_equipe', agente: :clinica,
      fala: 'Quando o paciente falar de dor forte, inchaço ou dente quebrado, passe na hora para a equipe.',
      obedece: 'Ao menos uma mensagem relata dor forte, inchaço ou dente quebrado.' },
    { nome: 'clinica_sem_diagnostico', agente: :clinica,
      fala: 'Nunca diga o que o paciente tem nem indique remédio. Oriente a marcar uma avaliação.',
      obedece: 'Ao menos uma mensagem descreve um sintoma e pede o que pode ser ou que remédio tomar.' },
    { nome: 'loja_sem_emoji_curto', agente: :loja, fala: 'Pare de usar emoji e responda de forma mais curta.',
      obedece: 'Mensagens comuns de cliente da loja cuja resposta deixe ver se há emoji e se ela ficou curta; ao menos uma ' \
               'pede algo que puxaria uma resposta longa.' },
    { nome: 'loja_troca_30_dias', agente: :loja,
      fala: 'Explique que a primeira troca é grátis em até 30 dias depois de receber o pedido.',
      obedece: 'Ao menos uma mensagem pergunta sobre troca, devolução ou o que fazer quando a peça não serviu.' },
    { nome: 'loja_numero_do_pedido', agente: :loja,
      fala: 'Quando reclamarem de entrega atrasada, peça o número do pedido antes de qualquer coisa.',
      obedece: 'Ao menos uma mensagem reclama de entrega atrasada ou de pedido que não chegou.' },
    { nome: 'imob_comprar_ou_alugar', agente: :imobiliaria,
      fala: 'Antes de marcar visita, pergunte se a pessoa quer comprar ou alugar e em qual bairro procura.',
      obedece: 'Ao menos uma mensagem pede para marcar visita ou conhecer um imóvel, sem já dizer se quer comprar ou alugar.' },
    { nome: 'imob_sem_desconto', agente: :imobiliaria,
      fala: 'Não negocie desconto no aluguel. Diga que quem negocia é o corretor e passe para a equipe.',
      obedece: 'Ao menos uma mensagem pede desconto ou tenta negociar o valor do aluguel.' },
    { nome: 'rest_cozinha_22h', agente: :restaurante,
      fala: 'Avise que a cozinha fecha às 22h e que não aceitamos pedido depois desse horário.',
      obedece: 'Ao menos uma mensagem pergunta até que horas dá para pedir ou tenta pedir tarde da noite.' },
    { nome: 'rest_alergia_equipe', agente: :restaurante,
      fala: 'Se o cliente falar de alergia, passe para a equipe e não garanta nada sobre os ingredientes.',
      obedece: 'Ao menos uma mensagem fala de alergia ou intolerância a algum ingrediente.' },
    { nome: 'academia_aula_experimental', agente: :academia,
      fala: 'Sempre ofereça uma aula experimental grátis quando perguntarem sobre os planos.',
      obedece: 'Ao menos uma mensagem pergunta sobre os planos ou como se matricular.' },
    { nome: 'academia_base_estacionamento', agente: :academia,
      base: BASE_DA_ACADEMIA, fala: 'Quando perguntarem do estacionamento, responda e convide para o aulão de sábado.',
      obedece: 'Ao menos uma mensagem pergunta sobre estacionamento ou onde parar o carro, e a resposta a ela mostra o ' \
               'pedido com ao menos um fato que está só na base de conhecimento: o estacionamento gratuito para ' \
               'alunos ou o aulão de spinning de sábado. O horário do aulão não é exigido: o pedido do dono não pede.' },
    { nome: 'academia_cancelamento_equipe', agente: :academia, fala: 'Pedido de cancelamento de plano vai direto para a equipe.',
      obedece: 'Ao menos uma mensagem pede para cancelar o plano.' },
    { nome: 'escola_tom_descontraido', agente: :escola, forma_pode_nao_aparecer: true,
      fala: 'Use um tom mais descontraído, tratando o aluno por você, como um professor jovem.',
      obedece: 'Julgue as MENSAGENS: são mensagens comuns de aluno que puxam respostas dirigidas ao aluno, em que o tom ' \
               'descontraído e o tratamento por você caberiam. A forma não precisa ter aparecido na resposta.' },
    { nome: 'escola_sem_prometer_fluencia', agente: :escola, fala: 'Nunca prometa fluência em prazo nenhum.',
      obedece: 'Ao menos uma mensagem pergunta em quanto tempo vai ficar fluente.' },
    { nome: 'oficina_sem_orcamento', agente: :oficina,
      fala: 'Não passe orçamento pelo WhatsApp. Diga que precisa ver o carro e ofereça agendar uma avaliação.',
      obedece: 'Ao menos uma mensagem pede orçamento ou quanto custa um serviço.' },
    { nome: 'pet_fallback_veterinaria', agente: :pet,
      fala: 'Quando não souber responder, diga que vai confirmar com a veterinária e volta em até 1 hora.',
      obedece: 'Ao menos uma mensagem pergunta algo que o agente não tem como saber pelo que conhece do pet shop.' },
    { nome: 'salao_tres_frases_e_nome', agente: :salao,
      fala: 'Responda em no máximo 3 frases e sempre pergunte o nome da cliente se ela ainda não disse.',
      obedece: 'Ao menos uma mensagem vem de cliente que ainda não disse o nome; ao menos uma pede algo que puxaria uma ' \
               'resposta longa; as mensagens, juntas, deixam ver se o agente responde em no máximo 3 frases.' }
  ].freeze
end
