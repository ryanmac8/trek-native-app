/// Currency rules shared by every money input and display, matching Trek's
/// web client (`client/src/utils/formatters.ts` and
/// `client/src/components/Budget/BudgetPanel.constants.ts`) so an amount
/// entered here reads and rounds the same way it does on the web.
///
/// Amounts travel to and from the backend as plain JSON numbers (e.g. a
/// budget item's `total_price`); everything in this file is about turning
/// those numbers into input text and back.
abstract final class Currency {
  /// The selectable currencies — the set Trek's exchange-rate provider can
  /// convert. Use [selectableWith] when an existing value must stay
  /// selectable.
  static const codes = <String>[
    'AED', 'AFN', 'ALL', 'AMD', 'ANG', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', //
    'BAM', 'BBD', 'BDT', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL', 'BSD',
    'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNH', 'CNY',
    'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP',
    'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL', 'GGP', 'GHS', 'GIP',
    'GMD', 'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS',
    'IMP', 'INR', 'IQD', 'IRR', 'ISK', 'JEP', 'JMD', 'JOD', 'JPY', 'KES',
    'KGS', 'KHR', 'KMF', 'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP',
    'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT',
    'MOP', 'MRO', 'MRU', 'MUR', 'MVR', 'MWK', 'MXN', 'MYR', 'MZN', 'NAD',
    'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP',
    'PKR', 'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD',
    'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN',
    'SVC', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD',
    'TWD', 'TZS', 'UAH', 'UGX', 'USD', 'UYU', 'UZS', 'VES', 'VND', 'VUV',
    'WST', 'XAF', 'XAG', 'XAU', 'XCD', 'XCG', 'XDR', 'XOF', 'XPD', 'XPF',
    'XPT', 'YER', 'ZAR', 'ZMW', 'ZWG',
  ];

  static const _symbols = <String, String>{
    'AED': 'د.إ', 'AFN': '؋', 'ALL': 'L', 'AMD': '֏', 'ANG': 'ƒ', //
    'AOA': 'Kz', 'ARS': r'$', 'AUD': r'$', 'AWG': 'ƒ', 'AZN': '₼',
    'BAM': 'КМ', 'BBD': r'$', 'BDT': '৳', 'BHD': 'د.ب', 'BIF': 'Fr',
    'BMD': r'$', 'BND': r'$', 'BOB': 'Bs.', 'BRL': r'R$', 'BSD': r'$',
    'BTN': 'Nu.', 'BWP': 'P', 'BYN': 'Br', 'BZD': r'$', 'CAD': r'$',
    'CDF': 'Fr', 'CHF': 'CHF', 'CLP': r'$', 'CNH': '¥', 'CNY': '¥',
    'COP': r'$', 'CRC': '₡', 'CUP': r'$', 'CVE': r'$', 'CZK': 'Kč',
    'DJF': 'Fdj', 'DKK': 'kr.', 'DOP': r'$', 'DZD': 'د.ج', 'EGP': 'ج.م',
    'ERN': 'Nfk', 'ETB': 'Br', 'EUR': '€', 'FJD': r'$', 'FKP': '£',
    'GBP': '£', 'GEL': '₾', 'GGP': '£', 'GHS': '₵', 'GIP': '£',
    'GMD': 'D', 'GNF': 'Fr', 'GTQ': 'Q', 'GYD': r'$', 'HKD': r'$',
    'HNL': 'L', 'HTG': 'G', 'HUF': 'Ft', 'IDR': 'Rp', 'ILS': '₪',
    'IMP': '£', 'INR': '₹', 'IQD': 'ع.د', 'IRR': '﷼', 'ISK': 'kr.',
    'JEP': '£', 'JMD': r'$', 'JOD': 'د.ا', 'JPY': '¥', 'KES': 'KSh',
    'KGS': 'som', 'KHR': '៛', 'KMF': 'Fr', 'KPW': '₩', 'KRW': '₩',
    'KWD': 'د.ك', 'KYD': r'$', 'KZT': '₸', 'LAK': '₭', 'LBP': 'ل.ل',
    'LKR': '₨', 'LRD': r'$', 'LSL': 'L', 'LYD': 'ل.د', 'MAD': 'د.م.',
    'MDL': 'L', 'MGA': 'Ar', 'MKD': 'ден', 'MMK': 'K', 'MNT': '₮',
    'MOP': 'P', 'MRO': 'UM', 'MRU': 'UM', 'MUR': '₨', 'MVR': 'MVR',
    'MWK': 'MK', 'MXN': r'$', 'MYR': 'RM', 'MZN': 'MTn', 'NAD': r'$',
    'NGN': '₦', 'NIO': r'C$', 'NOK': 'kr', 'NPR': 'Rs.', 'NZD': r'$',
    'OMR': 'ر.ع.', 'PAB': 'B/.', 'PEN': 'S/', 'PGK': 'K', 'PHP': '₱',
    'PKR': '₨', 'PLN': 'zł', 'PYG': '₲', 'QAR': 'ر.ق', 'RON': 'Lei',
    'RSD': 'RSD', 'RUB': '₽', 'RWF': 'FRw', 'SAR': 'ر.س', 'SBD': r'$',
    'SCR': '₨', 'SDG': '£', 'SEK': 'kr', 'SGD': r'$', 'SHP': '£',
    'SLE': 'Le', 'SOS': 'Sh', 'SRD': r'$', 'SSP': '£', 'STN': 'Db',
    'SVC': '₡', 'SYP': '£S', 'SZL': 'E', 'THB': '฿', 'TJS': 'ЅМ',
    'TMT': 'm', 'TND': 'د.ت', 'TOP': r'T$', 'TRY': '₺', 'TTD': r'$',
    'TWD': r'$', 'TZS': 'Sh', 'UAH': '₴', 'UGX': 'USh', 'USD': r'$',
    'UYU': r'$U', 'UZS': "so'm", 'VES': 'Bs', 'VND': '₫', 'VUV': 'Vt',
    'WST': 'T', 'XAF': 'CFA', 'XAG': 'oz t', 'XAU': 'oz t', 'XCD': r'$',
    'XCG': 'Cg', 'XDR': 'SDR', 'XOF': 'Fr', 'XPD': 'oz t', 'XPF': 'Fr',
    'XPT': 'oz t', 'YER': '﷼', 'ZAR': 'R', 'ZMW': 'K', 'ZWG': 'ZiG',
  };

