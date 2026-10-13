import {
  ETAPA_DESLIGADA,
  ETAPA_IGUAL,
  ETAPA_PROPRIA,
  CENARIO_ONLINE,
  cenaDaPrevia,
  etapasPorModo,
  faltaPessoa,
  filaDoExemplo,
  jeitoDaRegra,
  juntarNomes,
  minutosDe,
  modoDaEtapa,
  podeFicarSemResposta,
  quemComParteFora,
  quemRecebeNoExemplo,
  regraDaEtapa,
  fraseDaSituacao,
  situacaoDoFunil,
  textoDoJeito,
} from './passagem';

const regra = (campos = {}) => ({
  enabled: true,
  mode: 'round_robin',
  handoff_mode: 'r2_direct',
  trigger: '',
  prefer_online: true,
  pickup_threshold_seconds: 900,
  escalation_user_id: null,
  pool_type: 'inbox',
  pool_id: null,
  escalation_action: 'renotify',
  ...campos,
});
const chaves = passos => passos.map(passo => passo.chave);
const equipe = [
  { id: 1, name: 'Ana Ribeiro' },
  { id: 2, name: 'Bruno Lima' },
  { id: 3, name: 'Carla Souza' },
];

describe('cenaDaPrevia: sábado, equipe fora', () => {
  it('na hora e só online: a conversa fica com o atendimento automático até alguém assumir', () => {
    const passos = cenaDaPrevia({ regra: regra(), recebe: 'Bruno' });
    expect(chaves(passos)).toEqual([
      'SABADO',
      'CLIENTE_PEDE',
      'ROBO_AVISA',
      'NINGUEM_ONLINE',
      'CLIENTE_DUVIDA',
      'ROBO_RESPONDE',
      'SEGUNDA',
      'ENTREGUE',
      'ASSUMIU',
    ]);
    expect(passos.find(passo => passo.chave === 'ENTREGUE').nome).toBe('Bruno');
  });

  it('na hora para quem está fora (regra antiga): o atendimento automático para e a cliente fica sem resposta', () => {
    const passos = cenaDaPrevia({
      regra: regra({ prefer_online: false }),
      recebe: 'Bruno',
    });
    expect(chaves(passos)).toEqual([
      'SABADO',
      'CLIENTE_PEDE',
      'FOI_PARA_QUEM_ESTA_FORA',
      'ROBO_PARA',
      'CLIENTE_DUVIDA',
      'SEM_RESPOSTA',
    ]);
    expect(chaves(passos)).not.toContain('ROBO_RESPONDE');
  });

  it('com convite e avisar de novo: o convite sai mesmo com todos fora e o atendimento automático segue', () => {
    const passos = cenaDaPrevia({
      regra: regra({
        handoff_mode: 'r3_invite',
        pickup_threshold_seconds: 600,
      }),
      recebe: 'Carla',
    });
    expect(chaves(passos)).toEqual([
      'SABADO',
      'CLIENTE_PEDE',
      'ROBO_AVISA',
      'CONVITE_FORA',
      'CLIENTE_DUVIDA',
      'ROBO_RESPONDE',
      'ESPERA_AVISA',
      'CONVITE_VENCE',
      'SABADO_TARDE',
      'ACEITOU',
      'ASSUMIU',
    ]);
    expect(passos.find(passo => passo.chave === 'ESPERA_AVISA')).toMatchObject({
      minutos: 10,
      nome: 'Carla',
    });
  });

  it('com convite e passar para outra: espera a outra pessoa ficar online, sem calar o atendimento automático', () => {
    const passos = cenaDaPrevia({
      regra: regra({
        handoff_mode: 'r3_invite',
        escalation_action: 'escalate',
        pickup_threshold_seconds: 600,
      }),
      recebe: 'Carla',
      outra: 'Bruno',
    });
    expect(chaves(passos)).toEqual([
      'SABADO',
      'CLIENTE_PEDE',
      'ROBO_AVISA',
      'CONVITE_FORA',
      'CLIENTE_DUVIDA',
      'ROBO_RESPONDE',
      'ESPERA_PASSA_SEGURA',
      'CONVITE_VENCE',
      'SABADO_TARDE',
      'ENTREGUE_OUTRA',
      'ASSUMIU',
    ]);
    expect(passos.find(passo => passo.chave === 'ENTREGUE_OUTRA').nome).toBe(
      'Bruno'
    );
    expect(chaves(passos)).not.toContain('SEM_RESPOSTA');
    expect(
      passos.find(passo => passo.chave === 'ESPERA_PASSA_SEGURA')
    ).toMatchObject({
      minutos: 10,
      nome: 'Bruno',
      convidada: 'Carla',
    });
  });

  it('a prévia muda quando o liga/desliga antigo de online muda, nos dois modos', () => {
    const convite = {
      handoff_mode: 'r3_invite',
      escalation_action: 'escalate',
    };
    const ligado = chaves(
      cenaDaPrevia({ regra: regra(convite), recebe: 'Carla', outra: 'Bruno' })
    );
    const desligado = chaves(
      cenaDaPrevia({
        regra: regra({ ...convite, prefer_online: false }),
        recebe: 'Carla',
        outra: 'Bruno',
      })
    );
    expect(ligado).not.toEqual(desligado);
    expect(desligado).toContain('SEM_RESPOSTA');
  });

  it('funil desligado ou sem caixa: mostra que a equipe não é chamada ou que nada chega', () => {
    expect(
      chaves(cenaDaPrevia({ regra: regra(), recebe: 'Bruno', iaLigada: false }))
    ).toEqual(['SABADO', 'CLIENTE_PEDE', 'FUNIL_DESLIGADO', 'FICA_NA_CAIXA']);
    expect(
      chaves(cenaDaPrevia({ regra: regra(), recebe: 'Bruno', semCaixa: true }))
    ).toEqual(['SEM_CAIXA']);
  });

  it('desligada: a equipe não é chamada', () => {
    const passos = cenaDaPrevia({
      regra: regra({ enabled: false }),
      recebe: 'Bruno',
    });
    expect(chaves(passos)).toEqual([
      'SABADO',
      'CLIENTE_PEDE',
      'NAO_CHAMA',
      'ROBO_SEGUE',
    ]);
  });
});

