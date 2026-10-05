import 'package:flutter/material.dart' hide Action;
import 'package:flutter/services.dart';
import 'providers.dart';

void main() => runApp(const App());

const _ch = MethodChannel('pk.ussdpay/ussd');

const _icons = <String, IconData>{
  'balance': Icons.account_balance_wallet,
  'send': Icons.send,
  'bank': Icons.account_balance,
  'load': Icons.phone_android,
};

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Offline-Pay',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF0B8F4D), useMaterial3: true),
        home: const HomePage(),
      );
}

/// Step 1: pick the wallet / bank.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _helperOn = true;
  String? _network;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final on = await _ch.invokeMethod<bool>('accessibilityEnabled') ?? false;
    if (mounted) setState(() => _helperOn = on);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline-Pay')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!_helperOn)
          Card(
            color: Colors.amber.shade100,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text('One-time setup needed'),
              subtitle: const Text(
                  'Turn on "Offline-Pay USSD helper" in Accessibility so the app can work the menus for you.'),
              trailing: FilledButton(
                  onPressed: () =>
                      _ch.invokeMethod('openAccessibilitySettings'),
                  child: const Text('Open')),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('1. Which SIM network are you on?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Wrap(spacing: 8, children: [
          for (final n in simNetworks)
            ChoiceChip(
              label: Text(n),
              selected: _network == n,
              onSelected: (_) => setState(() => _network = n),
            ),
        ]),
        if (_network != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('2. Choose your bank / wallet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final p in providers.where((p) => p.supports(_network!)))
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(p.name),
                subtitle: Text('Dials ${p.codes[_network]}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ActionsPage(provider: p, network: _network!))),
              ),
            ),
          if (providers.every((p) => !p.supports(_network!)))
            const Text('No wallets available offline on this SIM yet.'),
        ],
      ]),
    );
  }
}

/// Step 2: pick what to do (balance, send, bank transfer, ...).
class ActionsPage extends StatelessWidget {
  final Provider provider;
  final String network;
  const ActionsPage({super.key, required this.provider, required this.network});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${provider.name} ($network SIM)')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final a in provider.actionsFor(network))
            Card(
              child: ListTile(
                leading: Icon(_icons[a.icon]),
                title: Text(a.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            FormPage(provider: provider, action: a))),
              ),
            ),
        ]),
      );
}

/// Step 3: ask only for what this action's USSD menu needs.
class FormPage extends StatefulWidget {
  final Provider provider;
  final Action action;
  const FormPage({super.key, required this.provider, required this.action});
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _form = GlobalKey<FormState>();
  final _values = <String, String>{};

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    final a = widget.action;
    final summary = a.fields
        .where((f) => f.kind != FieldKind.pin)
        .map((f) => '${f.label}: ${f.kind == FieldKind.choice ? f.options.firstWhere((o) => o.value == _values[f.id]).label : _values[f.id]}')
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Confirm: ${a.title}'),
        content: Text('${widget.provider.name}\n\n$summary'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final steps = a.build(_values);
    _values.remove('pin'); // never keep the PIN around
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => RunPage(title: a.title, steps: steps)));
  }

  Widget _field(Field f) {
    const border = OutlineInputBorder();
    switch (f.kind) {
      case FieldKind.choice:
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: f.label, border: border),
          items: [
            for (final o in f.options)
              DropdownMenuItem(value: o.value, child: Text(o.label))
          ],
          onChanged: (_) {},
          onSaved: (v) => _values[f.id] = v!,
          validator: (v) => v == null ? 'Please choose' : null,
        );
      case FieldKind.pin:
        return TextFormField(
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6)
          ],
          decoration: InputDecoration(labelText: f.label, border: border),
          onSaved: (v) => _values[f.id] = v!,
          validator: (v) => (v?.length ?? 0) >= 4 ? null : 'Enter your PIN',
        );
      case FieldKind.amount:
        return TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: f.label, border: border),
          onSaved: (v) => _values[f.id] = v!.trim(),
          validator: (v) =>
              (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter an amount',
        );
      case FieldKind.phone:
        return TextFormField(
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: f.label, border: border),
          onSaved: (v) => _values[f.id] = v!.trim(),
          validator: (v) =>
              (v?.trim().length ?? 0) >= 8 ? null : 'Enter a valid value',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.action.title)),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              for (final f in widget.action.fields) ...[
                _field(f),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: const Text('Continue'),
              ),
            ]),
          ),
        ),
      );
}

/// Step 4: run the USSD session and show each reply live.
class RunPage extends StatefulWidget {
  final String title;
  final List<String> steps;
  const RunPage({super.key, required this.title, required this.steps});
  @override
  State<RunPage> createState() => _RunPageState();
}

class _RunPageState extends State<RunPage> {
  final _log = <String>[];
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ch.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'progress') {
        setState(() => _log.add(call.arguments as String));
      } else if (call.method == 'result') {
        setState(() => _result = call.arguments as String);
      }
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await _ch.invokeMethod('session', {'steps': widget.steps});
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  @override
  void dispose() {
    _ch.invokeMethod('cancel');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _result != null || _error != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (!done) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        for (final l in _log)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(l, maxLines: 4, overflow: TextOverflow.ellipsis))),
        if (_result != null)
          Card(
              color: Colors.green.shade50,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_result!,
                      style: const TextStyle(fontSize: 16)))),
        if (_error != null)
          Card(
              color: Colors.red.shade50,
              child: Padding(
                  padding: const EdgeInsets.all(16), child: Text(_error!))),
        if (done)
          FilledButton(
              onPressed: () =>
                  Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Done')),
      ]),
    );
  }
}
