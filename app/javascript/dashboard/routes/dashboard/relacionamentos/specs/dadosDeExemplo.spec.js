import { empresas, pessoas } from '../demo/base';
import { pessoa as pessoaDaFicha } from '../demo/ficha';
import { pertenceAoGrupo } from '../fonte/grupos';
import { pessoasDeExemplo } from '../lista/pessoasDeExemplo';
import { quemTrouxeNaDemo } from '../demo/trazer';

// Dados de exemplo (#2894) que aparecem nos prints: variedade de nomes, equipe
// que não se confunde com cliente, empresas sem sobrenome repetido e perfis de
// rede sem número de id.
const AGORA = 1_700_000_000_000;
const ultimaPalavra = nome => nome.split(' ').at(-1);
const SOBRENOMES_DA_EQUIPE = ['Valtorini', 'Zanquetta', 'Pavanelli'];
const AMOSTRA_DE_FICHAS = 60;

describe('sobrenomes das pessoas', () => {
  it('são pelo menos 40 diferentes, para a primeira tela não repetir', () => {
    const usados = new Set(pessoas(AGORA).map(p => ultimaPalavra(p.name)));
    expect(usados.size).toBeGreaterThanOrEqual(40);
  });

  it('a primeira tela (25 pessoas) mostra bastante variedade', () => {
    const primeiros = pessoas(AGORA)
      .slice(0, 25)
      .map(p => ultimaPalavra(p.name));
    expect(new Set(primeiros).size).toBeGreaterThanOrEqual(15);
  });
});

describe('equipe', () => {
  it('os sobrenomes de quem atende não aparecem em cliente nem em empresa', () => {
    const nomes = [
      ...pessoas(AGORA).map(p => p.name),
      ...empresas(AGORA).map(e => e.name),
    ].join(' ');
    SOBRENOMES_DA_EQUIPE.forEach(sobrenome =>
      expect(nomes).not.toContain(sobrenome)
    );
  });
});

describe('quem trouxe as listas', () => {
  it('é alguém da equipe, não um cliente', () => {
    expect(SOBRENOMES_DA_EQUIPE).toContain(ultimaPalavra(quemTrouxeNaDemo()));
  });
});

describe('lista de exemplo da conta vazia', () => {
  const exemplo = pessoasDeExemplo(AGORA);

  it('são 5 pessoas inventadas, sem sobrenome da equipe nem de cliente da demonstração', () => {
    expect(exemplo).toHaveLength(5);
    const daDemo = new Set(pessoas(AGORA).map(p => ultimaPalavra(p.name)));
    exemplo.forEach(p => {
      expect(SOBRENOMES_DA_EQUIPE).not.toContain(ultimaPalavra(p.name));
      expect(daDemo.has(ultimaPalavra(p.name))).toBe(false);
    });
  });

  it('os telefones ficam no bloco fictício +55 11 9XXXX-00NN', () => {
    exemplo.forEach(p => {
      expect(p.phone_number.startsWith('+55119')).toBe(true);
      expect(p.phone_number).toHaveLength(14);
      expect(p.phone_number.slice(-4, -2)).toBe('00');
    });
  });

  it('cada uma já falou em um dia diferente', () => {
    const dias = exemplo.map(p => p.last_activity_at);
    expect(new Set(dias).size).toBe(exemplo.length);
  });
});

describe('empresas', () => {
  const nomes = () => empresas(AGORA).map(e => e.name);

  it('nenhuma repete a última palavra do nome (o sobrenome)', () => {
    const finais = nomes().map(ultimaPalavra);
    expect(new Set(finais).size).toBe(finais.length);
  });

  it('misturam nome de fantasia e nome com sobrenome', () => {
    expect(nomes()).toEqual(
      expect.arrayContaining(['Padaria Bom Dia', 'Oficina do Centro'])
    );
    const comSobrenome = new Set(
      pessoas(AGORA).map(p => ultimaPalavra(p.name))
    );
    const quantasComSobrenomeDeCliente = nomes().filter(n =>
      comSobrenome.has(ultimaPalavra(n))
    ).length;
    expect(quantasComSobrenomeDeCliente).toBeGreaterThan(0);
    expect(quantasComSobrenomeDeCliente).toBeLessThan(nomes().length);
  });
});

describe('perfil de rede', () => {
  it('o Instagram é primeiro nome e sobrenome, sem número de id', () => {
    // Uma amostra basta: montar a ficha de cada pessoa da base estoura o limite
    // de tempo do teste em máquina carregada (e na CI).
    const comInstagram = pessoas(AGORA)
      .slice(0, AMOSTRA_DE_FICHAS)
      .map(p => pessoaDaFicha(p.id))
      .map(p => ({
        nome: p.name,
        perfil: p.additional_attributes.social_profiles.instagram,
      }))
      .filter(p => p.perfil);
    expect(comInstagram.length).toBeGreaterThan(0);
    comInstagram.forEach(({ nome, perfil }) => {
      const [primeiro, ...resto] = nome.split(' ');
      const esperado = `@${primeiro}.${resto.join('.')}`
        .toLowerCase()
        .normalize('NFD')
        .split('')
        .filter(char => char.codePointAt(0) < 0x300)
        .join('');
      expect(perfil).toBe(esperado);
      expect([...perfil].some(char => char >= '0' && char <= '9')).toBe(false);
    });
  });
});

describe('o roteiro de prints', () => {
  it('mantém as situações das pessoas 23, 39 e 203 e a empresa 2', () => {
    const lista = pessoas(AGORA);
    const por = id => lista.find(p => p.id === id);
    expect(por(203).opted_out_at).not.toBeNull();
    expect(por(39).last_activity_at).toBeNull();
    expect(por(23)).toBeTruthy();
    const daEmpresa2 = lista.filter(p => p.company_id === 2);
    expect(daEmpresa2.some(p => p.opted_out_at)).toBe(true);
    expect(
      lista.filter(p => pertenceAoGrupo(p, 'sumiu_1_a_3_meses', AGORA))
    ).toHaveLength(42);
  });
});