describe('quem recebe no exemplo', () => {
  it('pula a pessoa da equipe com o nome da cliente de exemplo', () => {
    expect(
      quemRecebeNoExemplo({
        regra: regra(),
        equipe,
        todas: equipe,
        cliente: 'Ana',
      })
    ).toBe('Bruno');
    expect(filaDoExemplo(equipe, 'Ana')).toEqual(['Bruno', 'Carla']);
  });

  it('não repete quem recebe o "passar para outra"', () => {
    expect(
      quemRecebeNoExemplo({
        regra: regra(),
        equipe,
        todas: equipe,
        cliente: 'Ana',
        evitar: 'Bruno',
      })
    ).toBe('Carla');
  });

  it('com uma pessoa só, mostra essa pessoa', () => {
    const sempre = regra({ pool_type: 'user', pool_id: 3 });
    expect(
      quemRecebeNoExemplo({
        regra: sempre,
        equipe,
        todas: equipe,
        cliente: 'Ana',
      })
    ).toBe('Carla');
  });
});

describe('podeFicarSemResposta', () => {
  it('só acusa quando a conversa pode ir para quem está fora e calar o atendimento automático', () => {
    expect(podeFicarSemResposta(regra())).toBe(false);
    expect(podeFicarSemResposta(regra({ prefer_online: false }))).toBe(true);
    expect(
      podeFicarSemResposta(regra({ prefer_online: false, enabled: false }))
    ).toBe(false);
    expect(
      podeFicarSemResposta(
        regra({ prefer_online: false, handoff_mode: 'r3_invite' })
      )
    ).toBe(false);
    expect(
      podeFicarSemResposta(
        regra({
          prefer_online: false,
          handoff_mode: 'r3_invite',
          escalation_action: 'escalate',
        })
      )
    ).toBe(true);
  });
});

