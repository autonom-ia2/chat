import {
  VAZIO,
  camposDaResposta,
  nomeDoFormulario,
  respostaDoFormularioPara,
  rotuloDoCampo,
} from '../formulario/respostaDoFormulario';

const TEXTOS = { sim: 'Sim', nao: 'Não' };

describe('rotuloDoCampo (#1702)', () => {
  it('chave do construtor da Meta perde o screen_<n>_ e o _<n>', () => {
    expect(rotuloDoCampo('screen_0_Nome_completo_0')).toBe('Nome completo');
    expect(rotuloDoCampo('screen_12_Email_3')).toBe('Email');
  });

  it('snake, kebab e camelCase viram palavras com a primeira maiúscula', () => {
    expect(rotuloDoCampo('data_ida')).toBe('Data ida');
    expect(rotuloDoCampo('tipo-de-seguro')).toBe('Tipo de seguro');
    expect(rotuloDoCampo('numeroDePassageiros')).toBe('Numero de passageiros');
  });

  it('chave que só parece do construtor fica como está', () => {
    expect(rotuloDoCampo('screen_name')).toBe('Screen name');
    expect(rotuloDoCampo('screen_0')).toBe('Screen 0');
  });
});

describe('camposDaResposta (#1702)', () => {
  it('lista rótulo e valor legíveis, sem o flow_token', () => {
    const campos = camposDaResposta(
      {
        flow_token: 'segredo',
        destino: 'São Paulo',
        passageiros: 2,
        aceitou_termos: true,
        newsletter: false,
      },
      TEXTOS
    );
    expect(campos).toEqual([
      { chave: 'destino', rotulo: 'Destino', valor: 'São Paulo' },
      { chave: 'passageiros', rotulo: 'Passageiros', valor: '2' },
      { chave: 'aceitou_termos', rotulo: 'Aceitou termos', valor: 'Sim' },
      { chave: 'newsletter', rotulo: 'Newsletter', valor: 'Não' },
    ]);
  });

  it('sem JSON cru: lista vira vírgulas, objeto vira "rótulo: valor", vazio vira traço', () => {
    const campos = camposDaResposta(
      {
        horarios: ['manha', 'tarde'],
        agendamento: { dia: 'Segunda', turno: 'manha' },
        observacao: '',
        nada: null,
      },
      TEXTOS
    );
    expect(campos.map(campo => campo.valor)).toEqual([
      'manha, tarde',
      'Dia: Segunda · Turno: manha',
      VAZIO,
      VAZIO,
    ]);
    expect(campos.map(campo => campo.valor).join(' ')).not.toContain('{');
  });

  it('valor de escolha do construtor perde o id da frente; arquivo mostra só o nome', () => {
    const campos = camposDaResposta(
      {
        screen_0_Plano_1: '0_Plano_Ouro',
        screen_0_Extras_2: ['1_Guincho', '2_Carro_reserva'],
        screen_1_Documento_0: [
          { file_name: 'cnh.pdf', media_id: '123', cdn_url: 'https://x' },
        ],
        codigo: '0_mantido',
      },
      TEXTOS
    );
    expect(campos).toEqual([
      { chave: 'screen_0_Plano_1', rotulo: 'Plano', valor: 'Plano Ouro' },
      {
        chave: 'screen_0_Extras_2',
        rotulo: 'Extras',
        valor: 'Guincho, Carro reserva',
      },
      { chave: 'screen_1_Documento_0', rotulo: 'Documento', valor: 'cnh.pdf' },
      { chave: 'codigo', rotulo: 'Codigo', valor: '0_mantido' },
    ]);
  });

  it('resposta que não é objeto (a Meta mandou texto ilegível) devolve null', () => {
    expect(camposDaResposta('{quebrado', TEXTOS)).toBeNull();
    expect(camposDaResposta(['a'], TEXTOS)).toBeNull();
    expect(camposDaResposta(undefined, TEXTOS)).toBeNull();
  });

  it('só com o token: nenhum campo', () => {
    expect(camposDaResposta({ flow_token: 'x' }, TEXTOS)).toEqual([]);
  });
});

describe('respostaDoFormularioPara (#1702)', () => {
  const resposta = (id, inReplyTo) => ({
    id,
    message_type: 0,
    content_attributes: {
      in_reply_to: inReplyTo,
      whatsapp_flow_response: { name: 'flow', body: 'Sent' },
    },
  });

  it('acha a resposta mais recente que cita o formulário', () => {
    const mensagens = [
      resposta(10, 5),
      { id: 11, message_type: 0, content_attributes: { in_reply_to: 5 } },
      resposta(12, 5),
      resposta(13, 6),
    ];
    expect(respostaDoFormularioPara(5, mensagens).id).toBe(12);
  });

  it('ignora mensagem enviada e responde null sem nada carregado', () => {
    const enviada = { ...resposta(20, 5), message_type: 1 };
    expect(respostaDoFormularioPara(5, [enviada])).toBeNull();
    expect(respostaDoFormularioPara(5, undefined)).toBeNull();
  });
});

describe('nomeDoFormulario (#1702)', () => {
  it('lê o nome do formulário citado, em camelCase ou snake_case', () => {
    expect(
      nomeDoFormulario({
        contentAttributes: {
          rich_message: { type: 'flow', name: ' Cotação ' },
        },
      })
    ).toBe('Cotação');
    expect(
      nomeDoFormulario({
        content_attributes: { rich_message: { type: 'flow', name: 'Login' } },
      })
    ).toBe('Login');
  });

  it('citação que não é formulário ou sem nome: vazio', () => {
    expect(nomeDoFormulario(null)).toBe('');
    expect(
      nomeDoFormulario({
        contentAttributes: { richMessage: { type: 'options', name: 'x' } },
      })
    ).toBe('');
    expect(
      nomeDoFormulario({ contentAttributes: { richMessage: { type: 'flow' } } })
    ).toBe('');
  });
});
