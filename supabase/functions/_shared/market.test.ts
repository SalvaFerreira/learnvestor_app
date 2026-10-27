import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { parseEcbXml } from './market.ts';

const sample = `<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
  <Cube>
    <Cube time='2026-10-22'>
      <Cube currency='USD' rate='1.0842'/>
      <Cube currency='GBP' rate='0.8391'/>
    </Cube>
  </Cube>
</gesmes:Envelope>`;

Deno.test('parses ECB reference rates', () => {
  assertEquals(parseEcbXml(sample), { asOf: '2026-10-22', rates: { USD: 1.0842, GBP: 0.8391 } });
});

Deno.test('rejects responses without a date or USD rate', () => {
  assertThrows(() => parseEcbXml('<Cube/>'));
  assertThrows(() => parseEcbXml("<Cube time='2026-10-22'><Cube currency='GBP' rate='0.8'/></Cube>"));
});
