import { effectScope } from 'vue';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS, useTrazerLista } from '../../trazer/useTrazerLista';
const erroDeNome = (nome, extra = {}) =>
  Object.assign(new Error(nome), { name: nome, ...extra });

describe('useTrazerLista: a recusa da linha, a troca de coluna e as respostas', () => {
  const LIDA = {
    id: 812,
    arquivo: 'a.csv',
    colunas: [
      { indice: 0, nome: 'Cliente?', destino: 'informacao' },
      { indice: 1, nome: 'Cel', destino: 'telefone' },
    ],
    perguntas: [],
    respostas: {},
    resumo: { total: 3, novas: 2, completadas: 0, comProblema: 1 },
    exemplos: [],
    problemas: [
      {
        linha: 14,
        tipo: 'telefone',
        nome: 'Tadeu',
        valor: 'x',
        estado: 'aberto',
      },
      { linha: 37, tipo: 'email', nome: 'Rita', valor: 'y', estado: 'aberto' },
    ],
  };
  const montar = (daFonte = {}, lida = LIDA) => {
    const escopo = effectScope();
    const avisar = vi.fn();
    const fonte = { ler: vi.fn(async () => lida), ...daFonte };
    const tela = escopo.run(() => useTrazerLista({ fonte, avisar }));
    return { tela, avisar, fonte };
  };
  const lida = async (daFonte, leituraLida) => {
    const montado = montar(daFonte, leituraLida);
    await montado.tela.escolherArquivo({ name: 'a.csv' });
    return montado;
  };
  const RECUSA = erroDeNome('VALOR_INVALIDO', {
    motivo: 'invalid_brazilian_mobile_number',
  });
  const GUARDADA = {
    ...LIDA,
    problemas: [
      { ...LIDA.problemas[0], estado: 'guardado' },
      LIDA.problemas[1],
    ],
  };

  it('o servidor recusa o valor: a tela guarda a recusa da linha e não avisa por toast', async () => {
    const { tela, avisar } = await lida({
      consertar: vi.fn().mockRejectedValue(RECUSA),
    });
    expect(tela.recusaDoConserto.value).toBeNull();
    expect(await tela.guardar(14, '+551199')).toBe(false);
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 14,
      motivo: 'invalid_brazilian_mobile_number',
    });
    expect(avisar).not.toHaveBeenCalled();
    expect(tela.ocupado.value).toBe(false);
    expect(tela.leitura.value).toEqual(LIDA);
  });

  it('cada recusa é um aviso novo, mesmo com o mesmo motivo', async () => {
    const { tela } = await lida({
      consertar: vi.fn().mockRejectedValue(RECUSA),
    });
    await tela.guardar(14, '+551199');
    const primeira = tela.recusaDoConserto.value;
    await tela.guardar(14, '+551198');
    expect(tela.recusaDoConserto.value).toEqual(primeira);
    expect(tela.recusaDoConserto.value).not.toBe(primeira);
  });

  it('a recusa some quando a linha é salva', async () => {
    const consertar = vi
      .fn()
      .mockRejectedValueOnce(RECUSA)
      .mockResolvedValueOnce(GUARDADA);
    const { tela } = await lida({ consertar });
    await tela.guardar(14, '+551199');
    expect(await tela.guardar(14, '+5511973800014')).toBe(true);
    expect(tela.recusaDoConserto.value).toBeNull();
  });

  it('a recusa some quando a linha é deixada de fora e quando a tela recomeça', async () => {
    const { tela } = await lida({
      consertar: vi.fn().mockRejectedValue(RECUSA),
      deixarDeFora: vi.fn(async () => LIDA),
    });
    await tela.guardar(14, '+551199');
    await tela.deixarDeFora(14);
    expect(tela.recusaDoConserto.value).toBeNull();
    await tela.guardar(14, '+551199');
    tela.recomecar();
    expect(tela.recusaDoConserto.value).toBeNull();
  });

  it('mexer em outra linha não apaga a recusa desta', async () => {
    const { tela } = await lida({
      consertar: vi.fn().mockRejectedValue(RECUSA),
      deixarDeFora: vi.fn(async () => LIDA),
    });
    await tela.guardar(14, '+551199');
    await tela.deixarDeFora(37);
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 14,
      motivo: 'invalid_brazilian_mobile_number',
    });
  });

  // Nenhuma falha de escrita fica só no aviso que some: quem diz é a linha, e
  // só ela (o aviso solto repetiria a mesma frase).
  it('outro erro do conserto fica com a linha, sem aviso solto', async () => {
    const { tela, avisar } = await lida({
      consertar: vi.fn().mockRejectedValue(new Error('caiu')),
    });
    await tela.guardar(14, 'x');
    expect(avisar).not.toHaveBeenCalled();
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 14,
      motivo: 'nao_salvou',
    });
  });

  it('a troca que tiraria a última coluna de contato (TROCA_SEM_CONTATO) diz a frase própria, na coluna e no aviso', async () => {
    const { tela, avisar } = await lida({
      trocarDestino: vi.fn().mockRejectedValue(erroDeNome('TROCA_SEM_CONTATO')),
    });
    expect(await tela.trocarDestino(1, 'nao_guardar')).toBe(false);
    expect(avisar.mock.calls).toEqual([
      ['RELACIONAMENTOS_TRAZER.ERROS.SEM_COLUNA_DE_CONTATO'],
    ]);
    expect(tela.recusaDaColuna.value).toEqual({
      coluna: 1,
      chave: 'RELACIONAMENTOS_TRAZER.ERROS.SEM_COLUNA_DE_CONTATO',
    });
  });

  // A planilha lida de novo que termina sem ninguém: a mudança já estava salva
  // e não há o que consertar na tela; ela volta ao Enviar e diz por quê.
  it('a planilha lida de novo sem contato (PLANILHA_SEM_CONTATO) volta ao Enviar com a frase fixa', async () => {
    const { tela, avisar } = await lida({
      trocarDestino: vi.fn(async () => ({ situacao: 'lendo', id: 812 })),
      retomar: vi.fn().mockRejectedValue(erroDeNome('PLANILHA_SEM_CONTATO')),
    });
    expect(await tela.trocarDestino(1, 'nao_guardar')).toBe(false);
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.SEM_NINGUEM);
    expect(avisar).not.toHaveBeenCalled();
  });

  it('trocarDestino repassa o campo da informação nova à fonte', async () => {
    const trocarDestino = vi.fn(async () => LIDA);
    const { tela } = await lida({ trocarDestino });
    const campo = { nome: 'Fase', para_que_serve: 'fase da venda' };
    await tela.trocarDestino(0, 'informacao', campo);
    expect(trocarDestino).toHaveBeenCalledWith(812, 0, 'informacao', campo);
  });

  describe('perguntas', () => {
    const COM_PERGUNTAS = { ...LIDA, perguntas: [{ id: 'clientes' }] };

    it('as respostas começam pelas que a leitura traz do servidor', async () => {
      const { tela } = await lida(
        {},
        { ...COM_PERGUNTAS, respostas: { clientes: 'ainda_nao' } }
      );
      expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
      expect(tela.respostas.value).toEqual({ clientes: 'ainda_nao' });
      expect(tela.podeContinuar.value).toBe(true);
    });

    it('mexer nas respostas da tela não mexe na leitura', async () => {
      const { tela } = await lida({}, COM_PERGUNTAS);
      tela.responder('clientes', 'sim_todas');
      expect(tela.leitura.value.respostas).toEqual({});
    });

    it('a primeira coluna da planilha (índice 0) vale como coluna escolhida', async () => {
      // O servidor devolve a leitura com a resposta que gravou.
      const responder = vi.fn(async () => ({
        ...COM_PERGUNTAS,
        respostas: { clientes: 'algumas', colunaCliente: 0 },
      }));
      const { tela } = await lida({ responder }, COM_PERGUNTAS);
      tela.responder('clientes', 'algumas');
      expect(tela.podeContinuar.value).toBe(false);
      tela.escolherColunaDeCliente(0);
      expect(tela.podeContinuar.value).toBe(true);
      await tela.continuar();
      expect(responder).toHaveBeenCalledWith(812, {
        clientes: 'algumas',
        colunaCliente: 0,
      });
      expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    });
  });
});