describe('regras de etapa e validação', () => {
  const etapas = [
    { id: 1, nome: 'Novo', modo: ETAPA_IGUAL, regra: regra() },
    {
      id: 2,
      nome: 'Proposta',
      modo: ETAPA_PROPRIA,
      regra: regra({ handoff_mode: 'r3_invite' }),
    },
    { id: 3, nome: 'Fechado', modo: ETAPA_DESLIGADA, regra: regra() },
  ];

  it('agrupa as etapas pelo que vale nelas', () => {
    const grupos = etapasPorModo(etapas, regra());
    expect(grupos.ligadas.map(etapa => etapa.id)).toEqual([1, 2]);
    expect(grupos.semPassagem.map(etapa => etapa.id)).toEqual([3]);
    expect(
      etapasPorModo(etapas, regra({ enabled: false })).ligadas.map(
        etapa => etapa.id
      )
    ).toEqual([2]);
  });

  it('a etapa desligada não passa, mesmo com o funil ligado', () => {
    expect(regraDaEtapa(etapas[2], regra()).enabled).toBe(false);
    expect(regraDaEtapa(etapas[1], regra({ enabled: false })).enabled).toBe(
      true
    );
  });

  it('acusa a pessoa que falta escolher', () => {
    expect(faltaPessoa(regra({ pool_type: 'user' }))).toBe(true);
    expect(
      faltaPessoa(
        regra({ handoff_mode: 'r3_invite', escalation_action: 'escalate' })
      )
    ).toBe(true);
    expect(faltaPessoa(regra({ enabled: false, pool_type: 'user' }))).toBe(
      false
    );
    expect(faltaPessoa(regra())).toBe(false);
  });

  it('junta nomes com o idioma do painel (pt_BR)', () => {
    expect(juntarNomes(['Novo', 'Fechado'], 'pt_BR')).toBe('Novo e Fechado');
  });

  it('arredonda o tempo de espera em minutos, nunca abaixo de 1', () => {
    expect(minutosDe(regra({ pickup_threshold_seconds: 600 }))).toBe(10);
    expect(minutosDe(regra({ pickup_threshold_seconds: 10 }))).toBe(1);
  });
});

describe('cenaDaPrevia: terça, equipe online', () => {
  const terca = campos =>
    chaves(
      cenaDaPrevia({
        regra: regra(campos),
        recebe: 'Carla',
        cenario: CENARIO_ONLINE,
      })
    );

  it('na hora: vai para quem está online e a assistente para', () => {
    expect(terca()).toEqual([
      'TERCA',
      'CLIENTE_PEDE',
      'ROBO_CHAMA',
      'ENTREGUE_NA_HORA',
      'ASSUMIU',
    ]);
  });

  it('com convite: a assistente segue até a pessoa aceitar', () => {
    expect(terca({ handoff_mode: 'r3_invite' })).toEqual([
      'TERCA',
      'CLIENTE_PEDE',
      'ROBO_AVISA',
      'CONVITE_ONLINE',
      'CLIENTE_DUVIDA',
      'ROBO_RESPONDE',
      'ACEITOU_LOGO',
      'ASSUMIU',
    ]);
  });

  it('regra antiga: não promete que vai para quem está online', () => {
    expect(terca({ prefer_online: false })).toEqual([
      'TERCA',
      'CLIENTE_PEDE',
      'VAI_ONLINE_OU_NAO',
    ]);
    expect(
      terca({ prefer_online: false, handoff_mode: 'r3_invite' })
    ).toContain('CONVITE_ENVIADO');
  });

  it('desligada: o dia muda, a equipe continua sem ser chamada', () => {
    expect(terca({ enabled: false })).toEqual([
      'TERCA',
      'CLIENTE_PEDE',
      'NAO_CHAMA',
      'ROBO_SEGUE',
    ]);
  });
});

