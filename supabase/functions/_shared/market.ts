// Market data providers. The rest of the system only sees MarketDataProvider, so the
// vendor can be swapped (Finnhub, Twelve Data, EODHD, Polygon...) by adding one class.
//
// IMPORTANT: showing quotes to many users is redistribution. Before launch, use a plan
// whose licence allows display in a commercial app (free/personal tiers usually do not).

export interface Quote {
  symbol: string;
  price: number;
  prevClose: number | null;
  changePct: number | null;
  asOf: Date;
}

export interface MarketDataProvider {
  readonly name: string;
  /** Latest quote, or null when the provider does not cover the symbol. */
  quote(symbol: string): Promise<Quote | null>;
  /** Logo URL, if the provider has one. */
  logo(symbol: string): Promise<string | null>;
}

export class FinnhubProvider implements MarketDataProvider {
  readonly name = 'finnhub';
  constructor(private readonly apiKey: string, private readonly baseUrl = 'https://finnhub.io/api/v1') {}

  private async get<T>(path: string): Promise<T> {
    // Token in a header (not the query string) so it never ends up in URL logs.
    const res = await fetch(`${this.baseUrl}${path}`, { headers: { 'X-Finnhub-Token': this.apiKey } });
    if (res.status === 429) throw new RateLimitError();
    if (!res.ok) throw new Error(`Finnhub ${path} failed with ${res.status}`);
    return await res.json() as T;
  }

  async quote(symbol: string): Promise<Quote | null> {
    const q = await this.get<{ c: number; pc: number; dp: number | null; t: number }>(
      `/quote?symbol=${encodeURIComponent(symbol)}`,
    );
    // Finnhub answers unknown/unsupported symbols with zeros.
    if (!q || !q.c || !q.t) return null;
    return {
      symbol,
      price: q.c,
      prevClose: q.pc || null,
      changePct: q.dp ?? null,
      asOf: new Date(q.t * 1000),
    };
  }

  async logo(symbol: string): Promise<string | null> {
    const profile = await this.get<{ logo?: string }>(`/stock/profile2?symbol=${encodeURIComponent(symbol)}`);
    return profile?.logo || null;
  }
}

export class RateLimitError extends Error {
  constructor() {
    super('Market data provider rate limit reached');
  }
}

/** ECB euro reference rates: units of each currency per 1 EUR. Free, published daily. */
export async function fetchEcbRates(): Promise<{ asOf: string; rates: Record<string, number> }> {
  const res = await fetch('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml');
  if (!res.ok) throw new Error(`ECB rates failed with ${res.status}`);
  return parseEcbXml(await res.text());
}

export function parseEcbXml(xml: string): { asOf: string; rates: Record<string, number> } {
  const asOf = xml.match(/time=['"](\d{4}-\d{2}-\d{2})['"]/)?.[1];
  if (!asOf) throw new Error('ECB response has no reference date');
  const rates: Record<string, number> = {};
  for (const m of xml.matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g)) {
    rates[m[1]] = Number(m[2]);
  }
  if (!rates.USD) throw new Error('ECB response has no USD rate');
  return { asOf, rates };
}