  // Currencies whose smallest unit isn't 1/100. HUF is zero-decimal by
  // Trek's convention even though ISO 4217 lists 2.
  static const _zeroDecimal = {
    'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'HUF', 'BIF', 'DJF', 'GNF', 'KMF', //
    'PYG', 'RWF', 'UGX', 'VUV', 'XAF', 'XOF', 'XPF',
  };
  static const _threeDecimal = {
    'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND', //
  };

  // Currencies whose home locale writes the decimal part after a comma
  // (EUR → "1.234,56 €"). Every other currency uses a dot.
  static const _commaDecimal = {
    'EUR', 'CZK', 'PLN', 'SEK', 'NOK', 'DKK', 'TRY', 'BRL', 'IDR', 'ZAR', //
    'MAD', 'HUF', 'RON', 'BGN', 'HRK', 'ISK', 'RUB', 'UAH', 'KGS', 'VND',
    'CLP', 'COP', 'ARS',
  };

  /// [codes], plus [current] when it's a code outside that set (e.g. an
  /// archived currency an existing item was saved with), so editing that
  /// item never silently blanks its currency.
  static List<String> selectableWith(String? current) {
    final code = (current ?? '').toUpperCase();
    return code.isNotEmpty && !codes.contains(code) ? [...codes, code] : codes;
  }

  /// The symbol shown beside amounts (`€`, `$`, `¥`), falling back to the
  /// code itself for currencies without one.
  static String symbol(String currency) {
    final code = currency.toUpperCase();
    return _symbols[code] ?? code;
  }

  /// How many fractional digits amounts in [currency] carry: 0 (JPY), 3
  /// (KWD), or 2 for everything else.
  static int decimals(String currency) {
    final code = currency.toUpperCase();
    if (_zeroDecimal.contains(code)) return 0;
    if (_threeDecimal.contains(code)) return 3;
    return 2;
  }

  /// `,` or `.` — the separator [currency]'s amounts are displayed with,
  /// regardless of the device locale.
  static String decimalSeparator(String currency) =>
      _commaDecimal.contains(currency.toUpperCase()) ? ',' : '.';

  /// Rounds to whole cents, dropping the float noise an uneven split leaves
  /// behind (81.61 + 81.60 → 163.21, not 163.20999999999998). Cents rather
  /// than [decimals] to match the backend's own money arithmetic.
  static double cleanAmount(double value) => (value * 100).round() / 100;

  /// A stored amount as an edit field should show it: cent-rounded, padded
  /// to the currency's decimal count, using its [decimalSeparator]
  /// (`4.9` EUR → `4,90`; `500` JPY → `500`). Empty for null or non-finite
  /// values.
  static String toInputText(num? value, String currency) {
    if (value == null || !value.isFinite) return '';
    final text = cleanAmount(
      value.toDouble(),
    ).toStringAsFixed(decimals(currency));
    return decimalSeparator(currency) == ',' ? text.replaceAll('.', ',') : text;
  }

  /// Parses what the user typed into an amount field. Accepts either `,` or
  /// `.` as the decimal separator — whichever the keyboard offers — and no
  /// grouping separators. Returns null for empty or unparseable text.
  /// A trailing separator (`12,` while typing) parses as the whole number.
  static double? parseInput(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d*)?$|^\.\d+$').hasMatch(normalized)) return null;
    return double.tryParse(
      normalized.endsWith('.')
          ? normalized.substring(0, normalized.length - 1)
          : normalized,
    );
  }
}