describe('quem recebe com parte da equipe fora', () => {
  it('na equipe, pula quem está fora e vai para quem está online', () => {
    expect(
      quemComParteFora({ regra: regra(), fila: ['Bruno', 'Carla'] })
    ).toEqual({ chave: 'EQUIPE_VAI', fora: 'Bruno', online: 'Carla' });
    expect(quemComParteFora({ regra: regra(), fila: ['Bruno'] })).toEqual({
      chave: 'EQUIPE_UMA',
      nome: 'Bruno',
    });
  });

  it('sempre a mesma pessoa: na hora espera por ela; com convite, ela é avisada mesmo fora', () => {
    const sempre = { pool_type: 'user', pool_id: 2 };
    expect(
      quemComParteFora({ regra: regra(sempre), fila: [], pessoa: 'Bruno' })
    ).toEqual({ chave: 'PESSOA_ESPERA', nome: 'Bruno' });
    expect(
      quemComParteFora({
        regra: regra({ ...sempre, handoff_mode: 'r3_invite' }),
        fila: [],
        pessoa: 'Bruno',
      }).chave
    ).toBe('PESSOA_CONVITE');
    expect(
      quemComParteFora({
        regra: regra({ ...sempre, prefer_online: false }),
        fila: [],
        pessoa: 'Bruno',
      }).chave
    ).toBe('PESSOA_FORA');
  });

  it('regra antiga na equipe: não promete quem está online', () => {
    expect(
      quemComParteFora({
        regra: regra({ prefer_online: false }),
        fila: ['Bruno', 'Carla'],
      }).chave
    ).toBe('EQUIPE_ANTIGA');
  });
});

describe('jeito de uma etapa do meu jeito', () => {
  it('diz o jeito em poucas palavras, com a pessoa quando é sempre a mesma', () => {
    expect(jeitoDaRegra(regra(), equipe)).toEqual({ chave: 'NA_HORA_EQUIPE' });
    expect(
      jeitoDaRegra(regra({ pool_type: 'user', pool_id: 2 }), equipe)
    ).toEqual({ chave: 'NA_HORA_PESSOA', nome: 'Bruno Lima' });
    expect(
      jeitoDaRegra(
        regra({ handoff_mode: 'r3_invite', escalation_action: 'escalate' }),
        equipe
      )
    ).toEqual({ chave: 'CONVITE_EQUIPE' });
  });

  it('no quadro usa o primeiro nome; no cartão, o nome inteiro', () => {
    const t = (chave, campos) => `${chave}|${campos.nome}`;
    const sempre = regra({ pool_type: 'user', pool_id: 2 });
    expect(textoDoJeito(t, sempre, equipe)).toBe(
      'CRM_KANBAN.PASSAGEM.JEITO.CURTO.NA_HORA_PESSOA|Bruno'
    );
    expect(textoDoJeito(t, sempre, equipe, 'FRASE')).toBe(
      'CRM_KANBAN.PASSAGEM.JEITO.FRASE.NA_HORA_PESSOA|Bruno Lima'
    );
  });
});

