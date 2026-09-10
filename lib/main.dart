import 'package:flutter/material.dart';

void main() {
  runApp(const PopInvoiceApp());
}

// ---------------- DATA MODELS ----------------
class Product {
  final int id;
  final String name;
  final String icon;
  final String category;
  final double price;

  Product({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.price,
  });
}

class InvoiceItem {
  final Product product;
  double qty;
  double rate;

  InvoiceItem({
    required this.product,
    required this.qty,
    required this.rate,
  });

  double get total => qty * rate;
}

class Invoice {
  final String invNumber;
  final String date;
  final String customerName;
  final String customerPhone;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discount;
  final double grand;
  final double paid;
  final double previousDue;
  final double remaining;
  final String paymentMethod;

  Invoice({
    required this.invNumber,
    required this.date,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.grand,
    required this.paid,
    required this.previousDue,
    required this.remaining,
    required this.paymentMethod,
  });
}

class Customer {
  final String key;
  final String name;
  final String phone;
  double balance;

  Customer({
    required this.key,
    required this.name,
    required this.phone,
    required this.balance,
  });
}

// ---------------- STATE STORE ----------------
class WorkshopStore extends ChangeNotifier {
  List<Product> products = [
    Product(id: 1, name: '2x2 Plain Tile', icon: '⬜', category: 'Tiles', price: 120.0),
    Product(id: 2, name: '2x2 Design Tile', icon: '✨', category: 'Tiles', price: 140.0),
    Product(id: 3, name: 'POP Bag (Special)', icon: '🧱', category: 'Plaster Bags', price: 550.0),
    Product(id: 4, name: 'POP Bag (Standard)', icon: '📦', category: 'Plaster Bags', price: 480.0),
    Product(id: 5, name: 'Ceiling Patti (G.I)', icon: '📏', category: 'Design', price: 90.0),
    Product(id: 6, name: 'Jali Roll', icon: '🕸️', category: 'Others', price: 850.0),
    Product(id: 7, name: 'Corner Rose', icon: '🌸', category: 'Design', price: 250.0),
  ];

  List<Invoice> invoices = [];
  Map<String, Customer> customers = {};

  String getNextInvoiceNumber() {
    int next = invoices.length + 1;
    return 'INV-${next.toString().padLeft(6, '0')}';
  }

  void addProduct(String name, String icon, String category, double price) {
    products.add(Product(
      id: products.length + 1,
      name: name,
      icon: icon,
      category: category,
      price: price,
    ));
    notifyListeners();
  }

  void saveInvoice(Invoice inv) {
    invoices.insert(0, inv);
    if (inv.customerName != 'Walk-in Customer') {
      final key = inv.customerPhone.isNotEmpty ? inv.customerPhone : inv.customerName;
      if (!customers.containsKey(key)) {
        customers[key] = Customer(key: key, name: inv.customerName, phone: inv.customerPhone, balance: 0);
      }
      customers[key]!.balance += inv.remaining;
    }
    notifyListeners();
  }

  void recordPayment(String key, double amount) {
    if (customers.containsKey(key)) {
      customers[key]!.balance -= amount;
      if (customers[key]!.balance < 0) customers[key]!.balance = 0;
      notifyListeners();
    }
  }

  double get todayCashSales {
    final today = DateTime.now().toString().substring(0, 10);
    return invoices
        .where((i) => i.date.startsWith(today))
        .fold(0.0, (sum, i) => sum + i.paid);
  }

  double get todayCreditSales {
    final today = DateTime.now().toString().substring(0, 10);
    return invoices
        .where((i) => i.date.startsWith(today))
        .fold(0.0, (sum, i) => sum + i.remaining);
  }
}

final appStore = WorkshopStore();

