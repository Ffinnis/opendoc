# USD/RUB custom widget

Displays rubles per US dollar using the [Bank of Russia's official daily rates](https://www.cbr.ru/eng/currency_base/daily/), including the effective date. This is the published official rate, not a bank's buy/sell quote.

In a Custom widget, open Configure and choose the Webpage value template. Set:

| Field | Value |
| --- | --- |
| Name | USD/RUB |
| Webpage URL | `https://www.cbr.ru/eng/currency_base/daily/` |
| CSS selector | `.datepicker-filter_button, table.data tr:has(td)` |
| Attribute | Leave empty |
| Refresh | Every hour |
| Initial state | `{}` |
| Reset state each day | Off |

Replace the Display function with this code, then Preview and Save Widget:

```js
const row = input.matches.find(text => /^840\s+USD\s/.test(text));
if (!row) throw new Error('USD row missing from the CBR page');
const match = row.match(/^840\s+USD\s+(\d+)\s+.+?\s+([\d.,]+)$/);
if (!match) throw new Error('Unexpected CBR rate format');
const rate = Number(match[2].replace(',', '.')) / Number(match[1]);
if (!Number.isFinite(rate) || rate <= 0) throw new Error('Invalid USD rate');
const date = input.matches.find(text => /^\d{2}\.\d{2}\.\d{4}$/.test(text));
if (!date) throw new Error('CBR effective date missing');
return {
  value: rate.toFixed(4).replace('.', ',') + ' ₽',
  detail: '1 USD · CBR · ' + date
};
```

The popup includes a Refresh button automatically. No custom action buttons are needed. The code identifies USD by its numeric and alphabetic codes and divides by the published currency unit. It fails visibly if the rate or date cannot be found. The extractor supplies the first 20 CSS matches; if the source changes its table structure or moves USD beyond those matches, update the selector.