describe('situacaoDoFunil: a frase da lista de funis', () => {
  const etapa = (custom, ligada, modo) => ({
    handoff_custom: custom,
    handoff: { enabled: ligada, ...(modo ? { handoff_mode: modo } : {}) },
  });
  const ajustes = (campos = {}) => ({
    enabled: true,
    handoff: { enabled: true, handoff_mode: 'r2_direct' },
    stages: [etapa(false), etapa(false)],
    ...campos,
  });

  it('funil ligado em todas as etapas: ligada, com o jeito', () => {
    expect(situacaoDoFunil(ajustes())).toEqual({
      estado: 'ligada',
      jeito: 'na_hora',
      total: 2,
    });
    expect(
      situacaoDoFunil(
        ajustes({ handoff: { enabled: true, handoff_mode: 'r3_invite' } })
      ).jeito
    ).toBe('convite');
  });

  it('etapa do seu jeito com outro jeito: ligada, sem dizer um jeito só', () => {
    expect(
      situacaoDoFunil(
        ajustes({ stages: [etapa(false), etapa(true, true, 'r3_invite')] })
      )
    ).toEqual({ estado: 'ligada', jeito: null, total: 2 });
  });

  it('funil ligado sem etapas: ligada, com o jeito do funil', () => {
    expect(situacaoDoFunil(ajustes({ stages: [] }))).toEqual({
      estado: 'ligada',
      jeito: 'na_hora',
      total: 0,
    });
  });

  it('funil desligado com uma etapa do seu jeito: parte, com o jeito dessa etapa', () => {
    const situacao = situacaoDoFunil(
      ajustes({
        handoff: { enabled: false },
        stages: [
          etapa(false),
          etapa(true, true, 'r3_invite'),
          etapa(true, false),
        ],
      })
    );
    expect(situacao).toEqual({
      estado: 'parte',
      ligadas: 1,
      total: 3,
      jeito: 'convite',
    });
  });

  it('funil desligado com todas as etapas do seu jeito: ligada em todas', () => {
    const situacao = situacaoDoFunil(
      ajustes({
        handoff: { enabled: false },
        stages: [
          etapa(true, true, 'r2_direct'),
          etapa(true, true, 'r2_direct'),
        ],
      })
    );
    expect(situacao).toEqual({ estado: 'ligada', jeito: 'na_hora', total: 2 });
  });

  it('funil ligado com uma etapa sem passagem: conta as etapas e diz o jeito', () => {
    const situacao = situacaoDoFunil(
      ajustes({ stages: [etapa(false), etapa(true, false)] })
    );
    expect(situacao).toEqual({
      estado: 'parte',
      ligadas: 1,
      total: 2,
      jeito: 'na_hora',
    });
  });

  it('nenhuma etapa chama: desligada; assistente do funil desligada: diz isso', () => {
    expect(situacaoDoFunil(ajustes({ handoff: { enabled: false } }))).toEqual({
      estado: 'desligada',
    });
    expect(situacaoDoFunil(ajustes({ enabled: false }))).toEqual({
      estado: 'desligada',
      semAssistente: true,
    });
  });

  it('lê o modo da etapa como o servidor manda', () => {
    expect(modoDaEtapa(etapa(false, true))).toBe(ETAPA_IGUAL);
    expect(modoDaEtapa(etapa(true, true))).toBe(ETAPA_PROPRIA);
    expect(modoDaEtapa(etapa(true, false))).toBe(ETAPA_DESLIGADA);
  });
});

describe('fraseDaSituacao: a chave e os números da frase', () => {
  it('ligada em todas, com um jeito; com jeitos diferentes, sem jeito', () => {
    expect(
      fraseDaSituacao({ estado: 'ligada', jeito: 'na_hora', total: 5 })
    ).toEqual({
      chave: 'LIGADA',
      jeito: 'JEITO_NA_HORA',
    });
    expect(
      fraseDaSituacao({ estado: 'ligada', jeito: null, total: 5 }).chave
    ).toBe('LIGADA_MISTO');
  });

  it('funil sem etapas: só o jeito', () => {
    expect(
      fraseDaSituacao({ estado: 'ligada', jeito: 'convite', total: 0 })
    ).toEqual({
      chave: 'LIGADA_SEM_ETAPAS',
      jeito: 'JEITO_CONVITE',
    });
  });

  it('em parte das etapas: "na hora, em 4 de 5 etapas"', () => {
    expect(
      fraseDaSituacao({
        estado: 'parte',
        ligadas: 4,
        total: 5,
        jeito: 'na_hora',
      })
    ).toEqual({ chave: 'PARTE', jeito: 'JEITO_NA_HORA', n: 4, total: 5 });
    expect(
      fraseDaSituacao({ estado: 'parte', ligadas: 2, total: 3, jeito: null })
        .chave
    ).toBe('PARTE_MISTO');
  });

  it('desligada, sem assistente e sem resposta do servidor', () => {
    expect(fraseDaSituacao({ estado: 'desligada' }).chave).toBe('DESLIGADA');
    expect(
      fraseDaSituacao({ estado: 'desligada', semAssistente: true }).chave
    ).toBe('SEM_ASSISTENTE');
    expect(fraseDaSituacao(undefined).chave).toBe('SEM_SITUACAO');
  });
});