// ---------------- APP ROOT ----------------
class PopInvoiceApp extends StatelessWidget {
  const PopInvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POP Invoice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------- 1. HOME SCREEN ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    appStore.addListener(_refresh);
  }

  @override
  void dispose() {
    appStore.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toString().substring(0, 10);
    final todayCount = appStore.invoices.where((i) => i.date.startsWith(today)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POP Workshop Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Today's Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Chip(label: Text('$todayCount Bills'), backgroundColor: Colors.blue.shade50),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metricTile('Cash Received', 'Rs. ${appStore.todayCashSales.toStringAsFixed(0)}', Colors.green),
                        _metricTile('Udhar Added', 'Rs. ${appStore.todayCreditSales.toStringAsFixed(0)}', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  _bigNavCard(
                    title: 'New Bill',
                    subtitle: 'Create Invoice',
                    icon: Icons.receipt_long,
                    color: const Color(0xFF1565C0),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateInvoiceScreen())),
                  ),
                  _bigNavCard(
                    title: 'Customer Ledger',
                    subtitle: 'Udhar Khata',
                    icon: Icons.account_balance_wallet,
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerLedgerScreen())),
                  ),
                  _bigNavCard(
                    title: 'History',
                    subtitle: 'Search & View',
                    icon: Icons.history,
                    color: Colors.teal,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen())),
                  ),
                  _bigNavCard(
                    title: 'Products',
                    subtitle: 'Manage Items',
                    icon: Icons.category,
                    color: Colors.indigo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductCatalogScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String title, String value, Color color) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _bigNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: Colors.white),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. CREATE INVOICE SCREEN ----------------
