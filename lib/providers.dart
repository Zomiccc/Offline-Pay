/// All USSD knowledge lives here. Edit this file to add/fix providers and flows.
///
/// A flow is a list of USSD steps. Step 0 is dialed; every later step is typed into
/// the menu the network shows. Placeholders {id} are replaced with the value the user
/// entered for the field with that id. Choice fields send the option's `value`.
///
/// IMPORTANT: menu digits below are UNVERIFIED placeholders. Dial each code by hand,
/// note the real menu numbers, and fix them here before releasing.
enum FieldKind { phone, amount, pin, choice }

class Option {
  final String label;
  final String value; // what is typed into the USSD menu
  const Option(this.label, this.value);
}

class Field {
  final String id;
  final String label;
  final FieldKind kind;
  final List<Option> options;
  const Field(this.id, this.label, this.kind, [this.options = const []]);
}

class Action {
  final String title;
  final String icon; // key into the icon map in main.dart
  final List<Field> fields;
  final List<String> steps;
  const Action(this.title, this.icon, this.fields, this.steps);

  List<String> build(Map<String, String> values) => steps
      .map((s) => s.replaceAllMapped(
          RegExp(r'\{(\w+)\}'), (m) => values[m[1]] ?? ''))
      .toList();
}

/// SIM networks the user can choose from.
const simNetworks = ['Jazz', 'Telenor', 'Zong', 'Ufone'];

class Provider {
  final String name;

  /// USSD entry code per SIM network. A network missing from this map means the
  /// wallet cannot be used offline on that SIM (e.g. JazzCash on a Zong SIM).
  final Map<String, String> codes;
  final List<Action> Function(String code) flows;
  Provider(this.name, this.codes, this.flows);

  bool supports(String network) => codes.containsKey(network);
  List<Action> actionsFor(String network) => flows(codes[network]!);
}

const _phone = Field('number', 'Receiver mobile number', FieldKind.phone);
const _amount = Field('amount', 'Amount (Rs.)', FieldKind.amount);
const _pin = Field('pin', 'Wallet PIN (not saved)', FieldKind.pin);

const banks = [
  Option('HBL', '1'),
  Option('UBL', '2'),
  Option('Meezan Bank', '3'),
  Option('Allied Bank', '4'),
  Option('Bank Alfalah', '5'),
  Option('MCB', '6'),
];
const loadNetworks = [
  Option('Jazz', '1'),
  Option('Telenor', '2'),
  Option('Zong', '3'),
  Option('Ufone', '4'),
];

// Easypaisa flow (from user research): dial code -> PIN -> pick option -> pick
// destination type -> receiver + amount -> confirm with PIN.
// Entry codes are confirmed by Easypaisa's FAQ; the menu digits are UNVERIFIED.
List<Action> _easypaisa(String code) => [
      Action('Check balance', 'balance', const [_pin], [code, '{pin}', '1']),
      Action('Send to wallet', 'send', const [_phone, _amount, _pin],
          [code, '{pin}', '2', '1', '{number}', '{amount}', '{pin}']),
      Action(
          'Send to bank account',
          'bank',
          const [
            Field('bank', 'Choose bank', FieldKind.choice, banks),
            Field('account', 'Account number / IBAN', FieldKind.phone),
            _amount,
            _pin
          ],
          [code, '{pin}', '2', '2', '{bank}', '{account}', '{amount}', '{pin}']),
      Action(
          'Mobile load',
          'load',
          const [
            Field('network', 'Network', FieldKind.choice, loadNetworks),
            _phone,
            _amount,
            _pin
          ],
          [code, '{pin}', '3', '{network}', '{number}', '{amount}', '{pin}']),
    ];

// JazzCash flow: *786# is the main menu, *786*1# jumps straight to money transfer
// (mobile account / bank / CNIC). Menu digits after that are UNVERIFIED.
List<Action> _jazzcash(String code) => [
      Action('Check balance', 'balance', const [_pin], [code, '2', '{pin}']),
      Action('Send to wallet', 'send', const [_phone, _amount, _pin],
          ['*786*1#', '1', '{number}', '{amount}', '{pin}']),
      Action(
          'Send to bank account',
          'bank',
          const [
            Field('bank', 'Choose bank', FieldKind.choice, banks),
            Field('account', 'Account number / IBAN', FieldKind.phone),
            _amount,
            _pin
          ],
          ['*786*1#', '2', '{bank}', '{account}', '{amount}', '{pin}']),
      Action(
          'Mobile load',
          'load',
          const [
            Field('network', 'Network', FieldKind.choice, loadNetworks),
            _phone,
            _amount,
            _pin
          ],
          [code, '3', '{network}', '{number}', '{amount}', '{pin}']),
    ];

// Only wallets with a known code are listed. Add UPaisa, SadaPay, HBL Konnect, etc.
// here once you have confirmed their USSD codes on a real SIM.
final providers = <Provider>[
  Provider('Easypaisa', const {
    'Telenor': '*786#',
    'Jazz': '*2262#',
    'Zong': '*2262#',
    'Ufone': '*2262#',
  }, _easypaisa),
  Provider('JazzCash', const {'Jazz': '*786#'}, _jazzcash),
];
