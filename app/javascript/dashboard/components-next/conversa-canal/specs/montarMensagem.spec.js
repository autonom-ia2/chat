import {
  lerCoordenadas,
  montarBotaoDeLink,
  montarContato,
  montarFormulario,
  montarLocalizacao,
  montarOpcoes,
  montarPedidoDeLocalizacao,
  telefoneInternacional,
  textoParaQuemNaoTemFormato,
} from '../mais/montarMensagem';

describe('montarMensagem (#1702)', () => {
  describe('lerCoordenadas', () => {
    it('lê os números que o Google Maps copia', () => {
      expect(lerCoordenadas('-23.5613, -46.6565')).toEqual({
        latitude: -23.5613,
        longitude: -46.6565,
      });
    });

    it('lê o link com @lat,lng', () => {
      expect(
        lerCoordenadas(
          'https://www.google.com/maps/place/Av.+Paulista/@-23.5613,-46.6565,17z/data=x'
        )
      ).toEqual({ latitude: -23.5613, longitude: -46.6565 });
    });

    it('lê o link com ?q=lat,lng', () => {
      expect(lerCoordenadas('https://maps.google.com/?q=-22.9,-43.2')).toEqual({
        latitude: -22.9,
        longitude: -43.2,
      });
    });

    it('lê o link com !3d e !4d', () => {
      expect(
        lerCoordenadas(
          'https://www.google.com/maps/place/X/data=!4m6!3m5!3d-19.92!4d-43.94!16s'
        )
      ).toEqual({ latitude: -19.92, longitude: -43.94 });
    });

    it('no link do lugar, prefere o ponto (!3d!4d) ao centro da tela (@)', () => {
      expect(
        lerCoordenadas(
          'https://www.google.com/maps/place/Loja/@-23.50,-46.60,17z/data=!3m1!4b1!4m6!3m5!3d-23.5613!4d-46.6565!16s'
        )
      ).toEqual({ latitude: -23.5613, longitude: -46.6565 });
    });

    it('recusa texto sem coordenada e número fora do mapa', () => {
      expect(lerCoordenadas('Av. Paulista, 1000')).toBeNull();
      expect(lerCoordenadas('120, 10')).toBeNull();
      expect(lerCoordenadas('https://maps.app.goo.gl/abc')).toBeNull();
    });

    it('recusa número em notação que não é decimal simples', () => {
      expect(lerCoordenadas('1e1, 2')).toBeNull();
      expect(lerCoordenadas('0x10, 2')).toBeNull();
      expect(lerCoordenadas('Infinity, 2')).toBeNull();
      expect(lerCoordenadas('.5, 2')).toBeNull();
    });

    it('não quebra com link de escape inválido', () => {
      expect(lerCoordenadas('https://www.google.com/maps/%E0%A4%A')).toBeNull();
    });
  });

  it('telefone: exige + e o código do país, de 8 a 15 dígitos, sem adivinhar', () => {
    expect(telefoneInternacional('+55 11 98765-4321')).toBe('+5511987654321');
    expect(telefoneInternacional('+1 415 555 0100')).toBe('+14155550100');
    expect(telefoneInternacional('(11) 98765-4321')).toBe('');
    expect(telefoneInternacional('+55 11')).toBe('');
    expect(telefoneInternacional('+1234567890123456')).toBe('');
  });

  it('botão de link monta o rich_message do #1473 e pede o que falta', () => {
    expect(
      montarBotaoDeLink({ mensagem: 'Oi', nomeDoBotao: '', endereco: '' })
    ).toEqual({ erros: { nomeDoBotao: 'nomeDoBotao', endereco: 'endereco' } });
    expect(
      montarBotaoDeLink({
        mensagem: ' Sua proposta ',
        nomeDoBotao: 'Ver proposta',
        endereco: 'https://exemplo.com/p',
      })
    ).toEqual({
      pedido: {
        content: 'Sua proposta',
        richMessage: {
          type: 'link_button',
          label: 'Ver proposta',
          url: 'https://exemplo.com/p',
        },
      },
    });
  });

  it('opções: até 3 viram botões, mais que isso lista com o nome do botão', () => {
    const botoes = montarOpcoes({
      cabecalho: 'Planos',
      mensagem: 'Qual plano?',
      opcoes: ['Básico', 'Completo', ''],
      nomeDaLista: 'Ver opções',
    });
    expect(botoes.pedido.richMessage).toEqual({
      type: 'options',
      header: 'Planos',
      options: [
        { id: 'opcao_1', title: 'Básico' },
        { id: 'opcao_2', title: 'Completo' },
      ],
    });

    const lista = montarOpcoes({
      cabecalho: 'Agenda',
      mensagem: 'Qual dia?',
      opcoes: ['Seg', 'Ter', 'Qua', 'Qui'],
      nomeDaLista: 'Ver dias',
    });
    expect(lista.pedido.richMessage.button).toBe('Ver dias');
    expect(lista.pedido.richMessage.options).toHaveLength(4);

    expect(
      montarOpcoes({ cabecalho: 'C', mensagem: 'x', opcoes: ['só uma'] })
    ).toEqual({
      erros: { opcoes: 'opcoes' },
    });
  });

  it('opções exigem cabeçalho de até 60 letras, nos botões e na lista', () => {
    const semCabecalho = { mensagem: 'Qual dia?', opcoes: ['Seg', 'Ter'] };
    expect(montarOpcoes(semCabecalho).erros).toEqual({
      cabecalho: 'cabecalho',
    });
    expect(
      montarOpcoes({
        ...semCabecalho,
        opcoes: ['Seg', 'Ter', 'Qua', 'Qui'],
        nomeDaLista: 'Ver dias',
        cabecalho: '   ',
      }).erros
    ).toEqual({ cabecalho: 'cabecalho' });
    expect(
      montarOpcoes({ ...semCabecalho, cabecalho: 'x'.repeat(61) }).erros
    ).toEqual({ cabecalho: 'cabecalhoLongo' });
    expect(
      montarOpcoes({ ...semCabecalho, cabecalho: ` ${'x'.repeat(60)} ` }).pedido
        .richMessage.header
    ).toBe('x'.repeat(60));
  });

  it('confere os limites da Meta antes de enviar', () => {
    expect(
      montarBotaoDeLink({
        mensagem: 'Oi',
        nomeDoBotao: 'Um nome de botão comprido',
        endereco: 'ftp://exemplo.com/arquivo',
      }).erros
    ).toEqual({
      nomeDoBotao: 'nomeDoBotaoLongo',
      endereco: 'enderecoInvalido',
    });
    expect(
      montarOpcoes({
        cabecalho: 'C',
        mensagem: 'x',
        opcoes: ['Sim', 'Sim', 'Um título grande demais aqui'],
      }).erros
    ).toEqual({ opcoes: 'opcaoLonga' });
    expect(
      montarOpcoes({ cabecalho: 'C', mensagem: 'x', opcoes: ['Sim', 'Sim'] })
        .erros
    ).toEqual({ opcoes: 'opcoesRepetidas' });
    expect(
      montarOpcoes({
        cabecalho: 'C',
        mensagem: 'x',
        opcoes: ['a', 'b', 'c', 'd'],
        nomeDaLista: 'Um nome de lista comprido',
      }).erros
    ).toEqual({ nomeDaLista: 'nomeDaListaLongo' });
    expect(
      montarLocalizacao({
        coordenadas: '-23.5, -46.6',
        nome: 'x'.repeat(101),
        endereco: 'y'.repeat(301),
      }).erros
    ).toEqual({ nome: 'nomeDoLugarLongo', endereco: 'enderecoDoLugarLongo' });
    expect(
      montarFormulario(
        { formulario: '1', mensagem: 'Oi', textoDoBotao: 'z'.repeat(31) },
        { tela: 'INICIO', token: 't' }
      ).erros
    ).toEqual({ textoDoBotao: 'textoDoBotaoLongo' });
  });

  it('formulário sem tela não monta e o nome vai cortado em 60', () => {
    expect(
      montarFormulario(
        { formulario: '1', mensagem: 'Oi', textoDoBotao: 'Preencher' },
        { tela: '', token: 't' }
      ).erros
    ).toEqual({ formulario: 'formulario' });
    const { pedido } = montarFormulario(
      {
        formulario: '1',
        mensagem: 'Oi',
        textoDoBotao: 'Preencher',
        nomeDoFormulario: 'n'.repeat(80),
      },
      { tela: 'INICIO', token: 't' }
    );
    expect(pedido.richMessage.name).toHaveLength(60);
    expect(pedido.richMessage.screen).toBe('INICIO');
  });

  it('localização e contato vão sem texto, como o servidor exige', () => {
    expect(
      montarLocalizacao({
        coordenadas: '-23.5, -46.6',
        nome: 'Loja',
        endereco: '',
      })
    ).toEqual({
      pedido: {
        content: '',
        richMessage: {
          type: 'location',
          latitude: -23.5,
          longitude: -46.6,
          name: 'Loja',
        },
      },
    });
    expect(montarLocalizacao({ coordenadas: 'perto do centro' })).toEqual({
      erros: { coordenadas: 'coordenadas' },
    });
    expect(montarContato({ nome: 'Ana', telefone: '11 98765-4321' })).toEqual({
      erros: { telefone: 'telefone' },
    });
    expect(
      montarContato({ nome: 'Ana', telefone: '+55 11 98765-4321' })
    ).toEqual({
      pedido: {
        content: '',
        richMessage: {
          type: 'contact',
          name: 'Ana',
          phone: '+5511987654321',
          wa_id: '5511987654321',
        },
      },
    });
  });

  it('a versão em texto da localização usa o mesmo link do servidor', () => {
    const { pedido } = montarLocalizacao({
      coordenadas: '-23.5, -46',
      nome: 'Loja',
      endereco: '',
    });
    expect(textoParaQuemNaoTemFormato(pedido)).toBe(
      'Loja\nhttps://maps.google.com/?q=-23.5,-46.0'
    );
  });

  it('pedido de localização leva o texto da mensagem', () => {
    expect(montarPedidoDeLocalizacao({ mensagem: 'Onde você está?' })).toEqual({
      pedido: {
        content: 'Onde você está?',
        richMessage: { type: 'location_request' },
      },
    });
  });
});