class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _nameCtrl = TextEditingController(text: 'Walk-in Customer');
  final _phoneCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');

  List<InvoiceItem> selectedItems = [];
  double previousDue = 0.0;
  String paymentMode = 'Cash';

  void _checkCustomerDue(String _) {
    final key = _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : _nameCtrl.text;
    if (appStore.customers.containsKey(key)) {
      setState(() => previousDue = appStore.customers[key]!.balance);
    } else {
      setState(() => previousDue = 0.0);
    }
  }

  double get subtotal => selectedItems.fold(0.0, (sum, i) => sum + i.total);
  double get discount => double.tryParse(_discountCtrl.text) ?? 0.0;
  double get grand => (subtotal - discount) > 0 ? (subtotal - discount) : 0.0;
  double get totalPayable => grand + previousDue;
  double get paidAmount => paymentMode == 'Cash' ? totalPayable : (double.tryParse(_paidCtrl.text) ?? 0.0);
  double get remainingDue => (totalPayable - paidAmount) > 0 ? (totalPayable - paidAmount) : 0.0;

  void _openProductPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick POP Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 350,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: appStore.products.length,
                itemBuilder: (context, idx) {
                  final p = appStore.products[idx];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        selectedItems.add(InvoiceItem(product: p, qty: 1, rate: p.price));
                      });
                    },
                    child: Card(
                      color: Colors.blue.shade50,
                      elevation: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(p.icon, style: const TextStyle(fontSize: 32)),
                          const SizedBox(height: 4),
                          Text(p.name, textAlign: TextAlign.center, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Rs. ${p.price}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Bill'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Customer Name', prefixIcon: Icon(Icons.person)),
                          onChanged: _checkCustomerDue,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quick Walk-in',
                        icon: const Icon(Icons.flash_on, color: Colors.amber, size: 28),
                        onPressed: () {
                          setState(() {
                            _nameCtrl.text = 'Walk-in Customer';
                            _phoneCtrl.clear();
                            previousDue = 0.0;
                          });
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number (For Ledger)', prefixIcon: Icon(Icons.phone)),
                    onChanged: _checkCustomerDue,
                  ),
                  if (previousDue > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Text('Previous Due: Rs. ${previousDue.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Items Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
                onPressed: _openProductPicker,
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No items added. Tap "+ Add Item" above.'),
            ),
          ...selectedItems.asMap().entries.map((entry) {
            int idx = entry.key;
            var item = entry.value;
            return Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Text(item.product.icon, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: item.qty.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                        onChanged: (val) => setState(() => item.qty = double.tryParse(val) ?? 0.0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: item.rate.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Rate', isDense: true),
                        onChanged: (val) => setState(() => item.rate = double.tryParse(val) ?? 0.0),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() => selectedItems.removeAt(idx)),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:'), Text('Rs. ${subtotal.toStringAsFixed(0)}')]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Previous Balance:'), Text('Rs. ${previousDue.toStringAsFixed(0)}')]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total Payable:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Rs. ${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1565C0))),
                  ]),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Cash (Full)')),
                          selected: paymentMode == 'Cash',
                          onSelected: (v) => setState(() => paymentMode = 'Cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Udhar / Partial')),
                          selected: paymentMode == 'Credit',
                          onSelected: (v) => setState(() => paymentMode = 'Credit'),
                        ),
                      ),
                    ],
                  ),
                  if (paymentMode == 'Credit') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount Paid Now (Rs)', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Remaining Balance (Udhar):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        Text('Rs. ${remainingDue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: selectedItems.isEmpty
                ? null
                : () {
                    final inv = Invoice(
                      invNumber: appStore.getNextInvoiceNumber(),
                      date: DateTime.now().toString().substring(0, 16),
                      customerName: _nameCtrl.text.isEmpty ? 'Walk-in Customer' : _nameCtrl.text,
                      customerPhone: _phoneCtrl.text,
                      items: List.from(selectedItems),
                      subtotal: subtotal,
                      discount: discount,
                      grand: grand,
                      paid: paidAmount,
                      previousDue: previousDue,
                      remaining: remainingDue,
                      paymentMethod: paymentMode,
                    );
                    appStore.saveInvoice(inv);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${inv.invNumber} saved successfully!'), backgroundColor: Colors.green),
                    );
                  },
            child: const Text('Save & Generate Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------- 3. CUSTOMER LEDGER (UDHAR) ----------------
class CustomerLedgerScreen extends StatelessWidget {
  const CustomerLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = appStore.customers.values.where((c) => c.balance > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Udhar Khata'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: list.isEmpty
          ? const Center(child: Text('No customer has outstanding balance.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, idx) {
                final cust = list[idx];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.person, color: Colors.white)),
                    title: Text(cust.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(cust.phone.isEmpty ? 'No Phone' : cust.phone),
                    trailing: Text('Rs. ${cust.balance.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                    onTap: () {
                      final ctrl = TextEditingController();
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Collect Udhar: ${cust.name}'),
                          content: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Amount Received (Rs)'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () {
                                final amt = double.tryParse(ctrl.text) ?? 0.0;
                                if (amt > 0) {
                                  appStore.recordPayment(cust.key, amt);
                                  Navigator.pop(ctx);
                                }
                              },
                              child: const Text('Record Payment'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 4. INVOICE HISTORY SCREEN ----------------
class InvoiceHistoryScreen extends StatelessWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = appStore.invoices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice History'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: list.isEmpty
          ? const Center(child: Text('No invoices recorded yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, idx) {
                final inv = list[idx];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text('${inv.invNumber} — ${inv.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${inv.date} | Total: Rs. ${inv.grand.toStringAsFixed(0)}'),
                    trailing: Text(
                      inv.remaining > 0 ? 'Due Rs. ${inv.remaining.toStringAsFixed(0)}' : 'Paid',
                      style: TextStyle(color: inv.remaining > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 5. PRODUCT CATALOG SCREEN ----------------
class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  void _addNewProductDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedIcon = '🧱';
    String selectedCategory = 'Tiles';

    final emojis = ['🧱', '⬜', '✨', '📦', '📏', '🕸️', '🌸', '🔨', '⭐'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Add New POP Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name (e.g. 2x2 Fancy)')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default Rate (Rs)')),
                const SizedBox(height: 12),
                const Text('Pick Icon:', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children: emojis
                      .map((e) => ChoiceChip(
                            label: Text(e, style: const TextStyle(fontSize: 18)),
                            selected: selectedIcon == e,
                            onSelected: (s) => setDState(() => selectedIcon = e),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty) {
                  appStore.addProduct(
                    nameCtrl.text,
                    selectedIcon,
                    selectedCategory,
                    double.tryParse(priceCtrl.text) ?? 0.0,
                  );
                  Navigator.pop(ctx);
                  setState(() {});
                }
              },
              child: const Text('Save Item'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Catalog'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Item'),
        onPressed: _addNewProductDialog,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: appStore.products.length,
        itemBuilder: (context, idx) {
          final p = appStore.products[idx];
          return Card(
            color: Colors.white,
            child: ListTile(
              leading: Text(p.icon, style: const TextStyle(fontSize: 26)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(p.category),
              trailing: Text('Rs. ${p.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          );
        },
      ),
    );
  }
}
