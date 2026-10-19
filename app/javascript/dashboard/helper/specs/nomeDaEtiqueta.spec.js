import {
  mesmoNome,
  nomeDaEtiqueta,
  nomeLegivelDoTitulo,
  tituloTecnicoDoNome,
} from '../nomeDaEtiqueta';

describe('nomeDaEtiqueta', () => {
  it('derives the name of a label without a saved name from its title', () => {
    expect(nomeDaEtiqueta('aguardando_retorno')).toBe('Aguardando retorno');
    expect(nomeDaEtiqueta('vip')).toBe('Vip');
    expect(nomeLegivelDoTitulo('suporte-tecnico')).toBe('Suporte-tecnico');
  });

  it('prefers the saved name, then the phone name (F1b), then the title', () => {
    expect(
      nomeDaEtiqueta('novo_cliente', {
        nomeGuardado: 'Novo Cliente',
        nomeNoCelular: 'Novo cliente 🔥',
      })
    ).toBe('Novo Cliente');
    expect(
      nomeDaEtiqueta('novo_cliente', { nomeNoCelular: 'Novo cliente 🔥' })
    ).toBe('Novo cliente 🔥');
  });

  it('returns empty for an empty title', () => {
    expect(nomeDaEtiqueta('', { nomeGuardado: 'Nome' })).toBe('');
    expect(nomeDaEtiqueta(undefined)).toBe('');
    expect(nomeLegivelDoTitulo('___')).toBe('');
  });
});

describe('tituloTecnicoDoNome', () => {
  it('lowercases and turns spaces into "_"', () => {
    expect(tituloTecnicoDoNome('Novo Cliente')).toBe('novo_cliente');
    expect(tituloTecnicoDoNome('  Aguardando   retorno ')).toBe(
      'aguardando_retorno'
    );
  });

  it('drops what the Label validation refuses (emoji, punctuation)', () => {
    expect(tituloTecnicoDoNome('Cliente VIP ⭐')).toBe('cliente_vip');
    expect(tituloTecnicoDoNome('Orçamento enviado!')).toBe('orçamento_enviado');
    expect(tituloTecnicoDoNome('Pós-venda 2026')).toBe('pós-venda_2026');
  });

  it('never starts with "_" or "-", which the Label validation refuses', () => {
    expect(tituloTecnicoDoNome('- VIP')).toBe('vip');
    expect(tituloTecnicoDoNome('🔥 _novo')).toBe('novo');
  });

  it('keeps an accent typed as a separate mark (NFD)', () => {
    expect(tituloTecnicoDoNome('Pre\u0301-venda')).toBe('pré-venda');
  });

  it('keeps an already technical title as it is', () => {
    expect(tituloTecnicoDoNome('aguardando_retorno')).toBe(
      'aguardando_retorno'
    );
  });

  it('returns empty when nothing usable is left', () => {
    expect(tituloTecnicoDoNome('⭐ 🔥 !!')).toBe('');
    expect(tituloTecnicoDoNome('')).toBe('');
  });
});

describe('mesmoNome', () => {
  it('ignores case and surrounding spaces', () => {
    expect(mesmoNome(' Aguardando Retorno ', 'aguardando retorno')).toBe(true);
    expect(mesmoNome('Vip', 'Cliente VIP')).toBe(false);
  });
});
